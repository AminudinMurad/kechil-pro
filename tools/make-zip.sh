#!/usr/bin/env bash
#
# Packages the verified app bundle into a distributable ZIP beside the DMG.
#
#   tools/make-zip.sh                 build universal + package
#   UNIVERSAL=0 tools/make-zip.sh     this Mac's architecture only
#   SIGNED=0 tools/make-zip.sh        ad-hoc build without sandbox entitlements
#   SKIP_BUILD=1 tools/make-zip.sh    package build/Kechil PRO.app as it stands
#
set -euo pipefail
trap 'echo "make-zip failed at line $LINENO: $BASH_COMMAND" >&2' ERR

APP_NAME="Kechil PRO"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
RELEASES="$ROOT/releases"
UNIVERSAL="${UNIVERSAL:-1}"
SIGNED="${SIGNED:-1}"

if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
  [[ -d "$APP" ]] || { echo "error: SKIP_BUILD=1 but $APP does not exist" >&2; exit 1; }
  echo "==> Reusing existing $APP_NAME.app"
else
  UNIVERSAL="$UNIVERSAL" SIGNED="$SIGNED" "$ROOT/tools/build-app.sh"
fi

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$APP/Contents/Info.plist")}"
BIN_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" \
  "$APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/$BIN_NAME")"
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*) ARCH_LABEL="universal" ;;
  *)                             ARCH_LABEL="$ARCHS" ;;
esac

BASENAME="Kechil-PRO-v$VERSION-macos-$ARCH_LABEL"
ZIP="$RELEASES/$BASENAME.zip"
mkdir -p "$RELEASES"

echo "==> Checking bundle"
xattr -cr "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
codesign --verify --deep --strict "$APP"
echo "    app signature OK"
echo "    architectures: $ARCHS"

echo "==> Creating ZIP"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --norsrc --noqtn --keepParent "$APP" "$ZIP"
unzip -tqq "$ZIP"
if zipinfo -1 "$ZIP" | grep -E '(^|/)(\.DS_Store|__MACOSX)(/|$)|(^|/)\._' >/dev/null; then
  echo "error: archive contains Finder or macOS metadata" >&2
  exit 1
fi
( cd "$RELEASES" && shasum -a 256 "$BASENAME.zip" > "$BASENAME.zip.sha256" )

echo ""
echo "Built: $ZIP"
du -h "$ZIP" | awk '{print "  size:   " $1}'
echo "  sha256: $(awk '{print $1}' "$ZIP.sha256")"
