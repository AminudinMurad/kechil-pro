#!/usr/bin/env bash
#
# Packages the app into a mountable .dmg in releases/, ready to hand to a tester.
#
#   tools/make-dmg.sh                 build universal + package
#   UNIVERSAL=0 tools/make-dmg.sh     this Mac's architecture only (faster)
#   SIGNED=0 tools/make-dmg.sh        skip sandbox entitlements (not for release QA)
#   SKIP_BUILD=1 tools/make-dmg.sh    package build/Kechil PRO.app as it stands
#   VERSION=1.0.1 tools/make-dmg.sh   override the version in the filename
#   SIGN_IDENTITY="Developer ID Application: ..."   also sign the .dmg itself
#
set -euo pipefail
trap 'echo "make-dmg failed at line $LINENO: $BASH_COMMAND" >&2' ERR

APP_NAME="Kechil PRO"
VOL_NAME="Kechil PRO"        # the title of the mounted volume

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
# File Provider-backed project folders can immediately reattach FinderInfo after an
# xattr clear. Stage in the system temp directory, so signature cleanup stays stable
# while hdiutil copies the app into the delivery image.
STAGE="$(mktemp -d "${TMPDIR:-/private/tmp}/kechil-pro-dmg-stage.XXXXXX")"
RELEASES="$ROOT/releases"
trap 'rm -rf "$STAGE"' EXIT

UNIVERSAL="${UNIVERSAL:-1}"
SIGNED="${SIGNED:-1}"

# ---------------------------------------------------------------- build the app

if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
  [[ -d "$APP" ]] || { echo "error: SKIP_BUILD=1 but $APP does not exist" >&2; exit 1; }
  echo "==> Reusing existing $APP_NAME.app"
else
  UNIVERSAL="$UNIVERSAL" SIGNED="$SIGNED" "$ROOT/tools/build-app.sh"
fi

# ------------------------------------------------------- name the output artifact

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$APP/Contents/Info.plist")}"

# Label by what the binary actually contains, not by what was requested — a failed
# lipo would otherwise ship an arm64-only build under a "universal" filename. The
# executable name is read from the plist rather than hardcoded, so a future rename
# cannot leave this pointing at a path that no longer exists.
BIN_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" \
  "$APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/$BIN_NAME")"
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*) ARCH_LABEL="universal" ;;
  *)                             ARCH_LABEL="$ARCHS" ;;
esac

BASENAME="Kechil-PRO-v$VERSION-macos-$ARCH_LABEL"
DMG="$RELEASES/$BASENAME.dmg"
mkdir -p "$RELEASES"

# --------------------------------------------------- check what we are about to ship

echo "==> Checking the bundle"
echo "    universal binary: $ARCHS"

# Signed releases must remain sandboxed and may open outbound connections only for
# user-requested direct media downloads. They must never listen for inbound traffic.
if [[ "$SIGNED" == "1" ]]; then
  ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
  grep -q "com.apple.security.app-sandbox" <<<"$ENTS" \
    || { echo "error: app-sandbox entitlement missing from the signed bundle" >&2; exit 1; }
  grep -q "com.apple.security.network.client" <<<"$ENTS" \
    || { echo "error: direct-download network client entitlement missing" >&2; exit 1; }
  if grep -q "com.apple.security.network.server" <<<"$ENTS"; then
    echo "error: network-server entitlement is present — refusing to package" >&2
    exit 1
  fi
  echo "    sandbox on, outbound direct-download access only"
fi

# ------------------------------------------------------------------ stage contents

echo "==> Staging"
ditto "$APP" "$STAGE/$APP_NAME.app"          # ditto, not cp -R: preserves the signature
ln -s /Applications "$STAGE/Applications"    # so the window offers a drag target
find "$STAGE" -name '.DS_Store' -delete
xattr -cr "$STAGE"
# Explicitly clear both root markers too. They are Finder/File Provider bookkeeping,
# never application resources, and codesign correctly refuses bundles that retain them.
xattr -d com.apple.FinderInfo "$STAGE/$APP_NAME.app" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$STAGE/$APP_NAME.app" 2>/dev/null || true
codesign --verify --strict --deep "$STAGE/$APP_NAME.app"
echo "    staged app signature OK"

# --------------------------------------------------------------- build the image
#
# No custom background or icon layout: both are set by writing a .DS_Store into the
# mounted volume, which means attaching a read/write image. Not worth the fragility
# for a two-item window.

echo "==> Creating disk image"
if hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" \
     -ov -format UDZO -fs "HFS+" "$DMG" >/dev/null 2>&1; then
  echo "    via hdiutil create"
else
  # `create -srcfolder` attaches a scratch image to copy into, so it needs the
  # DiskImages device. Where that is unavailable it fails with "Device not
  # configured". makehybrid builds the filesystem in userspace instead, and convert
  # compresses the result — neither attaches anything.
  echo "    hdiutil create unavailable — falling back to makehybrid"
  RAW="$BUILD/dmg-raw.dmg"
  rm -f "$RAW"
  hdiutil makehybrid -hfs -hfs-volume-name "$VOL_NAME" -o "$RAW" "$STAGE" >/dev/null
  hdiutil convert "$RAW" -format UDZO -o "$DMG" -ov >/dev/null
  rm -f "$RAW"
fi

# A real Developer ID signature on the image is what notarization staples to. An
# ad-hoc one would add nothing, so it is skipped unless a real identity is given.
if [[ -n "${SIGN_IDENTITY:-}" && "${SIGN_IDENTITY:-}" != "-" ]]; then
  echo "==> Signing the image"
  codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

# ------------------------------------------------------------------------ verify

echo "==> Verifying"
if hdiutil verify "$DMG" >/dev/null 2>&1; then
  echo "    checksum OK"
else
  echo "    NOTE: hdiutil verify needs the DiskImages device and could not run here"
fi

( cd "$RELEASES" && shasum -a 256 "$BASENAME.dmg" > "$BASENAME.dmg.sha256" )

rm -rf "$STAGE"

echo ""
echo "Built: $DMG"
du -h "$DMG" | awk '{print "  size:   " $1}'
echo "  sha256: $(awk '{print $1}' "$DMG.sha256")"
echo ""
echo "Mount:  open \"$DMG\""
exit 0
