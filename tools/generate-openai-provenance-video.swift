import AVFoundation
import CoreGraphics
import CoreText
import CoreVideo
import Foundation

@main
enum OpenAIProvenanceVideoGenerator {
    private static let width = 640
    private static let height = 360
    private static let frameRate: Int32 = 30
    private static let frameCount = 150

    static func main() async throws {
        guard CommandLine.arguments.count >= 2 else {
            throw GeneratorError.usage
        }
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let identifier = CommandLine.arguments.count >= 3
            ? CommandLine.arguments[2]
            : "openai-test-\(UUID().uuidString.lowercased())"
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: outputURL)

        try await writeMovie(to: outputURL, identifier: identifier)
        try appendSyntheticC2PACarrier(to: outputURL, identifier: identifier)
        try writeManifest(nextTo: outputURL, identifier: identifier)

        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard abs(seconds - 5.0) < 0.05 else {
            throw GeneratorError.validation("expected 5 seconds; got \(seconds)")
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw GeneratorError.validation("no video track")
        }
        let size = try await track.load(.naturalSize)
        guard Int(size.width) == width, Int(size.height) == height else {
            throw GeneratorError.validation("unexpected dimensions \(size)")
        }
        let data = try Data(contentsOf: outputURL)
        guard data.range(of: Data("c2pa".utf8)) != nil,
              data.range(of: Data(identifier.utf8)) != nil else {
            throw GeneratorError.validation("embedded provenance fixture was not found")
        }

