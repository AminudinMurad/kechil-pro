import CoreGraphics

/// The shared resize contract for Image Optimize.
///
/// Cropping never manufactures pixels, but a subsequent resize may do so when the
/// user expressly permits it. Keeping that decision here makes the UI, preview and
/// exported image agree on what the upscaling toggle means.
enum ImageResizePolicy {
    /// Image Optimize starts in the permissive mode requested by the product UI.
    static let allowsUpscalingByDefault = true

    /// Returns the scale that the renderer may apply after a crop. With upscaling
    /// disabled, downscales still work while a scale above native cropped pixels is
    /// capped at one.
    static func finalScale(requested: CGFloat, allowsUpscaling: Bool) -> CGFloat {
        guard requested.isFinite, requested > 0 else { return 1 }
        return allowsUpscaling ? requested : min(1, requested)
    }
}
