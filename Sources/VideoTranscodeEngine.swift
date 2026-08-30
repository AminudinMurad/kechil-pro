import AVFoundation
import CoreImage
import Foundation

struct VideoTranscodeResult: Sendable {
    let outputURL: URL
    let descriptor: MediaAssetDescriptor
    let plan: VideoEncodingPlan
    let metadataVerified: Bool
    let remainingMetadata: [VideoMetadataFinding]
}

private final class VideoCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

private final class VideoPumpFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?
    func record(_ error: Error) { lock.withLock { if stored == nil { stored = error } } }
    var error: Error? { lock.withLock { stored } }
}

private final class VideoTranscodeSession: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let videoOutput: AVAssetReaderTrackOutput
    let videoInput: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let audioOutput: AVAssetReaderTrackOutput?
    let audioInput: AVAssetWriterInput?

    init(reader: AVAssetReader, writer: AVAssetWriter,
         videoOutput: AVAssetReaderTrackOutput, videoInput: AVAssetWriterInput,
         adaptor: AVAssetWriterInputPixelBufferAdaptor,
         audioOutput: AVAssetReaderTrackOutput?, audioInput: AVAssetWriterInput?) {
        self.reader = reader
        self.writer = writer
        self.videoOutput = videoOutput
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.audioOutput = audioOutput
        self.audioInput = audioInput
    }
}

