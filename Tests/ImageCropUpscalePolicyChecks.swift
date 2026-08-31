import CoreGraphics
import Foundation

@main
struct ImageCropUpscalePolicyChecks {
    static func main() {
        let source = CGSize(width: 1000, height: 600)
        let target = CGSize(width: 1400, height: 375)

        expect(ImageCropUpscalePolicy.keepNative.id == "Keep native size",
               "native crop policy has a concise user-facing label")
        expect(ImageCropUpscalePolicy.fillTarget.enlargesSmallerImages,
               "fill-target policy enables crop-only enlargement")
        expect(ImageCropGeometry.cropUpscaleScale(source: source, customSize: target,
                                                   policy: .keepNative) == 1,
               "native crop policy never enlarges a source")
        expect(approximately(ImageCropGeometry.cropUpscaleScale(
                                source: source, customSize: target, policy: .fillTarget), 1.4),
               "fill-target scale covers the larger requested crop dimension")

        let nativeCrop = ImageCropGeometry.cropSize(source: source, aspect: nil,
                                                     customSize: target,
                                                     cropUpscalePolicy: .keepNative)
        expect(nativeCrop == CGSize(width: 1000, height: 375),
               "native crop keeps the source width when the target is wider")

        let filledCrop = ImageCropGeometry.cropSize(source: CGSize(width: 1400, height: 840),
                                                     aspect: nil, customSize: target,
                                                     cropUpscalePolicy: .fillTarget)
        expect(filledCrop == target,
               "filled working image crops to the exact custom target")

        let sourceCrop = ImageCropGeometry.sourceCropSize(
            source: source, aspect: nil, customSize: target, cropUpscalePolicy: .fillTarget)
        expect(approximately(sourceCrop.width, 1000) &&
               approximately(sourceCrop.height, CGFloat(375.0 / 1.4)),
               "preview guide shows the native area retained before enlargement")

        let coveredSource = CGSize(width: 2000, height: 1200)
        expect(ImageCropGeometry.cropUpscaleScale(source: coveredSource, customSize: target,
                                                   policy: .fillTarget) == 1,
               "fill-target policy leaves a source that already covers the target unchanged")
        expect(ImageCropGeometry.sourceCropSize(source: coveredSource, aspect: nil,
                                                customSize: target,
                                                cropUpscalePolicy: .fillTarget) == target,
               "covered source retains the requested target area")

        print("Image crop upscale policy checks passed")
    }

    private static func approximately(_ lhs: CGFloat, _ rhs: CGFloat,
                                      tolerance: CGFloat = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        print("PASS: \(message)")
    }
}
