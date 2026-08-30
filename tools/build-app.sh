#!/usr/bin/env bash
#
# Builds "Kechil PRO.app" from Sources/ — no Xcode project required, just the
# Swift toolchain from Xcode or the Command Line Tools.
#
#   tools/build-app.sh              build for this Mac's architecture
#   UNIVERSAL=1 tools/build-app.sh  build a universal (arm64 + x86_64) binary
#   SIGNED=1 tools/build-app.sh     sign with sandbox + direct-download entitlement
#   RUN=1 tools/build-app.sh        build, then launch
#
set -euo pipefail
trap 'echo "Build failed at line $LINENO: $BASH_COMMAND" >&2' ERR

APP_NAME="Kechil PRO"        # user-visible bundle name
BIN_NAME="KechilPRO"         # must match CFBundleExecutable in App/Info.plist
MIN_MACOS="13.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Sources"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
ENTITLEMENTS="$ROOT/App/KechilPRO.entitlements"

command -v xcrun >/dev/null 2>&1 || {
  echo "error: xcrun not found. Install Xcode or run: xcode-select --install" >&2
  exit 1
}

# shellcheck source=select-toolchain.sh
. "$ROOT/tools/select-toolchain.sh"

SDK="${KECHIL_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"

echo "==> Cleaning"
rm -rf "$APP" "$BUILD/obj"
mkdir -p "$BUILD/obj" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# -parse-as-library is required: without it swiftc looks for top-level statements
# instead of honouring the @main attribute in Sources/App.swift.
compile() {
  local arch="$1" out="$2"
  local webp_build="$BUILD/obj/libwebp-$arch"
  echo "==> Compiling ($arch)"

  # Build the vendored codec in an architecture-specific copy. The upstream simple
  # makefile writes objects beside its sources, so building in vendor/ would mix arm64
  # and x86_64 state and dirty the verified source tree.
  rm -rf "$webp_build"
  ditto "$ROOT/vendor/libwebp" "$webp_build"
  make -s -C "$webp_build" -f makefile.unix \
    CC="$(xcrun -f clang)" AR="$(xcrun -f ar)" \
    EXTRA_FLAGS="-arch $arch -target ${arch}-apple-macos${MIN_MACOS} -isysroot $SDK -fno-common -DWEBP_USE_THREAD -fvisibility=hidden" \
    src/libwebp.a sharpyuv/libsharpyuv.a

  xcrun clang \
    -arch "$arch" \
    -target "${arch}-apple-macos${MIN_MACOS}" \
    -isysroot "$SDK" \
    -O2 \
    -I "$webp_build/src" \
    -I "$webp_build" \
    -c "$SRC/KechilWebPBridge.c" \
    -o "$BUILD/obj/KechilWebPBridge-$arch.o"

  xcrun swiftc \
    -sdk "$SDK" \
    -module-cache-path "$BUILD/obj/module-cache" \
    -parse-as-library \
    -import-objc-header "$SRC/KechilWebPBridge.h" \
    -O \
    -target "${arch}-apple-macos${MIN_MACOS}" \
    -framework AppKit \
    -framework AVFoundation \
    -framework AVKit \
    -framework CoreImage \
    -framework CoreMedia \
    -framework CoreVideo \
    -framework ImageIO \
    -framework QuartzCore \
    -framework VideoToolbox \
    -o "$out" \
    "$SRC"/*.swift \
    "$BUILD/obj/KechilWebPBridge-$arch.o" \
    "$webp_build/src/libwebp.a" \
    "$webp_build/sharpyuv/libsharpyuv.a" \
    -Xlinker -dead_strip
}

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  compile arm64  "$BUILD/obj/$BIN_NAME-arm64"
  compile x86_64 "$BUILD/obj/$BIN_NAME-x86_64"
  echo "==> Creating universal binary"
  lipo -create -output "$APP/Contents/MacOS/$BIN_NAME" \
    "$BUILD/obj/$BIN_NAME-arm64" "$BUILD/obj/$BIN_NAME-x86_64"
else
  compile "$(uname -m)" "$APP/Contents/MacOS/$BIN_NAME"
fi
chmod +x "$APP/Contents/MacOS/$BIN_NAME"

echo "==> Assembling bundle"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -f "$ROOT/assets/AppIcon.icns" ]]; then
  cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
    "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# Ad-hoc signature is enough to run locally. SIGNED=1 additionally applies the
# sandbox entitlements, including outbound client access for user-requested direct
# image/video downloads. The app has no network-server entitlement.
#
# Strip extended attributes first: `cp` carries them over from App/, and codesign
# rejects any bundle containing them with "resource fork, Finder information, or
# similar detritus not allowed".
echo "==> Signing"
xattr -cr "$APP"
# On File Provider-backed folders macOS can immediately restore FinderInfo and its
# provider marker on the bundle root after a recursive clear. Either attribute makes
# codesign reject the otherwise clean bundle as "resource fork, Finder information,
# or similar detritus not allowed", so remove those two root attributes explicitly.
# They are Finder bookkeeping, not application resources.
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
if [[ "${SIGNED:-0}" == "1" ]]; then
  codesign --force --sign "${SIGN_IDENTITY:--}" \
    --entitlements "$ENTITLEMENTS" --options runtime "$APP"
else
  codesign --force --sign - "$APP"
fi

echo "==> Verifying"
# File Provider may add Finder bookkeeping again between signing and verification.
# It is not part of the app and must not make an otherwise valid installed copy fail.
xattr -cr "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
codesign --verify --deep --strict "$APP" && echo "    signature OK"
du -sh "$APP" | awk '{print "    bundle size: " $1}'

echo ""
echo "Built: $APP"
echo "Run:   open \"$APP\""

[[ "${RUN:-0}" == "1" ]] && open "$APP"
exit 0