        let byteCount = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        print("Created: \(outputURL.path)")
        print("OpenAI generative test ID: \(identifier)")
        print("Duration: \(String(format: "%.3f", seconds)) seconds")
        print("Video: \(width)x\(height), \(frameRate) fps, H.264 MOV")
        print("Bytes: \(byteCount)")
        print("Credential status: synthetic unsigned test declaration")
    }

    private static func writeMovie(to url: URL, identifier: String) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.metadata = [
            metadataItem(.commonIdentifierTitle, "OpenAI generative provenance test"),
            metadataItem(.commonIdentifierDescription,
                         "Synthetic unsigned C2PA test declaration. OpenAI Generative ID: \(identifier)"),
            metadataItem(.commonIdentifierCreator, "OpenAI-style synthetic test fixture"),
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_500_000,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ])
        guard writer.canAdd(input) else { throw GeneratorError.writerUnavailable }
        writer.add(input)
        guard writer.startWriting() else {
            throw GeneratorError.writeFailed(writer.error?.localizedDescription ?? "writer did not start")
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw GeneratorError.writerUnavailable }

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw GeneratorError.writerUnavailable }
            draw(buffer, frame: frame, identifier: identifier)
            let time = CMTime(value: CMTimeValue(frame), timescale: frameRate)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw GeneratorError.writeFailed(writer.error?.localizedDescription ?? "frame append failed")
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw GeneratorError.writeFailed(writer.error?.localizedDescription ?? "writer did not finish")
        }
    }

    private static func draw(_ buffer: CVPixelBuffer, frame: Int, identifier: String) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: base, width: width, height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: colourSpace,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                                          CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return }

        let progress = CGFloat(frame) / CGFloat(frameCount - 1)
        let colours = [
            CGColor(red: 0.03 + progress * 0.08, green: 0.09, blue: 0.18, alpha: 1),
            CGColor(red: 0.05, green: 0.58 - progress * 0.18, blue: 0.44, alpha: 1),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colourSpace, colors: colours, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero,
                                       end: CGPoint(x: width, y: height), options: [])
        }

        context.setFillColor(CGColor(gray: 1, alpha: 0.10))
        let orbit = CGFloat(frame) * 0.055
        let x = 485 + cos(orbit) * 58
        let y = 178 + sin(orbit) * 58
        context.fillEllipse(in: CGRect(x: x - 58, y: y - 58, width: 116, height: 116))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.32))
        context.setLineWidth(2)
        context.strokeEllipse(in: CGRect(x: x - 72, y: y - 72, width: 144, height: 144))

        drawText("Synthetic provenance test", size: 30, fontName: "Helvetica Neue Bold",
                 color: CGColor(gray: 1, alpha: 1), at: CGPoint(x: 42, y: 264), in: context)
        drawText("5-second H.264 sample", size: 20, fontName: "Helvetica Neue Medium",
                 color: CGColor(gray: 1, alpha: 0.78), at: CGPoint(x: 44, y: 225), in: context)
        drawText("OpenAI generative test ID", size: 15, fontName: "Helvetica Neue Medium",
                 color: CGColor(gray: 1, alpha: 0.72), at: CGPoint(x: 44, y: 112), in: context)
        drawText(identifier, size: 14, fontName: "Helvetica Neue",
                 color: CGColor(gray: 1, alpha: 0.95), at: CGPoint(x: 44, y: 80), in: context)
        drawText("Unsigned fixture - for Kechil Clean testing only", size: 13,
                 fontName: "Helvetica Neue",
                 color: CGColor(gray: 1, alpha: 0.58), at: CGPoint(x: 44, y: 38), in: context)
    }

    private static func drawText(_ text: String, size: CGFloat, fontName: String,
                                 color: CGColor, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        let line = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private static func metadataItem(_ identifier: AVMetadataIdentifier, _ value: String)
        -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }

    /// Appends a legal top-level ISO BMFF UUID carrier. The payload deliberately looks like
    /// provenance data for removal tests, but it is not signed and is not a valid C2PA claim.
    private static func appendSyntheticC2PACarrier(to url: URL, identifier: String) throws {
        let declaration: [String: Any] = [
            "c2pa": "synthetic-test-declaration",
            "claim_generator": "OpenAI Sora (synthetic test declaration)",
            "digitalSourceType": "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia",
            "openai_generative_id": identifier,
            "synthetic_unsigned_fixture": true,
            "warning": "Not an authentic OpenAI Content Credential or SynthID watermark",
        ]
        let payload = try JSONSerialization.data(withJSONObject: declaration,
                                                 options: [.sortedKeys, .withoutEscapingSlashes])
        let c2paUUID: [UInt8] = [
            0xD8, 0xFE, 0xC3, 0xD6, 0x1B, 0x0E, 0x48, 0x3C,
            0x92, 0x97, 0x58, 0x28, 0x87, 0x7E, 0xC4, 0x81,
        ]
        let boxSize = 4 + 4 + c2paUUID.count + payload.count
        guard boxSize <= Int(UInt32.max) else {
            throw GeneratorError.validation("provenance carrier is too large")
        }
        var bigEndianSize = UInt32(boxSize).bigEndian
        var box = withUnsafeBytes(of: &bigEndianSize) { Data($0) }
        box.append(Data("uuid".utf8))
        box.append(contentsOf: c2paUUID)
        box.append(payload)

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: box)
    }

    private static func writeManifest(nextTo videoURL: URL, identifier: String) throws {
        let manifestURL = videoURL.deletingPathExtension().appendingPathExtension("json")
        let manifest: [String: Any] = [
            "file": videoURL.lastPathComponent,
            "duration_seconds": 5,
            "resolution": "640x360",
            "codec": "H.264",
            "openai_generative_id": identifier,
            "credential_status": "synthetic unsigned test declaration",
            "purpose": "Kechil PRO video metadata detection and Clean removal testing",
            "not_authentic_openai_provenance": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifestURL, options: .atomic)
    }
}

private enum GeneratorError: LocalizedError {
    case usage
    case writerUnavailable
    case writeFailed(String)
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: generator OUTPUT.mov [OPENAI_TEST_ID]"
        case .writerUnavailable:
            return "The video writer is unavailable"
        case .writeFailed(let detail):
            return "Video generation failed: \(detail)"
        case .validation(let detail):
            return "Generated video validation failed: \(detail)"
        }
    }
}
