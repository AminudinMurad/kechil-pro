import CoreGraphics
import Foundation

@main
struct MediaCropGuideChecks {
    static func main() {
        let centred = MediaCropGuide.cropRect(aspect: 1, sourceAspect: 16.0 / 9.0,
                                              container: CGSize(width: 640, height: 360))
        expect(centred?.width == 360 && centred?.height == 360,
               "square guide fits the displayed 16:9 source")
        expect(abs((centred?.midX ?? 0) - 320) < 0.01,
               "centre focus keeps the guide centred")

        let bottom = MediaCropGuide.cropRect(aspect: 5.0 / 4.0, sourceAspect: 1,
                                             container: CGSize(width: 400, height: 400),
                                             focusX: 0.5, focusY: 0)
        let top = MediaCropGuide.cropRect(aspect: 5.0 / 4.0, sourceAspect: 1,
                                          container: CGSize(width: 400, height: 400),
                                          focusX: 0.5, focusY: 1)
        expect((bottom?.minY ?? 0) > (top?.minY ?? 0),
               "zero vertical focus places the guide at the bottom")

        let custom = MediaCropGuide.cropRect(
            aspect: nil, sourceAspect: 2,
            cropPixelSize: CGSize(width: 800, height: 700),
            sourcePixelSize: CGSize(width: 2000, height: 1000),
            container: CGSize(width: 600, height: 400))
        expect(abs((custom?.width ?? 0) - 240) < 0.01 &&
               abs((custom?.height ?? 0) - 210) < 0.01,
               "custom width and height scale independently into the source preview")

        let bounded = ImageCropGeometry.cropSize(
            source: CGSize(width: 1000, height: 600), aspect: nil,
            customSize: CGSize(width: 1400, height: 375))
        expect(bounded == CGSize(width: 1000, height: 375),
               "custom dimensions clamp independently without proportional scaling")

        let filled = MediaCropGuide.cropRect(
            aspect: nil, sourceAspect: 1000.0 / 600.0,
            cropPixelSize: CGSize(width: 1400, height: 375),
            sourcePixelSize: CGSize(width: 1000, height: 600),
            cropUpscalePolicy: .fillTarget,
            container: CGSize(width: 600, height: 400))
        expect(abs((filled?.width ?? 0) - 600) < 0.01 &&
               abs((filled?.height ?? 0) - (600 * 375 / 1000 / 1.4)) < 0.01,
               "fill-target guide shows the native area retained before enlargement")
        print("Media crop guide checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