enum VideoTranscodeEngine {
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false,
    ])

    static func transcode(sourceURL: URL, settings: VideoOptimizeSettings,
                          overlay: CGImage? = nil,
                          progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws
        -> VideoTranscodeResult {
        let cancellation = VideoCancellationToken()
        return try await withTaskCancellationHandler {
            try await transcode(sourceURL: sourceURL, settings: settings, overlay: overlay,
                                cancellation: cancellation, progress: progress)
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func transcode(sourceURL: URL, settings: VideoOptimizeSettings,
                                  overlay: CGImage?, cancellation: VideoCancellationToken,
                                  progress: @escaping @Sendable (Double) -> Void) async throws
        -> VideoTranscodeResult {
        let sourceDescriptor = try await MediaCapabilityProbe.inspectVideo(at: sourceURL)
        guard !sourceDescriptor.isHDR else {
            throw VideoPipelineError.exportFailed(
                "HDR video export is not enabled yet because this path cannot guarantee preservation of its colour space. The original is unchanged")
        }
        guard let sourceWidth = sourceDescriptor.displayWidth,
              let sourceHeight = sourceDescriptor.displayHeight,
              let sourceDurationTime = sourceDescriptor.duration else {
            throw VideoPipelineError.verificationFailed("source dimensions or duration are unavailable")
        }
        let sourceDuration = CMTimeGetSeconds(sourceDurationTime)
        let validated = try settings.validated(sourceDuration: sourceDuration)
        let plan = try VideoSizeTargetPolicy.plan(
            sourceSize: CGSize(width: sourceWidth, height: sourceHeight),
            sourceFrameRate: max(1, sourceDescriptor.frameRate ?? 30),
            sourceDuration: sourceDuration, settings: validated)

        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw MediaCapabilityError.noVideoTrack }
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        let outputURL = try VideoTemporaryFiles.makeURL(suffix: "optimized",
                                                        extension: validated.container.fileExtension)
        try? FileManager.default.removeItem(at: outputURL)
        let fileType: AVFileType = validated.container == .mov ? .mov : .mp4
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        writer.shouldOptimizeForNetworkUse = true
        writer.metadata = []

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        ])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw VideoPipelineError.exportUnavailable }
        reader.add(videoOutput)

        let codec: AVVideoCodecType = validated.codec == .hevc ? .hevc : .h264
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: plan.videoBitrate,
            AVVideoExpectedSourceFrameRateKey: Int(plan.frameRate.rounded()),
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
        ]
        if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: plan.width,
            AVVideoHeightKey: plan.height,
            AVVideoCompressionPropertiesKey: compression,
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw VideoPipelineError.exportUnavailable }
        writer.add(videoInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: plan.width,
                kCVPixelBufferHeightKey as String: plan.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ])

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if validated.audioPolicy == .keep, let audioTrack = audioTracks.first {
            let descriptions = try await audioTrack.load(.formatDescriptions)
            let basic = descriptions.first.flatMap {
                CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
            }
            let sampleRate = max(8_000, basic?.mSampleRate ?? 48_000)
            let channels = min(2, max(1, Int(basic?.mChannelsPerFrame ?? 2)))
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            output.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVEncoderBitRateKey: plan.audioBitrate,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
            ])
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else {
                throw VideoPipelineError.exportFailed("the audio track cannot be preserved in this container")
            }
            reader.add(output)
            writer.add(input)
            audioOutput = output
            audioInput = input
        }

        let trimStart = CMTime(seconds: validated.trimStartSeconds, preferredTimescale: 600)
        let trimDuration = CMTime(seconds: plan.duration, preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: trimStart, duration: trimDuration)
        guard writer.startWriting() else {
            throw VideoPipelineError.exportFailed(writer.error?.localizedDescription ?? "writer did not start")
        }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw VideoPipelineError.exportFailed(reader.error?.localizedDescription ?? "reader did not start")
        }
        writer.startSession(atSourceTime: trimStart)

        let transport = VideoTranscodeSession(reader: reader, writer: writer,
            videoOutput: videoOutput, videoInput: videoInput, adaptor: adaptor,
            audioOutput: audioOutput, audioInput: audioInput)

        let failure = VideoPumpFailure()
        let group = DispatchGroup()
        group.enter()
        let videoQueue = DispatchQueue(label: "pro.kechil.video.encode", qos: .userInitiated)
        var lastAccepted = CMTime.invalid
        transport.videoInput.requestMediaDataWhenReady(on: videoQueue) {
            while transport.videoInput.isReadyForMoreMediaData {
                if cancellation.isCancelled {
                    failure.record(VideoPipelineError.cancelled)
                    transport.reader.cancelReading(); transport.writer.cancelWriting()
                    transport.videoInput.markAsFinished(); group.leave()
                    return
                }
                guard let sample = transport.videoOutput.copyNextSampleBuffer() else {
                    if transport.reader.status == .failed {
                        failure.record(VideoPipelineError.exportFailed(
                            transport.reader.error?.localizedDescription ?? "video reader failed"))
                    }
                    transport.videoInput.markAsFinished(); group.leave(); return
                }
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
                if lastAccepted.isValid {
                    let delta = CMTimeGetSeconds(CMTimeSubtract(presentationTime, lastAccepted))
                    if delta + 0.000_001 < 1 / plan.frameRate { continue }
                }
                guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample),
                      let pool = transport.adaptor.pixelBufferPool else {
                    failure.record(VideoPipelineError.exportFailed("the pixel-buffer pool is unavailable"))
                    transport.reader.cancelReading(); transport.writer.cancelWriting()
                    transport.videoInput.markAsFinished(); group.leave()
                    return
                }
                var destination: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess,
                      let destination else {
                    failure.record(VideoPipelineError.exportFailed("could not allocate an output frame"))
                    transport.reader.cancelReading(); transport.writer.cancelWriting()
                    transport.videoInput.markAsFinished(); group.leave()
                    return
                }
                do {
                    try render(sourceBuffer: sourceBuffer, destination: destination,
                               naturalSize: naturalSize, preferredTransform: preferredTransform,
                               settings: validated, plan: plan, overlay: overlay)
                    guard transport.adaptor.append(destination, withPresentationTime: presentationTime) else {
                        throw VideoPipelineError.exportFailed(
                            transport.writer.error?.localizedDescription ?? "could not append an output frame")
                    }
                    lastAccepted = presentationTime
                    let elapsed = max(0, CMTimeGetSeconds(CMTimeSubtract(presentationTime, trimStart)))
                    progress(min(1, elapsed / max(0.001, plan.duration)))
                } catch {
                    failure.record(error); transport.reader.cancelReading(); transport.writer.cancelWriting()
                    transport.videoInput.markAsFinished(); group.leave(); return
                }
            }
        }

        if transport.audioOutput != nil, transport.audioInput != nil {
            group.enter()
            let audioQueue = DispatchQueue(label: "pro.kechil.audio.encode", qos: .userInitiated)
            transport.audioInput?.requestMediaDataWhenReady(on: audioQueue) {
                guard let currentAudioInput = transport.audioInput,
                      let currentAudioOutput = transport.audioOutput else {
                    group.leave(); return
                }
                while currentAudioInput.isReadyForMoreMediaData {
                    if cancellation.isCancelled {
                        failure.record(VideoPipelineError.cancelled)
                        transport.reader.cancelReading(); transport.writer.cancelWriting()
                        currentAudioInput.markAsFinished(); group.leave()
                        return
                    }
                    guard let sample = currentAudioOutput.copyNextSampleBuffer() else {
                        if transport.reader.status == .failed {
                            failure.record(VideoPipelineError.exportFailed(
                                transport.reader.error?.localizedDescription ?? "audio reader failed"))
                        }
                        currentAudioInput.markAsFinished(); group.leave(); return
                    }
                    if !currentAudioInput.append(sample) {
                        failure.record(VideoPipelineError.exportFailed(
                            transport.writer.error?.localizedDescription ?? "could not append audio"))
                        transport.reader.cancelReading(); transport.writer.cancelWriting()
                        currentAudioInput.markAsFinished(); group.leave()
                        return
                    }
                }
            }
        }

        await withCheckedContinuation { continuation in
            group.notify(queue: .global(qos: .userInitiated)) { continuation.resume() }
        }
        if let error = failure.error {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        await withCheckedContinuation { continuation in
            transport.writer.finishWriting { continuation.resume() }
        }
        guard transport.writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoPipelineError.exportFailed(
                transport.writer.error?.localizedDescription ?? "the writer did not finish")
        }

        let descriptor = try await MediaCapabilityProbe.inspectVideo(at: outputURL)
        try verifyOutput(descriptor, plan: plan, audioExpected: validated.audioPolicy == .keep && sourceDescriptor.hasAudio)
        let metadata = try await VideoMetadataProbe.inspect(url: outputURL)
        return VideoTranscodeResult(outputURL: outputURL, descriptor: descriptor, plan: plan,
                                    metadataVerified: metadata.removableFindings.isEmpty,
                                    remainingMetadata: metadata.removableFindings)
    }

    private static func render(sourceBuffer: CVPixelBuffer, destination: CVPixelBuffer,
                               naturalSize: CGSize, preferredTransform: CGAffineTransform,
                               settings: VideoOptimizeSettings, plan: VideoEncodingPlan,
                               overlay: CGImage?) throws {
        var image = CIImage(cvPixelBuffer: sourceBuffer)
        image = image.transformed(by: preferredTransform)
        let orientedExtent = image.extent.standardized
        image = image.transformed(by: CGAffineTransform(translationX: -orientedExtent.minX,
                                                       y: -orientedExtent.minY))
        let displayed = CGSize(width: abs(CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform).width),
                               height: abs(CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform).height))
        let cropSize = VideoSizeTargetPolicy.croppedSize(source: displayed,
                                                         ratio: settings.cropPreset.ratio)
        let x = max(0, (displayed.width - cropSize.width) * settings.cropFocusX)
        let yFromTop = max(0, (displayed.height - cropSize.height) * settings.cropFocusY)
        let y = max(0, displayed.height - cropSize.height - yFromTop)
        image = image.cropped(to: CGRect(x: x, y: y, width: cropSize.width, height: cropSize.height))
        image = image.transformed(by: CGAffineTransform(translationX: -x, y: -y))
        let outputRect = CGRect(x: 0, y: 0, width: plan.width, height: plan.height)
        let scale = max(CGFloat(plan.width) / cropSize.width, CGFloat(plan.height) / cropSize.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaled = image.extent
        image = image.transformed(by: CGAffineTransform(
            translationX: (outputRect.width - scaled.width) / 2 - scaled.minX,
            y: (outputRect.height - scaled.height) / 2 - scaled.minY)).cropped(to: outputRect)
        if let overlay {
            image = CIImage(cgImage: overlay).composited(over: image)
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw VideoPipelineError.exportFailed("the sRGB colour space is unavailable")
        }
        context.render(image, to: destination, bounds: outputRect, colorSpace: colorSpace)
    }

    private static func verifyOutput(_ descriptor: MediaAssetDescriptor, plan: VideoEncodingPlan,
                                     audioExpected: Bool) throws {
        guard descriptor.displayWidth == plan.width, descriptor.displayHeight == plan.height else {
            throw VideoPipelineError.verificationFailed("the output dimensions do not match the selected frame")
        }
        guard descriptor.hasAudio == audioExpected else {
            throw VideoPipelineError.verificationFailed("the output audio policy does not match the selected setting")
        }
        if let duration = descriptor.duration {
            let delta = abs(CMTimeGetSeconds(duration) - plan.duration)
            guard delta <= max(0.12, 2 / plan.frameRate) else {
                throw VideoPipelineError.verificationFailed(
                    "output duration differs by \(String(format: "%.3f", delta)) seconds")
            }
        }
    }
}

enum VideoOptimizePipeline {
    static func optimize(sourceURL: URL, settings: VideoOptimizeSettings,
                         progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws
        -> VideoTranscodeResult {
        try await VideoTranscodeEngine.transcode(sourceURL: sourceURL, settings: settings,
                                                 progress: progress)
    }
}
