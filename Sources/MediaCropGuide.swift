import SwiftUI

/// Shared crop guide used by image and video Optimize previews. Coordinates are in
/// the preview's top-left UI space, matching the focus controls in both tools.
struct MediaCropGuide: View {
    let aspect: CGFloat?
    let sourceAspect: CGFloat?
    var cropPixelSize: CGSize?
    var sourcePixelSize: CGSize?
    var focusX: Double = 0.5
    var focusY: Double = 0.5

    init(aspect: CGFloat?, sourceAspect: CGFloat?, cropPixelSize: CGSize? = nil,
         sourcePixelSize: CGSize? = nil, focusX: Double = 0.5, focusY: Double = 0.5) {
        self.aspect = aspect
        self.sourceAspect = sourceAspect
        self.cropPixelSize = cropPixelSize
        self.sourcePixelSize = sourcePixelSize
        self.focusX = focusX
        self.focusY = focusY
    }

    var body: some View {
        GeometryReader { geometry in
            if let rect = Self.cropRect(aspect: aspect, sourceAspect: sourceAspect,
                                        cropPixelSize: cropPixelSize,
                                        sourcePixelSize: sourcePixelSize,
                                        container: geometry.size, focusX: focusX, focusY: focusY) {
                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .mask {
                        Rectangle().overlay {
                            Rectangle().frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
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
    static func cropRect(aspect: CGFloat?, sourceAspect: CGFloat?,
                         cropPixelSize: CGSize? = nil, sourcePixelSize: CGSize? = nil,
                         container: CGSize,
                         focusX: Double = 0.5, focusY: Double = 0.5) -> CGRect? {
        let hasCustomSize = cropPixelSize.map { $0.width > 0 && $0.height > 0 } ?? false
        guard (aspect.map { $0 > 0 } ?? false) || hasCustomSize,
              container.width > 0, container.height > 0 else {
            return nil
        }
        let imageRatio = sourcePixelSize.flatMap {
            $0.width > 0 && $0.height > 0 ? $0.width / $0.height : nil
        } ?? sourceAspect.flatMap { $0 > 0 ? $0 : nil } ??
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

        let cropSize: CGSize
        if let cropPixelSize, let sourcePixelSize,
           cropPixelSize.width > 0, cropPixelSize.height > 0,
           sourcePixelSize.width > 0, sourcePixelSize.height > 0 {
            let bounded = ImageCropGeometry.cropSize(source: sourcePixelSize,
                                                     aspect: nil,
                                                     customSize: cropPixelSize)
            cropSize = CGSize(width: bounded.width * imageRect.width / sourcePixelSize.width,
                              height: bounded.height * imageRect.height / sourcePixelSize.height)
        } else if let aspect, imageRatio > aspect {
            cropSize = CGSize(width: imageRect.height * aspect, height: imageRect.height)
        } else if let aspect {
            cropSize = CGSize(width: imageRect.width, height: imageRect.width / aspect)
        } else {
            return nil
        }
        let extraX = max(0, imageRect.width - cropSize.width)
        let extraY = max(0, imageRect.height - cropSize.height)
        let x = imageRect.minX + extraX * CGFloat(max(0, min(1, focusX)))
        // The controls describe 0 as Bottom and 1 as Top, while CGRect's UI space
        // grows downward; invert the focus value when positioning the guide.
        let y = imageRect.minY + extraY * (1 - CGFloat(max(0, min(1, focusY))) )
        return CGRect(x: x, y: y, width: cropSize.width, height: cropSize.height)
    }
}
