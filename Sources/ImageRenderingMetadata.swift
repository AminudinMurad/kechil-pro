import Foundation
import ImageIO

/// Retain display orientation without keeping identifying EXIF or touching pixels.
enum ImageRenderingMetadata {
    static func orientation(from data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawOrientation = properties[kCGImagePropertyOrientation],
              let orientation = (rawOrientation as? Int) ?? (rawOrientation as? NSNumber)?.intValue,
              (1...8).contains(orientation) else { return nil }
        return orientation
    }

    /// Only our exact single-tag payload is exempt. No extra IFDs/trailing bytes.
    static func isOrientationOnlyEXIF(_ data: Data) -> Bool {
        guard data.count == 26 || data.count == 32 else { return false }
        return (1...8).contains { value in
            let payload = exifPayload(orientation: value)
            return data == payload || data == Data(payload.dropFirst(6))
        }
    }

    static func exifPayload(orientation: Int) -> Data {
        precondition((1...8).contains(orientation))
        return Data([
            0x45, 0x78, 0x69, 0x66, 0, 0,
            0x4D, 0x4D, 0, 0x2A, 0, 0, 0, 8,
            0, 1,
            1, 0x12, 0, 3, 0, 0, 0, 1,
            0, UInt8(orientation), 0, 0,
            0, 0, 0, 0
        ])
    }

    static func preservingOrientation(of original: Data, in result: StripResult) throws -> StripResult {
        guard let originalOrientation = orientation(from: original), originalOrientation != 1 else { return result }
        if let existing = orientation(from: result.data) {
            guard existing == originalOrientation else {
                throw StripError.unsupported("display orientation changed while cleaning; the original is unchanged")
            }
            return result
        }
        let payload = exifPayload(orientation: originalOrientation)
        var output = result.data
        switch result.format {
        case .jpeg:
            let length = payload.count + 2
            var segment = Data([0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 255)])
            segment.append(payload)
            output.insert(contentsOf: segment, at: 2)
        case .png:
            guard output.count >= 33, String(decoding: output[12..<16], as: UTF8.self) == "IHDR" else {
                throw StripError.malformed("PNG IHDR is missing while preserving orientation")
            }
            let tiff = Data(payload.dropFirst(6))
            var chunk = be32(UInt32(tiff.count))
            let typeAndPayload = Data("eXIf".utf8) + tiff
            chunk.append(typeAndPayload)
            chunk.append(be32(crc32(typeAndPayload)))
            output.insert(contentsOf: chunk, at: 33)
        case .webp:
            var cursor = 12
            var flagsOffset: Int?
            while cursor + 8 <= output.count {
                let size = Int(output[cursor + 4]) | Int(output[cursor + 5]) << 8 |
                    Int(output[cursor + 6]) << 16 | Int(output[cursor + 7]) << 24
                guard size <= output.count - cursor - 8 else { break }
                if String(decoding: output[cursor..<(cursor + 4)], as: UTF8.self) == "VP8X", size >= 10 {
                    flagsOffset = cursor + 8
                    break
                }
                cursor += 8 + size + (size & 1)
            }
            guard let flagsOffset else {
                throw StripError.unsupported("WebP orientation cannot be preserved without a valid extended header")
            }
            output[flagsOffset] |= 0x08
            output.append(Data("EXIF".utf8))
            output.append(le32(UInt32(payload.count)))
            output.append(payload)
            if payload.count & 1 != 0 { output.append(0) }
            guard output.count - 8 <= Int(UInt32.max) else { throw StripError.malformed("WebP size overflow") }
            output.replaceSubrange(4..<8, with: le32(UInt32(output.count - 8)))
        case .other:
            return result
        }
        guard self.orientation(from: output) == originalOrientation else {
            throw StripError.unsupported("display orientation could not be retained without re-encoding")
        }
        return StripResult(data: output, removed: result.removed, format: result.format,
                           lossless: result.lossless,
                           preserved: result.preserved + ["Display orientation (\(originalOrientation)); encoded pixels unchanged"])
    }

    private static func be32(_ n: UInt32) -> Data {
        Data([UInt8(n >> 24), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)])
    }
    private static func le32(_ n: UInt32) -> Data { Data(be32(n).reversed()) }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xEDB88320) }
        }
        return crc ^ 0xFFFFFFFF
    }
}
