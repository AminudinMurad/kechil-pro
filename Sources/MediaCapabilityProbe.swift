import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MediaCapabilityError: LocalizedError {
    case unsupportedExtension(String)
    case unreadableImage
    case noVideoTrack
    case protectedAsset

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let ext):
            return ext.isEmpty ? "This file type is unsupported" : ".\(ext) is unsupported"
        case .unreadableImage: return "The image could not be decoded"
        case .noVideoTrack: return "No playable video track was found"
        case .protectedAsset: return "Protected or DRM media is unsupported"
        }
    }
}

enum MediaCapabilityProbe {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "webp", "heic", "heif", "tif", "tiff",
        "gif", "bmp", "avif", "dng",
    ]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    static func expectedKind(for url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return nil
        }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        return nil
    }

    static func accepts(_ url: URL, for route: ToolRoute) -> Bool {
        expectedKind(for: url) == route.media
    }

    static func inspectImage(at url: URL) throws -> MediaAssetDescriptor {
        guard imageExtensions.contains(url.pathExtension.lowercased()) else {
            throw MediaCapabilityError.unsupportedExtension(url.pathExtension.lowercased())
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw MediaCapabilityError.unreadableImage }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        return MediaAssetDescriptor(sourceURL: url, kind: .image,
                                    fileSize: Int64(values?.fileSize ?? 0),
                                    contentTypeIdentifier: values?.contentType?.identifier,
                                    displayWidth: width, displayHeight: height,
                                    duration: nil, frameRate: nil,
                                    videoCodec: nil, audioCodec: nil,
                                    hasAudio: false, isHDR: false, preferredTransform: nil)
    }

    static func inspectVideo(at url: URL) async throws -> MediaAssetDescriptor {
        guard videoExtensions.contains(url.pathExtension.lowercased()) else {
            throw MediaCapabilityError.unsupportedExtension(url.pathExtension.lowercased())
        }
        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        let hasProtectedContent = try await asset.load(.hasProtectedContent)
        guard isPlayable, !hasProtectedContent else {
            throw MediaCapabilityError.protectedAsset
        }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw MediaCapabilityError.noVideoTrack }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let videoDescriptions = try await videoTrack.load(.formatDescriptions)
        let audioDescriptions = try await audioTracks.first?.load(.formatDescriptions)
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])

        return MediaAssetDescriptor(sourceURL: url, kind: .video,
                                    fileSize: Int64(values?.fileSize ?? 0),
                                    contentTypeIdentifier: values?.contentType?.identifier,
                                    displayWidth: Int(displayRect.width.rounded()),
                                    displayHeight: Int(displayRect.height.rounded()),
                                    duration: duration,
                                    frameRate: Double(frameRate),
                                    videoCodec: codecName(from: videoDescriptions.first),
                                    audioCodec: codecName(from: audioDescriptions?.first),
                                    hasAudio: !audioTracks.isEmpty,
                                    isHDR: isHDR(videoDescriptions.first),
                                    preferredTransform: transform)
    }

    private static func codecName(from description: CMFormatDescription?) -> String? {
        guard let description else { return nil }
        let code = CMFormatDescriptionGetMediaSubType(description)
        switch code {
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC: return "HEVC"
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatAppleLossless: return "ALAC"
        default:
            let bytes: [UInt8] = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }
            let readable = bytes.map { $0 >= 32 && $0 < 127 ? Character(UnicodeScalar($0)) : "?" }
            return String(readable)
        }
    }

    private static func isHDR(_ description: CMFormatDescription?) -> Bool {
        guard let description,
              let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any]
        else { return false }
        let transfer = extensions[kCVImageBufferTransferFunctionKey as String] as? String
        return transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String) ||
            transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
    }
}
