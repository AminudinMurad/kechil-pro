import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() {
        print("  PASS  \(label)")
    } else {
        failures += 1
        print("  FAIL  \(label)")
    }
}

@main
struct CleanPresetChecks {
    static func main() {
        print("\nClean presets")
        let titles = CleanPreset.allCases.map(\.title)
        check(titles == ["Remove all metadata", "AI metadata", "Remove EXIF", "Remove GPS"],
              "four Clean choices use the approved labels")
        check(CleanPreset.allMetadata.removesAllMetadata &&
              !CleanPreset.aiMetadata.removesAllMetadata,
              "only Remove all metadata is the broad-scope operation")

        let gps = VideoMetadataFinding(scope: .file, category: .location,
                                       identifier: "com.apple.quicktime.location.ISO6709",
                                       displayName: "Location", valueSummary: "+03.14+101.68/",
                                       removable: true)
        let camera = VideoMetadataFinding(scope: .track(1), category: .device,
                                          identifier: "com.apple.quicktime.make",
                                          displayName: "Make", valueSummary: "Camera",
                                          removable: true)
        let ai = VideoMetadataFinding(scope: .file, category: .provenance,
                                      identifier: "c2pa", displayName: "Content credentials",
                                      valueSummary: "Created using Generative AI", removable: true)
        let caption = VideoMetadataFinding(scope: .file, category: .descriptive,
                                           identifier: "©nam", displayName: "Title",
                                           valueSummary: "A short clip", removable: true)
        check(CleanPreset.gps.matchesVideo(gps) && !CleanPreset.gps.matchesVideo(camera),
              "GPS scope selects location findings only")
        check(CleanPreset.exif.matchesVideo(camera) && !CleanPreset.exif.matchesVideo(gps),
              "EXIF scope selects camera/device findings only")
        check(CleanPreset.aiMetadata.matchesVideo(ai) &&
              !CleanPreset.aiMetadata.matchesVideo(caption),
              "AI scope selects provenance findings without deleting captions")
        check(CleanPreset.allMetadata.matchesVideo(caption),
              "Remove all metadata selects other removable findings")

        if failures == 0 {
            print("\nALL CLEAN PRESET CHECKS PASSED")
        } else {
            print("\n\(failures) CLEAN PRESET CHECK(S) FAILED")
            exit(1)
        }
    }
}
