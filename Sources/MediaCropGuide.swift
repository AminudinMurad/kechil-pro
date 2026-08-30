import SwiftUI

/// Shared crop guide used by image and video Optimize previews. Coordinates are in
/// the preview's top-left UI space, matching the focus controls in both tools.
struct MediaCropGuide: View {
    let aspect: CGFloat?
    let sourceAspect: CGFloat?
    var focusX: Double = 0.5
    var focusY: Double = 0.5

    var body: some View {
        GeometryReader { geometry in
            if let rect = Self.cropRect(aspect: aspect, sourceAspect: sourceAspect,
                                        container: geometry.size, focusX: focusX, focusY: focusY) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.white.opacity(0.9),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .allowsHitTesting(false)
    }

    /// Returns the crop rectangle inside the aspect-fitted source image. Keeping this
    /// geometry separate prevents a portrait source from getting a guide positioned in
    /// the black letterbox area around it.
    static func cropRect(aspect: CGFloat?, sourceAspect: CGFloat?, container: CGSize,
                         focusX: Double = 0.5, focusY: Double = 0.5) -> CGRect? {
        guard let aspect, aspect > 0, container.width > 0, container.height > 0 else {
            return nil
        }
        let imageRatio = sourceAspect.flatMap { $0 > 0 ? $0 : nil } ??
            container.width / container.height
        let imageRect: CGRect
        if imageRatio > container.width / container.height {
            let height = container.width / imageRatio
            imageRect = CGRect(x: 0, y: (container.height - height) / 2,
                               width: container.width, height: height)
        } else {
            let width = container.height * imageRatio
            imageRect = CGRect(x: (container.width - width) / 2, y: 0,
                               width: width, height: container.height)
        }

        let cropWidth: CGFloat
        let cropHeight: CGFloat
        if imageRatio > aspect {
            cropHeight = imageRect.height
            cropWidth = cropHeight * aspect
        } else {
            cropWidth = imageRect.width
            cropHeight = cropWidth / aspect
        }
        let extraX = max(0, imageRect.width - cropWidth)
        let extraY = max(0, imageRect.height - cropHeight)
        let x = imageRect.minX + extraX * CGFloat(max(0, min(1, focusX)))
        // The controls describe 0 as Bottom and 1 as Top, while CGRect's UI space
        // grows downward; invert the focus value when positioning the guide.
        let y = imageRect.minY + extraY * (1 - CGFloat(max(0, min(1, focusY))) )
        return CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
    }
}
