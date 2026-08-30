import CoreGraphics
import Foundation

enum VideoCropPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case original = "Original"
    case square = "1:1"
    case portrait = "4:5"
    case widescreen = "16:9"
    case story = "9:16"

    var id: String { rawValue }
    var ratio: Double? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .portrait: return 4.0 / 5.0
        case .widescreen: return 16.0 / 9.0
        case .story: return 9.0 / 16.0
        }
    }
}

enum VideoResolutionPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case original = "Original"
    case smart = "Smart"
    case p2160 = "2160p"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"

    var id: String { rawValue }
    var landscapeBounds: CGSize? {
        switch self {
        case .original, .smart: return nil
        case .p2160: return CGSize(width: 3840, height: 2160)
        case .p1080: return CGSize(width: 1920, height: 1080)
        case .p720: return CGSize(width: 1280, height: 720)
        case .p480: return CGSize(width: 854, height: 480)
        }
    }
}

enum VideoCodecChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case h264 = "H.264"
    case hevc = "HEVC"
    var id: String { rawValue }
}

enum VideoFrameRateChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case original = "Original"
    case fps24 = "24 fps"
    case fps30 = "30 fps"
    case fps60 = "60 fps"
    var id: String { rawValue }
    var value: Double? {
        switch self {
        case .original: return nil
        case .fps24: return 24
        case .fps30: return 30
        case .fps60: return 60
        }
    }
}

enum VideoSizeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case quality = "Quality"
    case targetSize = "Target size"
    var id: String { rawValue }
}

enum VideoQualityPriority: String, CaseIterable, Identifiable, Codable, Sendable {
    case balanced = "Balanced"
    case keepQuality = "Keep quality"
    case keepResolution = "Keep resolution"
    var id: String { rawValue }
}

enum VideoAudioPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case keep = "Keep audio"
    case remove = "Remove audio"
    var id: String { rawValue }
}

enum VideoContainerChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case mp4 = "MP4"
    case mov = "MOV"
    var id: String { rawValue }
    var fileExtension: String { rawValue.lowercased() }
}

struct VideoOptimizeSettings: Codable, Equatable, Sendable {
    var trimStartSeconds = 0.0
    var trimEndSeconds: Double?
    var cropPreset: VideoCropPreset = .original
    var cropFocusX = 0.5
    /// Top-to-bottom normalised focus used by the preview and export renderer.
    var cropFocusY = 0.5
    var resolution: VideoResolutionPreset = .smart
    var noUpscale = true
    var codec: VideoCodecChoice = .h264
    var frameRate: VideoFrameRateChoice = .original
    var sizeMode: VideoSizeMode = .quality
    var quality = 0.72
    var targetMegabytes = 25.0
    var priority: VideoQualityPriority = .balanced
    var audioPolicy: VideoAudioPolicy = .keep
    var audioBitrateKbps = 128
    var container: VideoContainerChoice = .mp4

    func validated(sourceDuration: Double) throws -> VideoOptimizeSettings {
        guard sourceDuration.isFinite, sourceDuration > 0 else {
            throw VideoOptimizeValidationError.invalidDuration
        }
        var copy = self
        copy.trimStartSeconds = min(max(0, trimStartSeconds), sourceDuration)
        copy.trimEndSeconds = min(max(copy.trimStartSeconds + 0.05,
                                      trimEndSeconds ?? sourceDuration), sourceDuration)
        guard (copy.trimEndSeconds ?? sourceDuration) - copy.trimStartSeconds >= 0.05 else {
            throw VideoOptimizeValidationError.trimTooShort
        }
        copy.cropFocusX = min(max(0, cropFocusX), 1)
        copy.cropFocusY = min(max(0, cropFocusY), 1)
        copy.quality = min(max(0.1, quality), 1)
        copy.targetMegabytes = min(max(1, targetMegabytes), 100_000)
        copy.audioBitrateKbps = [96, 128, 192, 256].min {
            abs($0 - audioBitrateKbps) < abs($1 - audioBitrateKbps)
        } ?? 128
        return copy
    }
}

enum VideoOptimizeValidationError: LocalizedError {
    case invalidDuration
    case trimTooShort
    case targetTooSmall(minimumMegabytes: Double)

    var errorDescription: String? {
        switch self {
        case .invalidDuration: return "The video duration is unavailable"
        case .trimTooShort: return "The selected trim range is too short"
        case .targetTooSmall(let minimum):
            return "The target is too small for this duration. Choose at least \(String(format: "%.1f", minimum)) MB."
        }
    }
}

struct VideoEncodingPlan: Equatable, Sendable {
    let width: Int
    let height: Int
    let frameRate: Double
    let duration: Double
    let videoBitrate: Int
    let audioBitrate: Int
    let estimatedBytes: Int64
    let targetBytes: Int64?
    let resolutionWasReducedForTarget: Bool

    var outputSize: CGSize { CGSize(width: width, height: height) }
}

