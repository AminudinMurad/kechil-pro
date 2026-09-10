import Foundation

@main
enum ConvertedFilenameNamingChecks {
    static func main() {
        var failures = 0

        func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
            if condition() {
                print("PASS: \(label)")
            } else {
                failures += 1
                print("FAIL: \(label)")
            }
        }

        let source = URL(fileURLWithPath: "/tmp/holiday.photo.jpg")
        expect(ConvertedFilenameNaming.filename(
            sourceURL: source, outputExtension: "webp",
            appendage: ConvertedFilenameNaming.defaultAppendage) == "holiday.photo-kechil.webp",
               "current -kechil appendage remains the default")
        expect(ConvertedFilenameNaming.filename(
            sourceURL: source, outputExtension: "png", appendage: "-small") ==
            "holiday.photo-small.png", "custom appendage is applied before the extension")
        expect(ConvertedFilenameNaming.filename(
            sourceURL: source, outputExtension: "webp", appendage: "-kechil",
            includeResolution: true, width: 1920, height: 1080) ==
            "holiday.photo-kechil-1920x1080.webp",
               "image resolution follows the custom appendage")
        expect(ConvertedFilenameNaming.filename(
            sourceURL: URL(fileURLWithPath: "/tmp/clip.mov"), outputExtension: "mp4",
            appendage: "-optimized", includeResolution: true, width: 1280, height: 720) ==
            "clip-optimized-1280x720.mp4",
               "the same resolution naming works for converted videos")
        expect(ConvertedFilenameNaming.filename(
            sourceURL: source, outputExtension: "jpg", appendage: "") ==
            "holiday.photo.jpg", "an empty appendage keeps the original base name")
        expect(ConvertedFilenameNaming.sanitisedAppendage("  -client copy  ") ==
            "-client copy", "outer whitespace is removed without losing inner spaces")
        expect(ConvertedFilenameNaming.sanitisedAppendage("/client:draft\\one") ==
            "-client-draft-one", "path separators cannot escape into the filename")
        expect(ConvertedFilenameNaming.sanitisedAppendage(String(repeating: "a", count: 80)).count ==
            ConvertedFilenameNaming.maximumAppendageLength,
               "appendages are bounded to a safe length")

        if failures > 0 { exit(1) }
        print("ALL CONVERTED FILENAME NAMING CHECKS PASSED (8 assertions)")
    }
}
