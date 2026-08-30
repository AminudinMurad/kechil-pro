import CoreGraphics

/// One crop-rectangle contract shared by the image preview guide and export pipeline.
/// Custom dimensions are independent pixel values; each edge is clamped to the source
/// so a batch can safely contain images smaller than the requested crop.
enum ImageCropGeometry {
    static func cropSize(source: CGSize, aspect: CGFloat?, customSize: CGSize?) -> CGSize {
        guard source.width > 0, source.height > 0 else { return .zero }

        if let customSize, customSize.width > 0, customSize.height > 0 {
            return CGSize(width: min(source.width, max(1, customSize.width.rounded())),
                          height: min(source.height, max(1, customSize.height.rounded())))
        }

        guard let aspect, aspect.isFinite, aspect > 0 else { return source }
        let sourceRatio = source.width / source.height
        if sourceRatio > aspect {
            return CGSize(width: source.height * aspect, height: source.height)
        }
        return CGSize(width: source.width, height: source.width / aspect)
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
}
