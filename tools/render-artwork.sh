#!/usr/bin/env bash
#
# Renders the app icon from tools/render-app-icon.swift into assets/. The icon is
# generated, not a committed binary nobody can regenerate — tools/check.sh re-renders
# it and compares, so the source of truth is the Swift file.
#
#   tools/render-artwork.sh
#
set -euo pipefail
trap 'echo "render-artwork failed at line $LINENO: $BASH_COMMAND" >&2' ERR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=select-toolchain.sh
. "$ROOT/tools/select-toolchain.sh"

SDK="${KECHIL_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
HOST_ARCH="$(uname -m)"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$ROOT/build/artwork-$STAMP"
MODULE_CACHE="$WORK/module-cache"
ICONSET="$WORK/KechilPRO.iconset"
mkdir -p "$ICONSET" "$MODULE_CACHE" "$ROOT/assets"

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$MODULE_CACHE" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/tools/render-app-icon.swift" \
  -o "$WORK/render-app-icon"
"$WORK/render-app-icon" "$ROOT/assets/icon-master.png"

sips -z 400 400 "$ROOT/assets/icon-master.png" --out "$ROOT/assets/icon.png" >/dev/null
sips -z 16 16   "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32   "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32   "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64   "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ROOT/assets/icon-master.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$ROOT/assets/icon-master.png" "$ICONSET/icon_512x512@2x.png"

# This exact filename is what tools/build-app.sh already looks for.
iconutil -c icns "$ICONSET" -o "$ROOT/assets/AppIcon.icns"

echo "Rendered assets/icon-master.png, assets/icon.png and assets/AppIcon.icns"
echo "Working directory: $WORK"
