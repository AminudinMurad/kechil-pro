#!/usr/bin/env bash
# Real crop exports, mixed-batch control behavior, and AVPlayer transport checks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tools/select-toolchain.sh"
SDK="${KECHIL_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
ARCH="$(uname -m)"
OUT="${1:-$ROOT/build/media-interaction-checks}"
mkdir -p "$OUT"
CODEC="$ROOT/build/obj/libwebp-$ARCH"
BRIDGE="$ROOT/build/obj/KechilWebPBridge-$ARCH.o"
if [[ ! -f "$CODEC/src/libwebp.a" || ! -f "$CODEC/sharpyuv/libsharpyuv.a" || ! -f "$BRIDGE" ]]; then
  CODEC="$OUT/libwebp-$ARCH"
  BRIDGE="$OUT/KechilWebPBridge-$ARCH.o"
  ditto "$ROOT/vendor/libwebp" "$CODEC"
  make -s -C "$CODEC" -f makefile.unix \
    CC="$(xcrun -f clang)" AR="$(xcrun -f ar)" \
    EXTRA_FLAGS="-arch $ARCH -target $ARCH-apple-macos13.0 -isysroot $SDK -fno-common -DWEBP_USE_THREAD -fvisibility=hidden" \
    src/libwebp.a sharpyuv/libsharpyuv.a
  xcrun clang -arch "$ARCH" -target "$ARCH-apple-macos13.0" -isysroot "$SDK" -O2 \
    -I "$CODEC/src" -I "$CODEC" -c "$ROOT/Sources/KechilWebPBridge.c" -o "$BRIDGE"
fi
sources=()
for source in "$ROOT"/Sources/*.swift; do
  [[ "$(basename "$source")" == "App.swift" ]] || sources+=("$source")
done
xcrun swiftc -sdk "$SDK" -module-cache-path "$OUT/module-cache" -parse-as-library \
  -import-objc-header "$ROOT/Sources/KechilWebPBridge.h" -O -warnings-as-errors \
  -target "$ARCH-apple-macosx13.0" -framework AppKit -framework AVFoundation -framework AVKit \
  -framework CoreImage -framework CoreMedia -framework CoreVideo -framework ImageIO \
  -framework QuartzCore -framework VideoToolbox \
  -o "$OUT/media-interaction-checks" "${sources[@]}" \
  "$ROOT/Tests/MediaInteractionChecks.swift" "$BRIDGE" \
  "$CODEC/src/libwebp.a" "$CODEC/sharpyuv/libsharpyuv.a"
"$OUT/media-interaction-checks" "$OUT/fixtures" "$ROOT/Test Samples/Kechil-OpenAI-Generative-ID-5s.mov"
