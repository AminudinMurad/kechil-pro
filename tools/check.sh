#!/usr/bin/env bash
#
# Fast correctness gate. Run before every commit.
#   1. Type-checks every Swift source with warnings treated as errors.
#   2. Checks the dashboard preset geometry.
#   3. Checks the bundle identity is self-consistent, so the app cannot build, sign
#      and verify cleanly and then refuse to launch.
#   4. Re-renders the app icon and requires the tracked artwork to come back
#      byte-identical, so assets/ can never drift from the Swift that generates it.
#   5. Runs the reference algorithm test, which proves metadata is removed AND
#      that decoded pixels are byte-identical (no recompression).
#
set -euo pipefail
trap 'echo "Check failed at line $LINENO: $BASH_COMMAND" >&2' ERR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=select-toolchain.sh
. "$ROOT/tools/select-toolchain.sh"

SDK="${KECHIL_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
HOST_ARCH="$(uname -m)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/build/check-$STAMP"
mkdir -p "$OUT/module-cache"

echo "==> Verifying vendored libwebp source"
( cd "$ROOT" && shasum -a 256 -c vendor/libwebp.sha256 >/dev/null )
echo "    libwebp v1.6.0 source matches vendor/libwebp.sha256"

echo "==> Type-checking Swift sources ($HOST_ARCH, warnings-as-errors)"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -import-objc-header "$ROOT/Sources/KechilWebPBridge.h" \
  -typecheck \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  "$ROOT"/Sources/*.swift
echo "    Swift OK"

echo "==> Checking build and release scripts"
bash -n "$ROOT/tools/build-app.sh" "$ROOT/tools/make-dmg.sh" "$ROOT/tools/make-zip.sh"
echo "    shell syntax OK"

echo "==> Checking shared Save All and Clean All actions"
xcrun swiftc -sdk "$SDK" -module-cache-path "$OUT/module-cache" \
  -parse-as-library -O -warnings-as-errors -target "$HOST_ARCH-apple-macosx13.0" \
  -framework SwiftUI -framework AppKit -o "$OUT/batch-action-checks" \
  "$ROOT/Sources/BatchSaveControls.swift" "$ROOT/Sources/CleanBatchFooter.swift" \
  "$ROOT/Tests/BatchActionChecks.swift"
"$OUT/batch-action-checks"

echo "==> Checking GitHub update version comparison"
xcrun swiftc -sdk "$SDK" -module-cache-path "$OUT/module-cache" \
  -parse-as-library -O -warnings-as-errors -target "$HOST_ARCH-apple-macosx13.0" \
  -framework SwiftUI -o "$OUT/update-checker-checks" \
  "$ROOT/Sources/UpdateChecker.swift" "$ROOT/Tests/UpdateCheckerChecks.swift"
"$OUT/update-checker-checks"

echo "==> Checking shared media queue selection"
xcrun swiftc -sdk "$SDK" -module-cache-path "$OUT/module-cache" \
  -parse-as-library -O -warnings-as-errors -target "$HOST_ARCH-apple-macosx13.0" \
  -framework AppKit -o "$OUT/media-selection-checks" \
  "$ROOT/Sources/MediaSelection.swift" "$ROOT/Tests/MediaSelectionChecks.swift"
"$OUT/media-selection-checks"

echo "==> Checking inspect-first Clean workflow contracts"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework CoreMedia \
  -o "$OUT/clean-workflow-checks" \
  "$ROOT/Sources/MediaContracts.swift" \
  "$ROOT/Sources/CleanContracts.swift" \
  "$ROOT/Tests/CleanWorkflowChecks.swift"
"$OUT/clean-workflow-checks"

echo "==> Checking image crop preview geometry"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework SwiftUI \
  -o "$OUT/image-crop-geometry-checks" \
  "$ROOT/Sources/ImageCropGeometry.swift" \
  "$ROOT/Sources/MediaCropGuide.swift" \
  "$ROOT/Tests/MediaCropGuideChecks.swift"
"$OUT/image-crop-geometry-checks"

echo "==> Checking image crop enlargement policy"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework CoreGraphics \
  -o "$OUT/image-crop-upscale-policy-checks" \
  "$ROOT/Sources/ImageCropGeometry.swift" \
  "$ROOT/Tests/ImageCropUpscalePolicyChecks.swift"
"$OUT/image-crop-upscale-policy-checks"

echo "==> Checking Image Optimize upscaling policy"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework CoreGraphics \
  -o "$OUT/image-resize-policy-checks" \
  "$ROOT/Sources/ImageResizePolicy.swift" \
  "$ROOT/Tests/ImageResizePolicyChecks.swift"
"$OUT/image-resize-policy-checks"

echo "==> Checking compact scrollbar geometry"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -o "$OUT/scrollbar-geometry-checks" \
  "$ROOT/Sources/ScrollbarGeometry.swift" "$ROOT/Tests/ScrollbarGeometryChecks.swift"
"$OUT/scrollbar-geometry-checks"

echo "==> Checking six-route media contract"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework CoreMedia \
  -o "$OUT/media-route-checks" \
  "$ROOT/Sources/MediaContracts.swift" "$ROOT/Tests/MediaRouteChecks.swift"
"$OUT/media-route-checks"

echo "==> Checking Paste URL and direct-download contract"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework AppKit \
  -framework SwiftUI \
  -framework UniformTypeIdentifiers \
  -o "$OUT/paste-url-checks" \
  "$ROOT/Sources/MediaContracts.swift" \
  "$ROOT/Sources/PasteURL.swift" \
  "$ROOT/Tests/PasteURLChecks.swift"
"$OUT/paste-url-checks"

echo "==> Checking Clean preset contract"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework AVFoundation \
  -o "$OUT/clean-preset-checks" \
  "$ROOT/Sources/MediaContracts.swift" \
  "$ROOT/Sources/MediaContainerSanitizer.swift" \
  "$ROOT/Sources/VideoMetadataProbe.swift" \
  "$ROOT/Tests/CleanPresetChecks.swift"
"$OUT/clean-preset-checks"

echo "==> Checking video Clean scope selection"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework AVFoundation \
  -o "$OUT/video-clean-scope-checks" \
  "$ROOT/Sources/MediaContracts.swift" \
  "$ROOT/Sources/VideoCleanScope.swift" \
  "$ROOT/Sources/MediaContainerSanitizer.swift" \
  "$ROOT/Sources/VideoMetadataProbe.swift" \
  "$ROOT/Tests/VideoCleanScopeChecks.swift"
"$OUT/video-clean-scope-checks"

echo "==> Checking scoped image GPS removal"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework ImageIO \
  -framework Security \
  -o "$OUT/scoped-gps-image-checks" \
  "$ROOT/Sources/MediaContracts.swift" \
  "$ROOT/Sources/MetadataStripper.swift" \
  "$ROOT/Sources/MediaContainerSanitizer.swift" \
  "$ROOT/Sources/ImageIOStripper.swift" \
  "$ROOT/Sources/ImageRenderingMetadata.swift" \
  "$ROOT/Sources/PNGTextMetadata.swift" \
  "$ROOT/Sources/ProvenanceProbe.swift" \
  "$ROOT/Sources/CleanPreset.swift" \
  "$ROOT/Sources/ScopedMetadataStripper.swift" \
  "$ROOT/Tests/ScopedGPSImageChecks.swift"
"$OUT/scoped-gps-image-checks"

echo "==> Checking lossless image preservation and safe unsupported cases"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework ImageIO \
  -framework Security \
  -o "$OUT/image-preservation-checks" \
  "$ROOT/Sources/MetadataStripper.swift" \
  "$ROOT/Sources/MediaContainerSanitizer.swift" \
  "$ROOT/Sources/ImageIOStripper.swift" \
  "$ROOT/Sources/ImageRenderingMetadata.swift" \
  "$ROOT/Sources/PNGTextMetadata.swift" \
  "$ROOT/Sources/ProvenanceProbe.swift" \
  "$ROOT/Tests/ImagePreservationChecks.swift"
"$OUT/image-preservation-checks"

echo "==> Checking scoped image AI decoding and mixed-field safety"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework ImageIO \
  -framework Security \
  -o "$OUT/scoped-image-safety-checks" \
  "$ROOT/Sources/MediaContracts.swift" \
  "$ROOT/Sources/MetadataStripper.swift" \
  "$ROOT/Sources/MediaContainerSanitizer.swift" \
  "$ROOT/Sources/ImageIOStripper.swift" \
  "$ROOT/Sources/ImageRenderingMetadata.swift" \
  "$ROOT/Sources/PNGTextMetadata.swift" \
  "$ROOT/Sources/ProvenanceProbe.swift" \
  "$ROOT/Sources/CleanPreset.swift" \
  "$ROOT/Sources/ScopedMetadataStripper.swift" \
  "$ROOT/Tests/ScopedImageSafetyChecks.swift"
"$OUT/scoped-image-safety-checks"

echo "==> Checking video trim, crop and target-size policy"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -o "$OUT/video-optimize-checks" \
  "$ROOT/Sources/VideoOptimizeSettings.swift" "$ROOT/Tests/VideoOptimizeChecks.swift"
"$OUT/video-optimize-checks"

echo "==> Checking shared watermark layout contract"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -o "$OUT/watermark-layout-checks" \
  "$ROOT/Sources/WatermarkLayoutEngine.swift" "$ROOT/Tests/WatermarkRendererChecks.swift"
"$OUT/watermark-layout-checks"

echo "==> Exercising video Clean, Optimize, audio and Watermark pipelines"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework AVFoundation \
  -framework CoreImage \
  -framework AppKit \
  -framework ImageIO \
  -o "$OUT/video-pipeline-checks" \
  "$ROOT/Sources/MediaContracts.swift" \
  "$ROOT/Sources/VideoCleanScope.swift" \
  "$ROOT/Sources/MediaCapabilityProbe.swift" \
  "$ROOT/Sources/MediaContainerSanitizer.swift" \
  "$ROOT/Sources/VideoMetadataProbe.swift" \
  "$ROOT/Sources/MediaSizeEstimate.swift" \
  "$ROOT/Sources/VideoCleanPipeline.swift" \
  "$ROOT/Sources/VideoOptimizeSettings.swift" \
  "$ROOT/Sources/VideoTranscodeEngine.swift" \
  "$ROOT/Sources/WatermarkLayoutEngine.swift" \
  "$ROOT/Sources/WatermarkRenderer.swift" \
  "$ROOT/Sources/VideoWatermarkPipeline.swift" \
  "$ROOT/Tests/VideoPipelineIntegrationChecks.swift"
"$OUT/video-pipeline-checks"

echo "==> Checking scoped video Clean against the bundled provenance fixture"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -o "$OUT/container-sanitizer-checks" \
  "$ROOT/Sources/MediaContainerSanitizer.swift" \
  "$ROOT/Tests/ContainerSanitizerChecks.swift"
"$OUT/container-sanitizer-checks" \
  "$ROOT/Test Samples/Kechil-OpenAI-Generative-ID-5s.mov"

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework AVFoundation \
  -framework CoreImage \
  -framework AppKit \
  -framework ImageIO \
  -o "$OUT/scoped-video-checks" \
  "$ROOT/Sources/MediaContracts.swift" \
  "$ROOT/Sources/VideoCleanScope.swift" \
  "$ROOT/Sources/MediaCapabilityProbe.swift" \
  "$ROOT/Sources/MediaContainerSanitizer.swift" \
  "$ROOT/Sources/VideoMetadataProbe.swift" \
  "$ROOT/Sources/MediaSizeEstimate.swift" \
  "$ROOT/Sources/VideoCleanPipeline.swift" \
  "$ROOT/Tests/ScopedVideoFixtureChecks.swift"
"$OUT/scoped-video-checks" \
  "$ROOT/Test Samples/Kechil-OpenAI-Generative-ID-5s.mov" \
  "openai-test-genid-4f61d8b7-531e-4f19-9ea6-bf4191696e13"

echo "==> Checking video Clean no-op and scope isolation"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework AVFoundation \
  -framework AppKit \
  -o "$OUT/video-clean-safety-checks" \
  "$ROOT/Sources/MediaContracts.swift" \
  "$ROOT/Sources/VideoCleanScope.swift" \
  "$ROOT/Sources/MediaCapabilityProbe.swift" \
  "$ROOT/Sources/MediaContainerSanitizer.swift" \
  "$ROOT/Sources/VideoMetadataProbe.swift" \
  "$ROOT/Sources/MediaSizeEstimate.swift" \
  "$ROOT/Sources/VideoCleanPipeline.swift" \
  "$ROOT/Sources/MediaSaveService.swift" \
  "$ROOT/Tests/VideoCleanSafetyChecks.swift"
"$OUT/video-clean-safety-checks" \
  "$ROOT/Test Samples/Kechil-OpenAI-Generative-ID-5s.mov"

echo "==> Checking dashboard preset geometry"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -o "$OUT/preset-checks" \
  "$ROOT/Sources/DashboardPreset.swift" "$ROOT/Tests/PresetChecks.swift"
"$OUT/preset-checks"

echo "==> Checking size-target quality contract"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -o "$OUT/size-target-checks" \
  "$ROOT/Sources/SizeTargetEncoder.swift" "$ROOT/Tests/SizeTargetChecks.swift"
"$OUT/size-target-checks"

echo "==> Checking AI provenance detection and output verification"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -framework ImageIO \
  -framework Security \
  -o "$OUT/provenance-checks" \
  "$ROOT/Sources/MetadataStripper.swift" \
  "$ROOT/Sources/MediaContainerSanitizer.swift" \
  "$ROOT/Sources/ImageIOStripper.swift" \
  "$ROOT/Sources/ImageRenderingMetadata.swift" \
  "$ROOT/Sources/PNGTextMetadata.swift" \
  "$ROOT/Sources/ProvenanceProbe.swift" \
  "$ROOT/Tests/ProvenanceChecks.swift"
"$OUT/provenance-checks"

echo "==> Checking bundle identity is self-consistent"
# CFBundleExecutable and build-app.sh's BIN_NAME must be the same string, or the
# bundle assembles with the binary under one name and Info.plist pointing at
# another — which builds, signs and verifies cleanly, then fails to launch. That is
# expensive to diagnose and free to assert, so it is asserted.
PLIST_EXEC="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" \
  "$ROOT/App/Info.plist")"
SCRIPT_BIN="$(sed -n 's/^BIN_NAME="\([^"]*\)".*/\1/p' "$ROOT/tools/build-app.sh")"
[[ -n "$PLIST_EXEC" && "$PLIST_EXEC" == "$SCRIPT_BIN" ]] || {
  echo "error: CFBundleExecutable ('$PLIST_EXEC') != build-app.sh BIN_NAME ('$SCRIPT_BIN')" >&2
  echo "       the bundle would build and sign, then refuse to launch" >&2
  exit 1
}
# The entitlements file build-app.sh signs with has to exist, or SIGNED=1 dies
# after a full compile.
ENTS_PATH="$(sed -n 's|^ENTITLEMENTS="\$ROOT/\(.*\)"$|\1|p' "$ROOT/tools/build-app.sh")"
[[ -f "$ROOT/$ENTS_PATH" ]] || {
  echo "error: build-app.sh signs with App/$ENTS_PATH, which does not exist" >&2
  exit 1
}
CLIENT_ENTITLEMENT="$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.network.client' "$ROOT/$ENTS_PATH" 2>/dev/null || true)"
[[ "$CLIENT_ENTITLEMENT" == "true" ]] || {
  echo "error: direct-download network client entitlement is missing" >&2
  exit 1
}
SERVER_ENTITLEMENT="$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.network.server' "$ROOT/$ENTS_PATH" 2>/dev/null || true)"
[[ -z "$SERVER_ENTITLEMENT" ]] || {
  echo "error: network-server entitlement must remain absent" >&2
  exit 1
}
echo "    $PLIST_EXEC, $ENTS_PATH"

