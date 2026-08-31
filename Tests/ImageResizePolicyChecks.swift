import CoreGraphics
import Foundation

@main
struct ImageResizePolicyChecks {
    static func main() {
        expect(ImageResizePolicy.allowsUpscalingByDefault,
               "Image Optimize permits upscaling by default")
        expect(ImageResizePolicy.finalScale(requested: 1.75, allowsUpscaling: true) == 1.75,
               "enabled upscaling keeps an above-native requested scale")
        expect(ImageResizePolicy.finalScale(requested: 1.75, allowsUpscaling: false) == 1,
               "disabled upscaling caps an above-native requested scale")
        expect(ImageResizePolicy.finalScale(requested: 0.6, allowsUpscaling: false) == 0.6,
               "disabled upscaling still permits downscaling")
        print("Image resize policy checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        print("PASS: \(message)")
    }
}
