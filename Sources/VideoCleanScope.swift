import Foundation

/// The metadata groups exposed by the video Clean workspace. Unlike the legacy
/// image presets, video cleanup is intentionally multi-select: a user can remove
/// only a location and date, or select every supported group in one pass.
enum VideoCleanScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case contentCredentials
    case descriptiveMetadata
    case xmp
    case location
    case containerDates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contentCredentials: return "Content Credentials"
        case .descriptiveMetadata: return "Descriptive metadata"
        case .xmp: return "XMP"
        case .location: return "Location"
        case .containerDates: return "Container dates"
        }
    }

    var detail: String {
        switch self {
        case .contentCredentials:
            return "C2PA & provenance"
        case .descriptiveMetadata:
            return "Title, author & comments"
        case .xmp:
            return "Adobe XMP"
        case .location:
            return "GPS & ISO 6709"
        case .containerDates:
            return "Created & modified"
        }
    }

    var symbolName: String {
        switch self {
        case .contentCredentials: return "seal.fill"
        case .descriptiveMetadata: return "text.alignleft"
        case .xmp: return "doc.text.fill"
        case .location: return "location.fill"
        case .containerDates: return "calendar"
        }
    }

    var scopeDescription: String {
        switch self {
        case .contentCredentials:
            return "Remove supported C2PA/content-credential carriers."
        case .descriptiveMetadata:
            return "Remove titles, descriptions, authors and comments."
        case .xmp:
            return "Remove readable Adobe XMP metadata where exposed."
        case .location:
            return "Remove GPS and ISO 6709 location fields."
        case .containerDates:
            return "Remove exposed creation and modification date metadata."
        }
    }
}

/// Set of video metadata groups selected for the next Clean run.
struct VideoCleanSelection: OptionSet, Hashable, Sendable {
    let rawValue: UInt16

    init(rawValue: UInt16) { self.rawValue = rawValue }

    static let contentCredentials = VideoCleanSelection(rawValue: 1 << 0)
    static let descriptiveMetadata = VideoCleanSelection(rawValue: 1 << 1)
    static let xmp = VideoCleanSelection(rawValue: 1 << 2)
    static let location = VideoCleanSelection(rawValue: 1 << 3)
    static let containerDates = VideoCleanSelection(rawValue: 1 << 4)
    static let all: VideoCleanSelection = [
        .contentCredentials, .descriptiveMetadata, .xmp, .location, .containerDates,
    ]

    var scopes: [VideoCleanScope] {
        VideoCleanScope.allCases.filter { contains(Self.option(for: $0)) }
    }

    var title: String {
        if self == .all { return "All supported metadata" }
        let names = scopes.map(\.title)
        return names.isEmpty ? "Nothing selected" : names.joined(separator: ", ")
    }

    var actionTitle: String {
        if self == .all { return "Clean" }
        if scopes.count == 1, let scope = scopes.first { return "Remove " + scope.title }
        return "Remove selected metadata"
    }

    var isEmpty: Bool { rawValue == 0 }

    func contains(_ scope: VideoCleanScope) -> Bool {
        contains(Self.option(for: scope))
    }

    mutating func toggle(_ scope: VideoCleanScope) {
        let option = Self.option(for: scope)
        if contains(option) { remove(option) } else { insert(option) }
    }

