import CoreGraphics
import CoreMedia
import Foundation

enum MediaKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case image
    case video

    var id: String { rawValue }
    var title: String { self == .image ? "Images" : "Videos" }
    var singularTitle: String { self == .image ? "image" : "video" }
    var addLabel: String { self == .image ? "Add Images…" : "Add Videos…" }
    var chooseLabel: String { self == .image ? "Choose Images…" : "Choose Videos…" }
    /// Keep the sidebar's image/video glyphs in the same outlined SF Symbol family.
    /// `photo.on.rectangle` gives Images the same compact, line-led visual weight as
    /// the `video` camera used by Videos rather than a filled thumbnail treatment.
    var symbol: String { self == .image ? "photo.on.rectangle" : "video" }
}

/// The four user-facing Clean choices. A preset is a scope, not a different
/// output format: the selected scope is removed and unrelated metadata is kept
/// whenever the source container lets us do that safely.
enum CleanPreset: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case allMetadata
    case aiMetadata
    case exif
    case gps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allMetadata: return "All metadata"
        case .aiMetadata:  return "AI metadata"
        case .exif:        return "EXIF"
        case .gps:         return "GPS"
        }
    }

    var detail: String {
        switch self {
        case .allMetadata: return "EXIF, GPS, XMP and more"
        case .aiMetadata:  return "Provenance and generator markers"
        case .exif:        return "Camera and capture data"
        case .gps:         return "Embedded location data"
        }
    }

    var symbolName: String {
        switch self {
        case .allMetadata: return "checkmark.shield.fill"
        case .aiMetadata:  return "sparkles"
        case .exif:        return "camera.fill"
        case .gps:         return "location.fill"
        }
    }

    var scopeDescription: String {
        switch self {
        case .allMetadata:
            return "Removes every supported metadata and provenance carrier."
        case .aiMetadata:
            return "Removes detected AI provenance, generator and prompt markers."
        case .exif:
            return "Removes camera, lens, capture and maker-note fields."
        case .gps:
            return "Removes GPS coordinates and location fields only."
        }
    }

    var actionTitle: String {
        switch self {
        case .allMetadata: return "Clean"
        case .aiMetadata:  return "Remove AI metadata"
        case .exif:        return "Remove EXIF"
        case .gps:         return "Remove GPS"
        }
    }

    var removesAllMetadata: Bool { self == .allMetadata }
}

enum KechilTool: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case clean
    case optimize
    case watermark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "Clean"
        case .optimize: return "Optimize"
        case .watermark: return "Watermark"
        }
    }

    var symbol: String {
        switch self {
        case .clean: return "checkmark.shield"
        case .optimize: return "arrow.up.left.and.arrow.down.right"
        case .watermark: return "seal"
        }
    }

    var scopeDescription: String {
        switch self {
        case .clean: return "Remove supported metadata and verify the saved copy."
        case .optimize: return "Crop, resize, trim, convert and reduce file size."
        case .watermark: return "Add a visible text or logo mark before export."
        }
    }
}

struct ToolRoute: Identifiable, Codable, Hashable, Sendable {
    let tool: KechilTool
    let media: MediaKind

    var id: String { "\(tool.rawValue).\(media.rawValue)" }
    var title: String { "\(tool.title) · \(media.title)" }

    static let cleanImages = ToolRoute(tool: .clean, media: .image)
    static let cleanVideos = ToolRoute(tool: .clean, media: .video)
    static let optimizeImages = ToolRoute(tool: .optimize, media: .image)
    static let optimizeVideos = ToolRoute(tool: .optimize, media: .video)
    static let watermarkImages = ToolRoute(tool: .watermark, media: .image)
    static let watermarkVideos = ToolRoute(tool: .watermark, media: .video)

    static let all: [ToolRoute] = [
        .cleanImages, .cleanVideos,
        .optimizeImages, .optimizeVideos,
        .watermarkImages, .watermarkVideos,
    ]
}

enum MediaJobStage: String, Codable, Hashable, Sendable {
    case queued
    case analysing
    case ready
    case processing
    case cancelling
    case cancelled
    case failed
    case completed
    case saved

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .analysing: return "Analysing"
        case .ready: return "Ready"
        case .processing: return "Processing"
        case .cancelling: return "Cancelling"
        case .cancelled: return "Cancelled"
        case .failed: return "Failed"
        case .completed: return "Completed"
        case .saved: return "Saved"
        }
    }
}

enum MediaJobPhase: String, Codable, Hashable, Sendable {
    case reading
    case rendering
    case writing
    case verifying
    case saving
}

struct MediaJobError: Error, Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let code: String
    let summary: String
    let detail: String

    init(code: String, summary: String, detail: String) {
        id = UUID()
        self.code = code
        self.summary = summary
        self.detail = detail
    }
}

struct MediaAssetDescriptor: Identifiable, @unchecked Sendable {
    let id: UUID
    let sourceURL: URL
    let kind: MediaKind
    let fileSize: Int64
    let contentTypeIdentifier: String?
    let displayWidth: Int?
    let displayHeight: Int?
    let duration: CMTime?
    let frameRate: Double?
    let videoCodec: String?
    let audioCodec: String?
    let hasAudio: Bool
    let isHDR: Bool
    let preferredTransform: CGAffineTransform?

    init(id: UUID = UUID(), sourceURL: URL, kind: MediaKind, fileSize: Int64,
         contentTypeIdentifier: String?, displayWidth: Int?, displayHeight: Int?,
         duration: CMTime?, frameRate: Double?, videoCodec: String?, audioCodec: String?,
         hasAudio: Bool, isHDR: Bool, preferredTransform: CGAffineTransform?) {
        self.id = id
        self.sourceURL = sourceURL
        self.kind = kind
        self.fileSize = fileSize
        self.contentTypeIdentifier = contentTypeIdentifier
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.duration = duration
        self.frameRate = frameRate
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.hasAudio = hasAudio
        self.isHDR = isHDR
        self.preferredTransform = preferredTransform
    }
}

enum VideoCleanVerification: Hashable, Sendable {
    case unchanged
    case containerOnlyFramesUnverified
    case samplesPreserved
    case reencoded
    case partial(remainingCount: Int)

    var label: String {
        switch self {
        case .unchanged: return "Unchanged copy; no cleanup applied"
        case .containerOnlyFramesUnverified: return "Container cleaned; frames not re-encoded"
        case .samplesPreserved: return "Media samples preserved"
        case .reencoded: return "Re-encoded to remove metadata"
        case .partial: return "Verification incomplete"
        }
    }
}