echo "==> Checking collision-safe saves and original protection"
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -o "$OUT/media-save-checks" \
  "$ROOT/Sources/MediaSaveService.swift" "$ROOT/Tests/MediaSaveChecks.swift"
"$OUT/media-save-checks"

echo "==> Verifying app icon artwork"
# The icon is generated, not a committed binary nobody can regenerate. Re-render it
# from tools/render-app-icon.swift and require the tracked PNGs back byte-identical:
# if the renderer changes and tools/render-artwork.sh is not re-run, this fails
# instead of shipping art that no longer matches its own source.
xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$OUT/module-cache" \
  -target "$HOST_ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/tools/render-app-icon.swift" \
  -o "$OUT/render-app-icon"
"$OUT/render-app-icon" "$OUT/icon-master.png"
cmp "$OUT/icon-master.png" "$ROOT/assets/icon-master.png"
sips -z 400 400 "$OUT/icon-master.png" --out "$OUT/icon.png" >/dev/null
cmp "$OUT/icon.png" "$ROOT/assets/icon.png"

# build-app.sh sets CFBundleIconFile only when this exact filename is present, and
# does it with `|| true` — a missing or renamed .icns yields an iconless app with no
# error anywhere in the build. Unpacking it here is what asserts it exists.
iconutil -c iconset "$ROOT/assets/AppIcon.icns" -o "$OUT/KechilPRO.iconset"
expected_icon_representations=(
  "icon_16x16.png:16"
  "icon_16x16@2x.png:32"
  "icon_32x32.png:32"
  "icon_32x32@2x.png:64"
  "icon_128x128.png:128"
  "icon_128x128@2x.png:256"
  "icon_256x256.png:256"
  "icon_256x256@2x.png:512"
  "icon_512x512.png:512"
  "icon_512x512@2x.png:1024"
)
for representation in "${expected_icon_representations[@]}"; do
  filename="${representation%%:*}"
  expected_size="${representation##*:}"
  icon_path="$OUT/KechilPRO.iconset/$filename"
  icon_width="$(sips -g pixelWidth "$icon_path" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
  icon_height="$(sips -g pixelHeight "$icon_path" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"
  [[ "$icon_width" == "$expected_size" && "$icon_height" == "$expected_size" ]] || {
    echo "error: $filename must be ${expected_size}x${expected_size}," \
      "found ${icon_width}x${icon_height}" >&2
    exit 1
  }
done

# iconutil rewrites PNG metadata while preserving pixels, so the 1024px
# representation is normalised to BMP before being compared with the master.
sips -s format bmp "$OUT/icon-master.png" --out "$OUT/icon-master.bmp" >/dev/null
sips -s format bmp "$OUT/KechilPRO.iconset/icon_512x512@2x.png" \
  --out "$OUT/icon-from-icns.bmp" >/dev/null
cmp "$OUT/icon-master.bmp" "$OUT/icon-from-icns.bmp"
echo "    icon-master.png, icon.png and AppIcon.icns all reproduce from source (10 sizes)"

echo "==> Verifying strip algorithm against real images"
if command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" 2>/dev/null; then
  python3 "$ROOT/Tests/verify_algorithm.py"
else
  echo "    SKIPPED — needs: python3 -m pip install Pillow" >&2
fi

echo ""
echo "==> Checking real crop exports, mixed-batch controls, and video playback"
bash "$ROOT/tools/check-media-interactions.sh" "$OUT/media-interactions"
echo "All checks passed."