    func matches(_ finding: VideoMetadataFinding) -> Bool {
        guard finding.removable, !isEmpty else { return false }
        // The all-groups export removes all exposed metadata. Verification must
        // also include device/artwork/timed/unknown fields, not just five labels.
        if self == .all { return true }
        return scopes.contains { scope in
            let identifiers = [finding.identifier, finding.displayName]
                .joined(separator: " ").lowercased()
            let values = [finding.identifier, finding.displayName, finding.valueSummary]
                .joined(separator: " ").lowercased()
            let descriptiveKey = finding.category == .descriptive || containsAny(identifiers, markers: [
                "title", "description", "author", "comment", "keyword", "copyright",
                "©nam", "©cmt", "©des", "displayname",
            ])
            switch scope {
            case .contentCredentials:
                // A title/description can mention “C2PA” as ordinary text. Keep
                // that descriptive field unless its identifier itself denotes a
                // credential carrier; the five cards must remain independently
                // scoped rather than deleting neighbouring metadata by value.
                if descriptiveKey {
                    return containsAny(identifiers, markers: [
                        "c2pa", "content credential", "credential", "provenance", "jumbf",
                        "uuid", "cabx",
                    ])
                }
                return finding.category == .provenance || containsAny(values, markers: [
                    "c2pa", "content credential", "credential", "provenance", "jumbf",
                    "uuid", "cabx",
                ])
            case .descriptiveMetadata:
                return descriptiveKey || containsAny(values, markers: [
                    "title", "description", "author", "comment", "keyword", "copyright",
                    "©nam", "©cmt", "©des", "name",
                ])
            case .xmp:
                return containsAny(values, markers: [
                    "xmp", "adobe xap", "ns.adobe.com", "rdf:description", "xml packet",
                ])
            case .location:
                return finding.category == .location || containsAny(values, markers: [
                    "gps", "location", "iso6709", "iso 6709", "xyz",
                ])
            case .containerDates:
                return finding.category == .timestamp || containsAny(values, markers: [
                    "mvhd", "tkhd", "mdhd", "creation", "modification", "timestamp", "date",
                ])
            }
        }
    }

    func noMatchMessage() -> String {
        if isEmpty { return "No groups selected. An unchanged copy is ready to save." }
        if self == .all { return "No supported metadata was detected. An unchanged copy is ready to save." }
        return "No selected supported metadata was detected. An unchanged copy is ready to save."
    }

    private static func option(for scope: VideoCleanScope) -> VideoCleanSelection {
        switch scope {
        case .contentCredentials: return .contentCredentials
        case .descriptiveMetadata: return .descriptiveMetadata
        case .xmp: return .xmp
        case .location: return .location
        case .containerDates: return .containerDates
        }
    }

    private func containsAny(_ value: String, markers: [String]) -> Bool {
        markers.contains { value.contains($0) }
    }
}

extension CleanPreset {
    /// Maps the original four-preset API to the new multi-select video contract.
    /// Existing callers/tests remain source-compatible while the video UI can expose
    /// its more precise groups.
    var videoSelection: VideoCleanSelection {
        switch self {
        case .allMetadata: return .all
        case .aiMetadata: return .contentCredentials
        case .exif: return []
        case .gps: return .location
        }
    }
}

/// Presentation decisions shared by the inspector and safety checks. A metadata
/// carrier is not evidence of AI creation, and a still-present field is never
/// listed as removed just because its value or track index changed.
enum VideoCleanEvidence {
    static func noLongerDetected(_ input: [VideoMetadataFinding],
                                remaining: [VideoMetadataFinding]) -> [VideoMetadataFinding] {
        let remainingKeys = Set(remaining.map {
            "\($0.scope.label)|\($0.identifier.lowercased())"
        })
        return input.filter {
            !remainingKeys.contains("\($0.scope.label)|\($0.identifier.lowercased())")
        }
    }

    static func isProvenance(_ finding: VideoMetadataFinding) -> Bool {
        if finding.category == .provenance { return true }
        let key = "\(finding.identifier) \(finding.displayName)".lowercased()
        return ["c2pa", "content credential", "provenance", "jumbf"].contains(where: key.contains)
    }

