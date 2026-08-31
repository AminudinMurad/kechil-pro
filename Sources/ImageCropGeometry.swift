import CoreGraphics

/// Policy for a custom crop whose requested pixel area is larger than one or more
/// queued sources. This is deliberately separate from Resize's post-crop policy:
/// crop enlargement makes the requested crop possible, while Resize controls the
/// dimensions after that crop has been made.
enum ImageCropUpscalePolicy: String, CaseIterable, Identifiable, Equatable, Sendable {
    case keepNative = "Keep native size"
    case fillTarget = "Enlarge smaller images to fill target"

    var id: String { rawValue }

    var enlargesSmallerImages: Bool { self == .fillTarget }
}

/// One crop-rectangle contract shared by the image preview guide and export pipeline.
/// Custom dimensions are independent pixel values; each edge is clamped to the source
/// when `keepNative` is selected. `fillTarget` first enlarges a source uniformly so
/// the requested custom dimensions can be retained exactly.
enum ImageCropGeometry {
    static func cropSize(source: CGSize, aspect: CGFloat?, customSize: CGSize?) -> CGSize {
        cropSize(source: source, aspect: aspect, customSize: customSize,
                 cropUpscalePolicy: .keepNative)
    }

    /// Returns the dimensions of the crop in the coordinate system of the supplied
    /// working image. When `fillTarget` is selected, callers should pre-scale the
    /// source by `cropUpscaleScale` before asking for the crop rectangle; the requested
    /// custom size then fits exactly in that working image.
    static func cropSize(source: CGSize, aspect: CGFloat?, customSize: CGSize?,
                         cropUpscalePolicy: ImageCropUpscalePolicy) -> CGSize {
        guard source.width > 0, source.height > 0 else { return .zero }

        if let customSize = normalizedCustomSize(customSize) {
            if cropUpscalePolicy.enlargesSmallerImages {
                return customSize
            }
            return CGSize(width: min(source.width, customSize.width),
                          height: min(source.height, customSize.height))
        }

        guard let aspect, aspect.isFinite, aspect > 0 else { return source }
        let sourceRatio = source.width / source.height
        if sourceRatio > aspect {
            return CGSize(width: source.height * aspect, height: source.height)
        }
        return CGSize(width: source.width, height: source.width / aspect)
    }

    /// Returns the uniform pre-scale needed for a custom crop to cover its target.
    /// Downscaling is never introduced by this crop policy: sources that already cover
    /// both dimensions keep a scale of one. The caller still crops after this scale,
    /// so a non-matching source ratio is handled by removing excess pixels rather than
    /// stretching either axis.
    static func cropUpscaleScale(source: CGSize, customSize: CGSize?,
                                 policy: ImageCropUpscalePolicy) -> CGFloat {
        guard policy.enlargesSmallerImages,
              source.width > 0, source.height > 0,
              let customSize = normalizedCustomSize(customSize) else { return 1 }
        let scale = max(customSize.width / source.width,
                        customSize.height / source.height)
        guard scale.isFinite else { return 1 }
        return max(1, scale)
    }

    /// Returns the area retained from the original source when a crop may enlarge it.
    /// This is the geometry used by the preview guide: an enlarged source can retain a
    /// smaller native region while still producing the exact requested output size.
    static func sourceCropSize(source: CGSize, aspect: CGFloat?, customSize: CGSize?,
                               cropUpscalePolicy: ImageCropUpscalePolicy = .keepNative) -> CGSize {
        let outputSize = cropSize(source: source, aspect: aspect, customSize: customSize,
                                  cropUpscalePolicy: cropUpscalePolicy)
        let scale = cropUpscaleScale(source: source, customSize: customSize,
                                     policy: cropUpscalePolicy)
        guard scale > 1 else { return outputSize }
        return CGSize(width: outputSize.width / scale,
                      height: outputSize.height / scale)
    }

    static func cropRect(source: CGRect, aspect: CGFloat?, customSize: CGSize?,
                         focusX: Double, focusY: Double) -> CGRect {
        let size = cropSize(source: source.size, aspect: aspect, customSize: customSize)
        let x = source.minX + (source.width - size.width) * CGFloat(clamp(focusX))
        let y = source.minY + (source.height - size.height) * CGFloat(clamp(focusY))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0.5))
    }

    private static func normalizedCustomSize(_ size: CGSize?) -> CGSize? {
        guard let size,
              size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        return CGSize(width: max(1, size.width.rounded()),
                      height: max(1, size.height.rounded()))
    }
}
