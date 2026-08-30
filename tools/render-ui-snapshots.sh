#!/usr/bin/env bash
# Renders the real six-route SwiftUI dashboard plus Settings without taking a
# screen capture. This works on CI and on Macs where Screen Recording is denied.
set -euo pipefail
trap 'echo "UI snapshot run failed at line $LINENO: $BASH_COMMAND" >&2' ERR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
OUTPUT="$BUILD/ui-snapshots"
HOST_ARCH="$(uname -m)"

# shellcheck source=select-toolchain.sh
. "$ROOT/tools/select-toolchain.sh"
SDK="${KECHIL_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"

if [[ "${SKIP_APP_BUILD:-0}" != "1" ]]; then
  echo "==> Building host-architecture app and codec objects"
  SIGNED=1 bash "$ROOT/tools/build-app.sh"
else
  [[ -f "$BUILD/obj/KechilWebPBridge-$HOST_ARCH.o" &&
     -f "$BUILD/obj/libwebp-$HOST_ARCH/src/libwebp.a" ]] || {
    echo "error: host-architecture codec objects are missing; omit SKIP_APP_BUILD" >&2
    exit 1
  }
fi

sources=()
for source in "$ROOT"/Sources/*.swift; do
  [[ "$(basename "$source")" == "App.swift" ]] || sources+=("$source")
done

echo "==> Compiling UI snapshot renderer"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$BUILD/obj/ui-snapshot-module-cache" \
  -parse-as-library \
  -import-objc-header "$ROOT/Sources/KechilWebPBridge.h" \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework AppKit \
  -framework AVFoundation \
  -framework AVKit \
  -framework CoreImage \
  -framework CoreMedia \
  -framework CoreVideo \
  -framework ImageIO \
  -framework QuartzCore \
  -framework VideoToolbox \
  -o "$BUILD/obj/ui-snapshot-renderer" \
  "${sources[@]}" \
  "$ROOT/Tests/UISnapshotRenderer.swift" \
  "$BUILD/obj/KechilWebPBridge-$HOST_ARCH.o" \
  "$BUILD/obj/libwebp-$HOST_ARCH/src/libwebp.a" \
  "$BUILD/obj/libwebp-$HOST_ARCH/sharpyuv/libsharpyuv.a"

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"
"$BUILD/obj/ui-snapshot-renderer" "$OUTPUT" "$ROOT/assets/icon-master.png"

count="$(find "$OUTPUT" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
[[ "$count" == "18" ]] || {
  echo "error: expected 18 UI snapshots, found $count" >&2
  exit 1
}
echo "Rendered: $OUTPUT"