enum VideoSizeTargetPolicy {
    /// The target-size contract reserves 3% for MP4/MOV container overhead, subtracts
    /// the chosen audio budget, then selects an even-pixel frame size. It is a bounded,
    /// explainable estimate rather than an exact-byte promise.
    static func plan(sourceSize: CGSize, sourceFrameRate: Double, sourceDuration: Double,
                     settings: VideoOptimizeSettings) throws -> VideoEncodingPlan {
        let validated = try settings.validated(sourceDuration: sourceDuration)
        let end = validated.trimEndSeconds ?? sourceDuration
        let duration = end - validated.trimStartSeconds
        let requestedFrameRate = validated.frameRate.value ?? sourceFrameRate
        let frameRate = max(1, min(requestedFrameRate, sourceFrameRate, 60))
        let cropped = croppedSize(source: sourceSize, ratio: validated.cropPreset.ratio)
        var output = requestedSize(cropped: cropped, preset: validated.resolution,
                                   noUpscale: validated.noUpscale)
        let audioBitrate = validated.audioPolicy == .keep ? validated.audioBitrateKbps * 1_000 : 0
        var targetBytes: Int64?
        let videoBitrate: Int
        var reduced = false

        if validated.sizeMode == .targetSize {
            let bytes = Int64((validated.targetMegabytes * 1_000_000).rounded())
            targetBytes = bytes
            let totalBitsPerSecond = Double(bytes) * 8 * 0.97 / duration
            let available = Int(totalBitsPerSecond.rounded()) - audioBitrate
            let minimumVideoBitrate = 250_000
            guard available >= minimumVideoBitrate else {
                let minimum = (Double(minimumVideoBitrate + audioBitrate) * duration / 8 / 0.97) / 1_000_000
                throw VideoOptimizeValidationError.targetTooSmall(minimumMegabytes: minimum)
            }
            videoBitrate = available
            if validated.resolution == .smart && validated.priority != .keepResolution {
                let threshold = validated.priority == .keepQuality ? 0.085 : 0.060
                let chosen = smartSize(startingAt: output, bitrate: videoBitrate,
                                       frameRate: frameRate, minimumBitsPerPixel: threshold)
                reduced = chosen != output
                output = chosen
            }
        } else {
            let bitsPerPixel = 0.035 + validated.quality * 0.095
            videoBitrate = max(350_000,
                Int(Double(output.width * output.height) * frameRate * bitsPerPixel))
        }

        let estimated = Int64((Double(videoBitrate + audioBitrate) * duration / 8 / 0.97).rounded())
        return VideoEncodingPlan(width: Int(output.width), height: Int(output.height),
                                 frameRate: frameRate, duration: duration,
                                 videoBitrate: videoBitrate, audioBitrate: audioBitrate,
                                 estimatedBytes: estimated, targetBytes: targetBytes,
                                 resolutionWasReducedForTarget: reduced)
    }

    static func croppedSize(source: CGSize, ratio: Double?) -> CGSize {
        guard let ratio, ratio > 0 else { return even(source) }
        let sourceRatio = source.width / max(1, source.height)
        if sourceRatio > ratio {
            return even(CGSize(width: source.height * ratio, height: source.height))
        }
        return even(CGSize(width: source.width, height: source.width / ratio))
    }

    private static func requestedSize(cropped: CGSize, preset: VideoResolutionPreset,
                                      noUpscale: Bool) -> CGSize {
        guard let landscapeBounds = preset.landscapeBounds else { return even(cropped) }
        let bounds = cropped.height > cropped.width
            ? CGSize(width: landscapeBounds.height, height: landscapeBounds.width)
            : landscapeBounds
        let scale = min(bounds.width / cropped.width, bounds.height / cropped.height)
        let finalScale = noUpscale ? min(1, scale) : scale
        return even(CGSize(width: cropped.width * finalScale, height: cropped.height * finalScale))
    }

    private static func smartSize(startingAt size: CGSize, bitrate: Int, frameRate: Double,
                                  minimumBitsPerPixel: Double) -> CGSize {
        var candidate = even(size)
        let bounds: [CGSize] = [
            candidate,
            candidate.height > candidate.width ? CGSize(width: 1080, height: 1920) : CGSize(width: 1920, height: 1080),
            candidate.height > candidate.width ? CGSize(width: 720, height: 1280) : CGSize(width: 1280, height: 720),
            candidate.height > candidate.width ? CGSize(width: 540, height: 960) : CGSize(width: 960, height: 540),
            candidate.height > candidate.width ? CGSize(width: 480, height: 854) : CGSize(width: 854, height: 480),
        ]
        for bound in bounds {
            let scale = min(1, min(bound.width / size.width, bound.height / size.height))
            candidate = even(CGSize(width: size.width * scale, height: size.height * scale))
            let bpp = Double(bitrate) / (candidate.width * candidate.height * frameRate)
            if bpp >= minimumBitsPerPixel { return candidate }
        }
        return candidate
    }

    private static func even(_ size: CGSize) -> CGSize {
        CGSize(width: max(2, floor(size.width / 2) * 2),
               height: max(2, floor(size.height / 2) * 2))
    }
}
