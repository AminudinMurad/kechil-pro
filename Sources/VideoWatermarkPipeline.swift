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
        let optimize = makeOptimizeSettings(settings: settings)
        let plan = try VideoSizeTargetPolicy.plan(sourceSize: CGSize(width: width, height: height),
            sourceFrameRate: max(1, descriptor.frameRate ?? 30),
            sourceDuration: max(0.05, CMTimeGetSeconds(duration)), settings: optimize)
        let logo = try settings.logoData.map(WatermarkRenderer.decodeLogo)
        let overlay = try WatermarkRenderer.renderOverlay(configuration: settings.configuration,
            canvasSize: plan.outputSize, logo: logo)
        return try await VideoTranscodeEngine.transcode(sourceURL: sourceURL, settings: optimize,
                                                        overlay: overlay, progress: progress)
    }

    /// Measures a short real encode with the same watermark render and encoder
    /// used by Apply, then projects those observed bytes to the full duration.
    /// This is intentionally labelled an estimate because scene complexity and
    /// rate-control decisions can vary across the rest of the source.
    static func estimateSize(sourceURL: URL,
                             settings: VideoWatermarkSettings) async throws -> MediaSizeEstimate {
        try Task.checkCancellation()
        let descriptor = try await MediaCapabilityProbe.inspectVideo(at: sourceURL)
        guard let width = descriptor.displayWidth, let height = descriptor.displayHeight,
              let duration = descriptor.duration else {
            throw VideoPipelineError.verificationFailed("source dimensions or duration are unavailable")
        }
        let fullDuration = CMTimeGetSeconds(duration)
        guard fullDuration.isFinite, fullDuration > 0 else {
            throw VideoPipelineError.verificationFailed("source duration is unavailable")
        }

        let fullSettings = makeOptimizeSettings(settings: settings)
        let fullPlan = try VideoSizeTargetPolicy.plan(
            sourceSize: CGSize(width: width, height: height),
            sourceFrameRate: max(1, descriptor.frameRate ?? 30),
            sourceDuration: fullDuration,
            settings: fullSettings)
        let logo = try settings.logoData.map(WatermarkRenderer.decodeLogo)
        let overlay = try WatermarkRenderer.renderOverlay(
            configuration: settings.configuration,
            canvasSize: fullPlan.outputSize,
            logo: logo)

        let sampleDuration = min(3.0, fullDuration)
        let sampleStart = fullDuration - sampleDuration > 0.05
            ? min(fullDuration * 0.37, fullDuration - sampleDuration)
            : 0
        let sampleEnd = sampleStart + sampleDuration
        let sampleSettings = makeOptimizeSettings(
            settings: settings,
            trimStart: sampleStart,
            trimEnd: sampleEnd >= fullDuration - 0.025 ? nil : sampleEnd)
        let sampleResult = try await VideoTranscodeEngine.transcode(
            sourceURL: sourceURL,
            settings: sampleSettings,
            overlay: overlay)
        defer { try? FileManager.default.removeItem(at: sampleResult.outputURL) }
        try Task.checkCancellation()

        let sampleBytes = Int64((try? sampleResult.outputURL.resourceValues(
            forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard sampleBytes > 0 else {
            throw VideoPipelineError.verificationFailed("the temporary watermark sample has no readable file size")
        }
        let measuredDuration = max(0.05, sampleResult.plan.duration)
        let projected = Int64((Double(sampleBytes) * fullDuration / measuredDuration).rounded())
        let sampleLabel = abs(measuredDuration - fullDuration) < 0.025
            ? "the full-duration source" : "\(String(format: "%.1f", measuredDuration))-second sample"
        let sourceBytes = max(descriptor.fileSize,
                              Int64((try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        return MediaSizeEstimate(
            sourceBytes: sourceBytes,
            estimatedBytes: max(sampleBytes, projected),
            basis: .realVideoSample,
            detail: "Measured \(sampleLabel) with \(settings.codec.rawValue), \(settings.audioPolicy.rawValue.lowercased()), and the current quality; projected to \(String(format: "%.1f", fullDuration)) seconds. Final bytes can vary with scene complexity.")
    }

    private static func makeOptimizeSettings(settings: VideoWatermarkSettings,
                                             trimStart: Double = 0,
                                             trimEnd: Double? = nil) -> VideoOptimizeSettings {
        VideoOptimizeSettings(
            trimStartSeconds: trimStart,
            trimEndSeconds: trimEnd,
            cropPreset: .original,
            cropFocusX: 0.5,
            cropFocusY: 0.5,
            resolution: .original,
            noUpscale: true,
            codec: settings.codec,
            frameRate: .original,
            sizeMode: .quality,
            quality: settings.quality,
            targetMegabytes: 25,
            priority: .balanced,
            audioPolicy: settings.audioPolicy,
            audioBitrateKbps: 192,
            container: settings.container)
    }
}
