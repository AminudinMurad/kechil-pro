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
            "C2PA & provenance",
            "Title, author & comments",
            "Adobe XMP",
            "GPS & ISO 6709",
            "Created & modified",
        ], "video Clean cards use short readable descriptions")
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

        let device = VideoMetadataFinding(scope: .file, category: .device,
            identifier: "com.apple.quicktime.model", displayName: "Device", valueSummary: "Camera", removable: true)
        let timed = VideoMetadataFinding(scope: .timedTrack(1), category: .timed,
            identifier: "meta", displayName: "Timed metadata", valueSummary: "Present", removable: true)
        check(VideoCleanSelection.all.matches(device) && VideoCleanSelection.all.matches(timed),
              "all-groups verification includes device and timed findings")

        let stillPresent = VideoMetadataFinding(scope: .file, category: .descriptive,
            identifier: "©nam", displayName: "Title", valueSummary: "A changed title", removable: true)
        check(VideoCleanEvidence.noLongerDetected([caption, location], remaining: [stillPresent]) == [location],
              "a still-present field is not labelled removed when its value changes")
        check(VideoCleanEvidence.isProvenance(credentials) && !VideoCleanEvidence.declaresAISource(credentials),
              "generic C2PA/OpenAI text is provenance, not proof of AI generation")
        let declaredAI = VideoMetadataFinding(scope: .file, category: .provenance,
            identifier: "c2pa", displayName: "Content Credentials",
            valueSummary: "DigitalSourceType: trainedAlgorithmicMedia", removable: true)
        check(VideoCleanEvidence.declaresAISource(declaredAI),
              "explicit algorithmic-media declaration is reported separately")
        let ordinaryAITitle = VideoMetadataFinding(scope: .file, category: .descriptive,
            identifier: "©nam", displayName: "Title", valueSummary: "A talk about generative AI", removable: true)
        check(!VideoCleanEvidence.declaresAISource(ordinaryAITitle),
              "ordinary descriptive text does not establish an AI source")

        print("\nVideo Clean detected-finding filters")
        check(VideoFindingFilter.allCases.map(\.title) == [
            "Generative AI", "Content Credentials", "XMP", "Location",
            "Descriptive metadata", "Device and software", "Dates and timestamps",
            "Artwork", "Timed metadata", "Technical", "Other metadata",
        ], "video findings use the approved stable order")
        check(VideoFindingFilter.contentCredentials.matches(credentials) &&
              !VideoFindingFilter.generativeAI.matches(credentials),
              "C2PA without an explicit source declaration is not counted as AI")
        let declaredFilters = VideoFindingFilter.filters(in: [declaredAI])
        check(declaredFilters.contains(.generativeAI) &&
              declaredFilters.contains(.contentCredentials),
              "an explicit trained-algorithmic declaration overlaps AI and credentials")
        check(!VideoFindingFilter.generativeAI.matches(ordinaryAITitle),
              "ordinary text mentioning AI does not match the Generative AI filter")

        let descriptive = VideoMetadataFinding(scope: .file, category: .descriptive,
            identifier: "title", displayName: "Title", valueSummary: "Example", removable: true)
        let software = VideoMetadataFinding(scope: .file, category: .device,
            identifier: "encoder", displayName: "Software", valueSummary: "Kechil test", removable: true)
        let artwork = VideoMetadataFinding(scope: .file, category: .artwork,
            identifier: "cover", displayName: "Artwork", valueSummary: "Present", removable: true)
        let technical = VideoMetadataFinding(scope: .track(1), category: .technical,
            identifier: "codec", displayName: "Codec", valueSummary: "H.264", removable: false)
        let other = VideoMetadataFinding(scope: .file, category: .unknown,
            identifier: "vendor", displayName: "Vendor field", valueSummary: "Present", removable: true)
        let typedMappings: [(VideoFindingFilter, VideoMetadataFinding)] = [
            (.xmp, xmp), (.location, location), (.descriptiveMetadata, descriptive),
            (.deviceSoftware, software), (.datesTimestamps, date), (.artwork, artwork),
            (.timedMetadata, timed), (.technical, technical), (.otherMetadata, other),
        ]
        check(typedMappings.allSatisfy { $0.0.matches($0.1) },
              "XMP and every typed video finding category map to their filter")

        let secondTitle = VideoMetadataFinding(scope: .track(1), category: .descriptive,
            identifier: "comment", displayName: "Comment", valueSummary: "Example", removable: true)
        let oneFileFilters = VideoFindingFilter.filters(in: [descriptive, secondTitle, declaredAI])
        check(oneFileFilters.filter { $0 == .descriptiveMetadata }.count == 1,
              "multiple findings in one file produce one category membership")
        check(Set(oneFileFilters).count == oneFileFilters.count,
              "a file never returns a duplicate findings filter")

        var toggled = VideoCleanSelection.all
        toggled.toggle(.location)
        check(!toggled.contains(.location) && toggled.scopes.count == 4,
              "a group can be toggled off without changing other groups")

        if failures == 0 {
            print("\nALL VIDEO CLEAN SCOPE AND FILTER CHECKS PASSED")
        } else {
            print("\n\(failures) VIDEO CLEAN SCOPE CHECK(S) FAILED")
            exit(1)
        }
    }
}
