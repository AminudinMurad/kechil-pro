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
struct VideoCleanScopeChecks {
    static func main() {
        print("\nVideo Clean scope selection")
        check(VideoCleanScope.allCases.map(\.title) == [
            "Content Credentials", "Descriptive metadata", "XMP", "Location", "Container dates",
        ], "video Clean exposes the five reference groups in order")
        check(VideoCleanScope.allCases.map(\.detail) == [
            "C2PA manifest and known provenance UUID boxes",
            "Title, author, comments and application metadata",
            "Adobe XMP packets stored in known MP4 boxes",
            "Known location metadata stored in user-data boxes",
            "Non-empty creation and modification timestamps",
        ], "video Clean cards keep the reference descriptions")
        check(VideoCleanScope.allCases.map(\.symbolName) == [
            "seal.fill", "text.alignleft", "doc.text.fill", "location.fill", "calendar",
        ], "video Clean groups use distinct metadata icons instead of checkbox icons")
        check(VideoCleanSelection.all.scopes == VideoCleanScope.allCases,
              "all five groups are selected by default")

        let credentials = VideoMetadataFinding(
            scope: .file, category: .provenance, identifier: "c2pa",
            displayName: "Content credentials", valueSummary: "OpenAI provenance",
            removable: true)
        let caption = VideoMetadataFinding(
            scope: .file, category: .descriptive, identifier: "©nam",
            displayName: "Title", valueSummary: "A short clip", removable: true)
        let provenanceCaption = VideoMetadataFinding(
            scope: .file, category: .descriptive, identifier: "mdta/com.apple.quicktime.description",
            displayName: "Description", valueSummary: "Synthetic C2PA test declaration", removable: true)
        let unknownProvenanceCaption = VideoMetadataFinding(
            scope: .file, category: .unknown, identifier: "mdta/com.apple.quicktime.description",
            displayName: "description", valueSummary: "Synthetic C2PA test declaration", removable: true)
        let xmp = VideoMetadataFinding(
            scope: .file, category: .unknown, identifier: "xmp",
            displayName: "XMP packet", valueSummary: "Adobe XMP", removable: true)
        let location = VideoMetadataFinding(
            scope: .file, category: .location,
            identifier: "com.apple.quicktime.location.ISO6709",
            displayName: "Location", valueSummary: "+03.14+101.68/", removable: true)
        let date = VideoMetadataFinding(
            scope: .file, category: .timestamp,
            identifier: "mvhd", displayName: "Container dates",
            valueSummary: "Creation and modification", removable: true)

        check(VideoCleanSelection.contentCredentials.matches(credentials),
              "Content Credentials selects provenance")
        check(!VideoCleanSelection.contentCredentials.matches(caption),
              "Content Credentials keeps descriptive metadata")
        check(!VideoCleanSelection.contentCredentials.matches(provenanceCaption),
              "Content Credentials does not treat descriptive C2PA text as a carrier")
        check(!VideoCleanSelection.contentCredentials.matches(unknownProvenanceCaption),
              "Content Credentials preserves unknown-key descriptions with carrier text")
        check(VideoCleanSelection.descriptiveMetadata.matches(caption),
              "Descriptive metadata selects title/description fields")
        check(VideoCleanSelection.xmp.matches(xmp), "XMP selects XMP packets")
        check(VideoCleanSelection.location.matches(location), "Location selects GPS fields")
        check(VideoCleanSelection.containerDates.matches(date), "Container dates selects date atoms")

        var toggled = VideoCleanSelection.all
        toggled.toggle(.location)
        check(!toggled.contains(.location) && toggled.scopes.count == 4,
              "a group can be toggled off without changing other groups")

        if failures == 0 {
            print("\nALL VIDEO CLEAN SCOPE CHECKS PASSED")
        } else {
            print("\n\(failures) VIDEO CLEAN SCOPE CHECK(S) FAILED")
            exit(1)
        }
    }
}
