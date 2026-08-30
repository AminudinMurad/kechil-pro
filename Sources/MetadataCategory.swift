import Foundation

/// A privacy-relevant class of metadata, derived from the human-readable labels the
/// strippers emit in `StripResult.removed`.
///
/// The strippers deliberately produce display strings rather than typed values, and
/// `MetadataStripper.swift` is covered by `Tests/verify_algorithm.py` — changing it
/// obliges a mirrored change in the Python. So categorisation happens here instead,
/// over the strings, leaving the verified stripper untouched.
///
/// **Keep this mapping in step with the four places that produce those labels:**
/// `MetadataStripper.jpegSegmentName` (JPEG), `MetadataStripper.pngChunkName` (PNG),
/// `MetadataStripper.stripWebP` (WebP) and `MetadataStripper.presentMetadata` (ImageIO).
/// There is no compiler link between them, so an added label needs a case added below.
/// Anything unrecognised falls to `.other` rather than being dropped, so a new label
/// never silently disappears from the dashboard.
enum MetadataCategory: String, CaseIterable, Identifiable, Hashable {
    case gps
    case ai
    case c2pa
    case exif
    case xmp
    case iptc
    case makerNotes
    case text
    case timestamp
    case signature
    case other

    var id: String { rawValue }

    /// How much this block actually discloses. Drives colour and ordering.
    ///
    /// Only two levels are elevated, on purpose: coordinates identify where a person
    /// physically was, and Content Credentials carry the "AI generated" claim people
    /// most often want gone. Inflating the rest would make the colour meaningless.
    enum Severity {
        case critical       // pinpoints a location
        case serious        // asserts provenance / AI origin
        case informational  // discloses, but not a location or a claim
    }

    var severity: Severity {
        switch self {
        case .gps:       return .critical
        case .ai, .c2pa: return .serious
        default:    return .informational
        }
    }

    /// Fixed display order. Deliberately not derived from counts: a category's position
    /// and colour must not change when the queue or the active filter changes.
    var sortRank: Int {
        switch self {
        case .gps:        return 0
        case .ai:         return 1
        case .c2pa:       return 2
        case .exif:       return 3
        case .xmp:        return 4
        case .iptc:       return 5
        case .makerNotes: return 6
        case .text:       return 7
        case .timestamp:  return 8
        case .signature:  return 9
        case .other:      return 10
        }
    }

    var displayName: String {
        switch self {
        case .gps:        return "GPS location"
        case .ai:         return "Generative AI"
        case .c2pa:       return "Content Credentials"
        case .exif:       return "EXIF"
        case .xmp:        return "XMP"
        case .iptc:       return "IPTC"
        case .makerNotes: return "Maker notes"
        case .text:       return "Embedded text"
        case .timestamp:  return "Timestamp"
        case .signature:  return "Digital signature"
        case .other:      return "Other metadata"
        }
    }

    var symbolName: String {
        switch self {
        case .gps:        return "location.fill"
        case .ai:         return "sparkles"
        case .c2pa:       return "seal.fill"
        case .exif:       return "camera.fill"
        case .xmp:        return "doc.text.fill"
        case .iptc:       return "person.crop.square.fill"
        case .makerNotes: return "gearshape.fill"
        case .text:       return "textformat"
        case .timestamp:  return "clock.fill"
        case .signature:  return "signature"
        case .other:      return "tag.fill"
        }
    }

    /// What this block can reveal. Wording tracks the "What gets removed" table in
    /// README.md so the docs and the UI never disagree.
    var blurb: String {
        switch self {
        case .gps:        return "Exact latitude and longitude where the photo was taken."
        case .ai:         return "A standard source type or generator-specific field identifies Generative AI."
        case .c2pa:       return "Provenance record, including an \"AI generated\" label."
        case .exif:       return "Camera, lens, exposure settings and timestamps."
        case .xmp:        return "Editing history, rights, and AI generation prompts."
        case .iptc:       return "Author, caption, keywords and credits."
        case .makerNotes: return "Device internals and embedded thumbnails."
        case .text:       return "Embedded text, often naming the software used."
        case .timestamp:  return "When the file was last modified."
        case .signature:  return "An embedded digital signature."
        case .other:      return "A vendor-specific metadata block."
        }
    }

    // MARK: Label mapping

    /// Categories carried by one stripper label.
    ///
    /// Returns more than one for compound labels: "EXIF / GPS location" is both a
    /// location leak and camera data, and the dashboard must count it under both.
    /// Substring matching rather than equality, because the JPEG path interpolates
    /// segment numbers ("APP5 metadata").
    static func categories(for label: String) -> [MetadataCategory] {
        let l = label.lowercased()
        var found: [MetadataCategory] = []

        if l.contains("gps")       { found.append(.gps) }
        if l == "ai" || l.hasPrefix("ai ") || l.contains(" ai ") ||
            l.contains("ai metadata") || l.contains("ai generation") {
            found.append(.ai)
        }
        if l.contains("c2pa")      { found.append(.c2pa) }
        if l.contains("exif")      { found.append(.exif) }
        if l.contains("tiff")      { found.append(.exif) }   // ImageIO: camera make/model
        if l.contains("xmp")       { found.append(.xmp) }
        if l.contains("iptc")      { found.append(.iptc) }
        if l.contains("maker")     { found.append(.makerNotes) }
        if l.contains("text")      { found.append(.text) }
        if l.contains("comment")   { found.append(.text) }   // JPEG COM segment
        if l.contains("timestamp") { found.append(.timestamp) }
        if l.contains("signature") { found.append(.signature) }

        return found.isEmpty ? [.other] : found
    }
}

extension ScrubItem {
    /// Distinct categories this image was carrying, in fixed display order.
    ///
    /// Deduplicated: a JPEG with three separate APPn maker segments carried maker
    /// notes once as far as the user is concerned.
    var categories: [MetadataCategory] {
        var seen = Set<MetadataCategory>()
        if provenance.hasGenerativeAI { seen.insert(.ai) }

        // The source probe is the authority for what the original carried. Removal
        // labels describe what one selected operation changed, and can be empty when
        // processing fails or when a different scope is selected. In particular,
        // ImageIO reports GPS as a typed location finding, so count it even while the
        // user is previewing Remove EXIF or before Remove GPS has produced an output.
        if provenance.findings.contains(where: { $0.kind == .location }) {
            seen.insert(.gps)
        }
        for carrier in provenance.carriers {
            for category in MetadataCategory.categories(for: carrier) {
                seen.insert(category)
            }
        }
        for label in removed {
            for category in MetadataCategory.categories(for: label) {
                seen.insert(category)
            }
        }
        return seen.sorted { $0.sortRank < $1.sortRank }
    }

    /// Categories actually removed by the selected operation. This stays separate
    /// from `categories`, which describes everything the source carried, so a
    /// scoped GPS/EXIF cleanup does not claim that preserved fields vanished.
    var removedCategories: [MetadataCategory] {
        var seen = Set<MetadataCategory>()
        for label in removed {
            for category in MetadataCategory.categories(for: label) {
                seen.insert(category)
            }
        }
        if preset == .aiMetadata, !removed.isEmpty { seen.insert(.ai) }
        return seen.sorted { $0.sortRank < $1.sortRank }
    }

    /// True when this image disclosed a physical location.
    var leakedLocation: Bool { categories.contains(.gps) }
}