    static func declaresAISource(_ finding: VideoMetadataFinding) -> Bool {
        let key = "\(finding.identifier) \(finding.displayName)".lowercased()
        let sourceField = ["generator", "software", "digital source", "digitalsourcetype", "xmp"]
            .contains(where: key.contains)
        guard isProvenance(finding) || sourceField else { return false }
        let value = ([finding.valueSummary] + finding.evidence
            .filter { $0.label != "Identifier" && $0.label != "Common key" }
            .map(\.value)).joined(separator: " ").lowercased()
        return ["trainedalgorithmicmedia", "compositewithtrainedalgorithmicmedia",
                "generative ai", "ai-generated", "ai generated", "ai_generation",
                "gpt-image", "dall-e", "stable diffusion", "midjourney", "comfyui",
                "automatic1111", "adobe firefly", "openai sora", "openai (sora)"]
            .contains(where: value.contains)
    }
}

/// Presentation-only categories for the Video Clean batch findings and queue
/// filters. They deliberately describe the inspected original rather than the
/// five independent removal scopes.
enum VideoFindingFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case generativeAI
    case contentCredentials
    case xmp
    case location
    case descriptiveMetadata
    case deviceSoftware
    case datesTimestamps
    case artwork
    case timedMetadata
    case technical
    case otherMetadata

    enum Tone { case neutral, critical, serious }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generativeAI: return "Generative AI"
        case .contentCredentials: return "Content Credentials"
        case .xmp: return "XMP"
        case .location: return "Location"
        case .descriptiveMetadata: return "Descriptive metadata"
        case .deviceSoftware: return "Device and software"
        case .datesTimestamps: return "Dates and timestamps"
        case .artwork: return "Artwork"
        case .timedMetadata: return "Timed metadata"
        case .technical: return "Technical"
        case .otherMetadata: return "Other metadata"
        }
    }

    var symbolName: String {
        switch self {
        case .generativeAI: return "sparkles"
        case .contentCredentials: return "seal.fill"
        case .xmp: return "doc.text.fill"
        case .location: return "location.fill"
        case .descriptiveMetadata: return "text.alignleft"
        case .deviceSoftware: return "camera.fill"
        case .datesTimestamps: return "calendar"
        case .artwork: return "photo.fill"
        case .timedMetadata: return "timeline.selection"
        case .technical: return "wrench.and.screwdriver.fill"
        case .otherMetadata: return "tag.fill"
        }
    }

    var tone: Tone {
        switch self {
        case .location: return .critical
        case .generativeAI, .contentCredentials: return .serious
        default: return .neutral
        }
    }

    var help: String {
        switch self {
        case .generativeAI:
            return "An explicit source declaration or recognised generator identifies Generative AI."
        case .contentCredentials:
            return "C2PA or other provenance metadata; this alone is not proof of AI generation."
        case .xmp: return "Readable Adobe XMP metadata exposed by the video inspection."
        case .location: return "GPS or ISO 6709 location metadata."
        case .descriptiveMetadata: return "Titles, descriptions, authors or comments."
        case .deviceSoftware: return "Camera, device, encoder or software identifiers."
        case .datesTimestamps: return "Creation, modification or container timestamps."
        case .artwork: return "Embedded artwork, covers or thumbnails."
        case .timedMetadata: return "Metadata carried on a timed track."
        case .technical: return "Technical media facts that Clean does not claim to remove."
        case .otherMetadata: return "Other inspected metadata not covered by a named category."
        }
    }

    func matches(_ finding: VideoMetadataFinding) -> Bool {
        switch self {
        case .generativeAI: return VideoCleanEvidence.declaresAISource(finding)
        case .contentCredentials: return VideoCleanEvidence.isProvenance(finding)
        case .xmp: return VideoCleanSelection.xmp.matches(finding)
        case .location: return finding.category == .location
        case .descriptiveMetadata: return finding.category == .descriptive
        case .deviceSoftware: return finding.category == .device
        case .datesTimestamps: return finding.category == .timestamp
        case .artwork: return finding.category == .artwork
        case .timedMetadata: return finding.category == .timed
        case .technical: return finding.category == .technical
        case .otherMetadata: return finding.category == .unknown
        }
    }

    static func filters(in findings: [VideoMetadataFinding]) -> [VideoFindingFilter] {
        allCases.filter { filter in findings.contains(where: filter.matches) }
    }
}
