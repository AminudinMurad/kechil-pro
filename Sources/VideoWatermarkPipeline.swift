import CoreGraphics
import CoreMedia
import Foundation

struct VideoWatermarkSettings: Equatable, Sendable {
    var configuration: WatermarkConfiguration
    var logoData: Data?
    var codec: VideoCodecChoice = .h264
    var audioPolicy: VideoAudioPolicy = .keep
    var container: VideoContainerChoice = .mp4
    var quality = 0.82
}

enum VideoWatermarkPipeline {
    static func apply(sourceURL: URL, settings: VideoWatermarkSettings,
                      progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws
        -> VideoTranscodeResult {
        let descriptor = try await MediaCapabilityProbe.inspectVideo(at: sourceURL)
        guard let width = descriptor.displayWidth, let height = descriptor.displayHeight,
              let duration = descriptor.duration else {
            throw VideoPipelineError.verificationFailed("source dimensions or duration are unavailable")
        }
        let optimize = VideoOptimizeSettings(trimStartSeconds: 0,
            trimEndSeconds: nil, cropPreset: .original, cropFocusX: 0.5, cropFocusY: 0.5,
            resolution: .original, noUpscale: true, codec: settings.codec,
            frameRate: .original, sizeMode: .quality, quality: settings.quality,
            targetMegabytes: 25, priority: .balanced, audioPolicy: settings.audioPolicy,
            audioBitrateKbps: 192, container: settings.container)
        let plan = try VideoSizeTargetPolicy.plan(sourceSize: CGSize(width: width, height: height),
            sourceFrameRate: max(1, descriptor.frameRate ?? 30),
            sourceDuration: max(0.05, CMTimeGetSeconds(duration)), settings: optimize)
        let logo = try settings.logoData.map(WatermarkRenderer.decodeLogo)
        let overlay = try WatermarkRenderer.renderOverlay(configuration: settings.configuration,
            canvasSize: plan.outputSize, logo: logo)
        return try await VideoTranscodeEngine.transcode(sourceURL: sourceURL, settings: optimize,
                                                        overlay: overlay, progress: progress)
    }
}
