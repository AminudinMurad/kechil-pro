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
        print("Media crop guide checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
