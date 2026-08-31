import Foundation
import ImageIO
import zlib

/// Focused regressions for the image AI scope. These fixtures deliberately put
/// generator data in all three PNG text encodings, plus a mixed rights field, so
/// detection and deletion must use the same bounded decoder and must fail closed
/// when a whole-field delete would lose unrelated metadata.
@main
enum ScopedImageSafetyChecks {
    static var assertions = 0
    static var failures = 0

    static func main() throws {
        let plain = png(text: textChunk(type: "tEXt", key: "prompt",
                                         value: "A harbour at dawn; sampler: Euler"))
        let plainReport = ProvenanceProbe.inspect(plain)
        check(plainReport.hasGenerativeAI, "uncompressed PNG prompt is detected")
        let plainClean = try MetadataStripper.strip(plain, preset: .aiMetadata)
        check(plainClean.data.range(of: Data("sampler: Euler".utf8)) == nil,
              "uncompressed PNG generator field is removed")

        let compressed = png(text: textChunk(type: "zTXt", key: "parameters",
                                              value: "Steps: 20, Sampler: Euler, CFG scale: 7",
                                              compressed: true))
        let compressedReport = ProvenanceProbe.inspect(compressed)
        check(compressedReport.hasGenerativeAI, "zTXt generator parameters are decoded and detected")
        let compressedClean = try MetadataStripper.strip(compressed, preset: .aiMetadata)
        check(compressedClean.data.range(of: Data("parameters".utf8)) == nil,
              "zTXt generator field is removed after zlib decoding")

        let workflow = png(text: textChunk(type: "iTXt", key: "prompt",
                                            value: #"{"3":{"class_type":"KSampler"}}"#,
                                            compressed: true))
        let workflowReport = ProvenanceProbe.inspect(workflow)
        check(workflowReport.findings.contains(where: { $0.title == "ComfyUI workflow" }),
              "ComfyUI node graph is detected without a brand name")
        let workflowClean = try MetadataStripper.strip(workflow, preset: .aiMetadata)
        check(workflowClean.data.range(of: Data("KSampler".utf8)) == nil,
              "compressed ComfyUI workflow is removed")

        let ordinary = png(text: textChunk(type: "tEXt", key: "Comment",
                                            value: "A discussion of OpenAI policy"))
        let ordinaryClean = try MetadataStripper.strip(ordinary, preset: .aiMetadata)
        check(ordinaryClean.data == ordinary,
              "ordinary text mentioning OpenAI is not removed by the AI scope")

        let mixed = png(text: textChunk(type: "tEXt", key: "Comment",
                                        value: "negative prompt: blur; Copyright Example Studio"))
        do {
            _ = try MetadataStripper.strip(mixed, preset: .aiMetadata)
            check(false, "mixed AI and rights field is rejected instead of deleted")
        } catch {
            let message = error.localizedDescription.lowercased()
            check(message.contains("shares") || message.contains("unselected") ||
                  message.contains("unchanged"),
                  "mixed AI and rights field explains why it was not deleted")
        }

        let malformed = png(text: malformedZTXt())
        do {
            _ = try MetadataStripper.strip(malformed, preset: .aiMetadata)
            check(false, "malformed compressed text is rejected")
        } catch {
            check(error.localizedDescription.lowercased().contains("could not be decoded") ||
                  error.localizedDescription.lowercased().contains("safely"),
                  "malformed compressed text reports a bounded decode failure")
        }

        print("Scoped image safety checks: \(assertions - failures)/\(assertions) passed")
        if failures != 0 { exit(1) }
    }

    private static func png(text: Data) -> Data {
        var output = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        output.append(chunk("IHDR", Data([0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0])))
        output.append(text)
        output.append(chunk("IDAT", Data()))
        output.append(chunk("IEND", Data()))
        return output
    }

    private static func textChunk(type: String, key: String, value: String,
                                  compressed: Bool = false) -> Data {
        let keyData = Data(key.data(using: .isoLatin1) ?? Data())
        let valueData = Data(value.utf8)
        var payload = keyData
        payload.append(0)
        switch type {
        case "tEXt":
            payload.append(valueData)
        case "zTXt":
            payload.append(0)
            payload.append(compress(valueData))
        case "iTXt":
            payload.append(compressed ? 1 : 0)
            payload.append(0)
            payload.append(0)
            payload.append(0)
            payload.append(compressed ? compress(valueData) : valueData)
        default:
            fatalError("unsupported fixture type")
        }
        return chunk(type, payload)
    }

    private static func malformedZTXt() -> Data {
        chunk("zTXt", Data("parameters\0\0not-a-zlib-stream".utf8))
    }

    private static func compress(_ data: Data) -> Data {
        var capacity = compressBound(uLong(data.count))
        var buffer = [UInt8](repeating: 0, count: Int(capacity))
        let status = data.withUnsafeBytes { raw in
            compress2(&buffer, &capacity,
                      raw.bindMemory(to: UInt8.self).baseAddress!, uLong(data.count), Z_BEST_COMPRESSION)
        }
        precondition(status == Z_OK)
        return Data(buffer.prefix(Int(capacity)))
    }

    private static func chunk(_ type: String, _ payload: Data) -> Data {
        let typeData = Data(type.utf8)
        return be32(UInt32(payload.count)) + typeData + payload + be32(crc32(typeData + payload))
    }

    private static func be32(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24), UInt8((value >> 16) & 255),
              UInt8((value >> 8) & 255), UInt8(value & 255)])
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if condition() { print("PASS: \(message)") }
        else { failures += 1; print("FAIL: \(message)") }
    }
}
