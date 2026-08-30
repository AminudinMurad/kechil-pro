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
            return "C2PA manifest and known provenance UUID boxes"
        case .descriptiveMetadata:
            return "Title, author, comments and application metadata"
        case .xmp:
            return "Adobe XMP packets stored in known MP4 boxes"
        case .location:
            return "Known location metadata stored in user-data boxes"
        case .containerDates:
            return "Non-empty creation and modification timestamps"
        }
    }

    var symbolName: String {
        switch self {
        case .contentCredentials: return "checkmark.seal.fill"
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
        if isEmpty { return "Select at least one metadata group to clean this video." }
        if self == .all { return "No supported metadata was found in this video." }
        return "No selected metadata was found in this video."
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
