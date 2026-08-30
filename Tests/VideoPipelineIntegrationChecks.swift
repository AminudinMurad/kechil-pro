import AVFoundation
import CoreVideo
import Foundation

@main
enum VideoPipelineIntegrationChecks {
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pro.kechil.pipeline-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov")
        try await makeFixture(at: source, in: folder)

        let sourceDescriptor = try await MediaCapabilityProbe.inspectVideo(at: source)
        expect(sourceDescriptor.displayWidth == 320 && sourceDescriptor.displayHeight == 180,
               "fixture dimensions are readable")
        expect(sourceDescriptor.hasAudio, "fixture audio track is readable")

        let cleaned = try await VideoCleanPipeline.clean(sourceURL: source)
        expect(FileManager.default.fileExists(atPath: cleaned.outputURL.path),
               "video Clean creates a temporary output")
        expect(cleaned.outputDescriptor.displayWidth == 320 &&
               cleaned.outputDescriptor.displayHeight == 180,
               "video Clean preserves display dimensions")
        expect(!cleaned.inputFindings.isEmpty && cleaned.remainingFindings.isEmpty,
               "video Clean detects fixture metadata and removes it from the output")

        var optimize = VideoOptimizeSettings()
        optimize.trimStartSeconds = 0.25
        optimize.trimEndSeconds = 1.25
        optimize.cropPreset = .square
        optimize.resolution = .original
        optimize.container = .mp4
        optimize.audioPolicy = .keep
        optimize.audioBitrateKbps = 128
        optimize.sizeMode = .targetSize
        optimize.targetMegabytes = 1
        let optimized = try await VideoOptimizePipeline.optimize(sourceURL: source,
                                                                  settings: optimize)
        expect(optimized.descriptor.displayWidth == 180 && optimized.descriptor.displayHeight == 180,
               "video Optimize crops through the real reader/writer path")
        let optimizedDuration = optimized.descriptor.duration.map(CMTimeGetSeconds) ?? 0
        expect(abs(optimizedDuration - 1) < 0.15, "video Optimize applies trim timing")
        expect(optimized.descriptor.hasAudio && optimized.descriptor.audioCodec == "AAC",
               "video Optimize encodes kept audio as AAC")
        let optimizedBytes = (try? optimized.outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        expect(optimizedBytes <= 1_050_000, "video Optimize respects the tested target-MB budget")
        expect(optimized.metadataVerified, "video Optimize re-probes metadata")

        let configuration = WatermarkConfiguration(source: .text("Kechil"),
            textColor: .white, opacity: 0.7, rotationDegrees: -20,
            scalePercentOfShortestEdge: 12, anchor: .bottomRight,
            marginPercent: 3, tiled: false, shadowEnabled: true)
        let watermarkSettings = VideoWatermarkSettings(configuration: configuration,
            logoData: nil, codec: .h264, audioPolicy: .keep, container: .mp4, quality: 0.7)
        let watermarked = try await VideoWatermarkPipeline.apply(sourceURL: source,
                                                                  settings: watermarkSettings)
        expect(watermarked.descriptor.displayWidth == 320 &&
               watermarked.descriptor.displayHeight == 180,
               "video Watermark preserves the selected frame size")
        expect(watermarked.descriptor.hasAudio, "video Watermark keeps audio when selected")
        expect(watermarked.metadataVerified, "video Watermark re-probes metadata")
        for seconds in [0.1, 1.0, 1.8] {
            let sourceFrame = try await frame(from: source, seconds: seconds)
            let outputFrame = try await frame(from: watermarked.outputURL, seconds: seconds)
            expect(averageDifference(sourceFrame, outputFrame) > 1.2,
                   "video Watermark is visible at \(seconds) seconds")
        }

        for url in [cleaned.outputURL, optimized.outputURL, watermarked.outputURL] {
            try? FileManager.default.removeItem(at: url)
        }
        print("Video pipeline integration checks passed")
    }

    private static func makeFixture(at url: URL, in folder: URL) async throws {
        let videoURL = folder.appendingPathComponent("picture.mov")
        let audioURL = folder.appendingPathComponent("tone.caf")
        try await makeVideo(at: videoURL)
        try makeAudio(at: audioURL)
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first
        let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first
        let duration = try await videoAsset.load(.duration)
        guard let videoTrack, let audioTrack else { throw FixtureError.writerUnavailable }
        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid),
              let compositionAudio = composition.addMutableTrack(withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw FixtureError.writerUnavailable
        }
        try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                             of: videoTrack, at: .zero)
        try compositionAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                             of: audioTrack, at: .zero)
        guard let export = AVAssetExportSession(asset: composition,
                                                presetName: AVAssetExportPresetPassthrough) else {
            throw FixtureError.writerUnavailable
        }
        export.metadata = [metadataItem(identifier: .commonIdentifierTitle,
                                        value: "Kechil pipeline fixture")]
        if #available(macOS 15.0, *) {
            try await export.export(to: url, as: .mov)
        } else {
            export.outputURL = url
            export.outputFileType = .mov
            await withCheckedContinuation { continuation in
                export.exportAsynchronously { continuation.resume() }
            }
            guard export.status == .completed else {
                throw FixtureError.writeFailed(export.error?.localizedDescription ?? "composition export failed")
            }
        }
    }

    private static func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 180,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 180,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ])
        guard writer.canAdd(input) else { throw FixtureError.writerUnavailable }
        writer.add(input)
        guard writer.startWriting() else {
            throw FixtureError.writeFailed(writer.error?.localizedDescription ?? "writer did not start")
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw FixtureError.writerUnavailable }
        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw FixtureError.writerUnavailable }
            fill(buffer, frame: frame)
            let time = CMTime(value: CMTimeValue(frame), timescale: 30)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw FixtureError.writeFailed(writer.error?.localizedDescription ?? "frame append failed")
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw FixtureError.writeFailed(writer.error?.localizedDescription ?? "writer did not finish")
        }
    }

    private static func makeAudio(at url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000),
              let channel = buffer.floatChannelData?.pointee else {
            throw FixtureError.writerUnavailable
        }
        buffer.frameLength = 96_000
        for frame in 0..<Int(buffer.frameLength) {
            channel[frame] = sin(Float(frame) * 2 * .pi * 440 / 48_000) * 0.15
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private static func fill(_ buffer: CVPixelBuffer, frame: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let offset = x * 4
                row[offset] = UInt8((x + frame * 2) % 256)
                row[offset + 1] = UInt8((y * 2 + frame * 3) % 256)
                row[offset + 2] = UInt8((x + y + frame * 4) % 256)
                row[offset + 3] = 255
            }
        }
    }

    private static func metadataItem(identifier: AVMetadataIdentifier, value: String)
        -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }

    private static func frame(from url: URL, seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds,
                                                              preferredTimescale: 600))
        return image
    }

    private static func averageDifference(_ lhs: CGImage, _ rhs: CGImage) -> Double {
        let width = 160
        let height = 90
        func pixels(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: width * height * 4)
            data.withUnsafeMutableBytes { bytes in
                guard let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
                      let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4, space: colourSpace,
                        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                            CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return data
        }
        let first = pixels(lhs)
        let second = pixels(rhs)
        let total = zip(first, second).reduce(0.0) { partial, pair in
            partial + Double(abs(Int(pair.0) - Int(pair.1)))
        }
        return total / Double(first.count)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}

private enum FixtureError: LocalizedError {
    case writerUnavailable
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .writerUnavailable: return "The fixture video writer is unavailable"
        case .writeFailed(let detail): return "Fixture video write failed: \(detail)"
        }
    }
}
