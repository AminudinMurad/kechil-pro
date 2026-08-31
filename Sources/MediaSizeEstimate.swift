import Foundation

/// Explains how a live size value was obtained. A video watermark estimate is
/// deliberately distinguished from the exact byte count available after export.
enum MediaSizeEstimateBasis: String, Hashable, Sendable {
    case exactClean
    case fullImageEncode
    case realVideoSample
    case actualOutput

    var title: String {
        switch self {
        case .exactClean: return "Same Clean path measured"
        case .fullImageEncode: return "Same image encoder measured"
        case .realVideoSample: return "Real video sample measured"
        case .actualOutput: return "Prepared output measured"
        }
    }
}

struct MediaSizeEstimate: Equatable, Sendable {
    let sourceBytes: Int64
    let estimatedBytes: Int64
    let basis: MediaSizeEstimateBasis
    let detail: String

    var deltaBytes: Int64 { estimatedBytes - sourceBytes }
}

enum MediaSizeText {
    /// Uses decimal units because the UI is communicating media file sizes and
    /// target-MB settings, not memory allocation sizes.
    static func bytes(_ value: Int64) -> String {
        let number = Double(max(0, value))
        if number < 1_000 { return "\(Int64(number.rounded())) B" }
        if number < 1_000_000 { return String(format: "%.1f kB", number / 1_000) }
        if number < 1_000_000_000 { return String(format: "%.2f MB", number / 1_000_000) }
        return String(format: "%.2f GB", number / 1_000_000_000)
    }

    static func exactBytes(_ value: Int64) -> String {
        "\(max(0, value)) bytes"
    }

    static func signedBytes(_ value: Int64) -> String {
        if value == 0 { return "same size" }
        if value > 0 { return "+\(bytes(value))" }
        return "−\(bytes(abs(value)))"
    }
}
