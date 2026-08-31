import Foundation
import zlib

/// PNG text uses a zlib-wrapped stream, not libcompression's raw DEFLATE format.
/// One decoder is shared by inspection and scoped removal so the two cannot
/// disagree about compressed generator fields. Bounds apply to successful output,
/// not merely to the size of the initial decompression buffer.
enum PNGTextMetadata {
    static let maximumFieldBytes = 4 * 1024 * 1024
    static let maximumImageTextBytes = 16 * 1024 * 1024

    struct Field {
        let key: String
        let text: String

        var isAIGeneration: Bool { MetadataTextClassifier.isAIGeneration(key: key, value: text) }

        /// Dedicated generator fields may be deleted as a unit. A generic caption
        /// or XMP packet can mix an AI declaration with rights or other fields;
        /// rejecting it is safer than silently deleting the entire mixed carrier.
        var canRemoveWholeField: Bool {
            let name = key.lowercased()
            return ["prompt", "negative_prompt", "negative prompt", "parameters", "workflow",
                    "software", "creatortool", "digitalsourcetype", "digital source type",
                    "invokeai_metadata", "invokeai_graph", "sd-metadata"].contains(name) ||
                name.hasPrefix("invokeai_") || name.hasSuffix(":workflow") ||
                name.hasSuffix(":digitalsourcetype")
        }
    }

    enum DecodeError: LocalizedError {
        case invalid
        case tooLarge
        var errorDescription: String? {
            switch self {
            case .invalid: return "PNG text metadata is malformed or its compressed stream is incomplete."
            case .tooLarge: return "PNG text metadata exceeds the safe decoded text limit."
            }
        }
    }

    static func decode(type: String, payload: Data, remainingBytes: inout Int) throws -> Field {
        let bytes = [UInt8](payload)
        guard let end = bytes.firstIndex(of: 0), (1...79).contains(end),
              let key = String(bytes: bytes[..<end], encoding: .isoLatin1) else {
            throw DecodeError.invalid
        }
        var cursor = end + 1
        let compressed: Bool
        let encoding: String.Encoding
        switch type {
        case "tEXt":
            compressed = false
            encoding = .isoLatin1
        case "zTXt":
            guard cursor < bytes.count, bytes[cursor] == 0 else { throw DecodeError.invalid }
            cursor += 1
            compressed = true
            encoding = .isoLatin1
        case "iTXt":
            guard cursor + 2 <= bytes.count, bytes[cursor] <= 1, bytes[cursor + 1] == 0 else {
                throw DecodeError.invalid
            }
            compressed = bytes[cursor] == 1
            cursor += 2
            // Language and translated keyword are terminated independently.
            for _ in 0..<2 {
                guard cursor < bytes.count, let zero = bytes[cursor...].firstIndex(of: 0) else {
                    throw DecodeError.invalid
                }
                cursor = zero + 1
            }
            encoding = .utf8
        default: throw DecodeError.invalid
        }
        let limit = min(maximumFieldBytes, remainingBytes)
        guard limit >= 0 else { throw DecodeError.tooLarge }
        let encoded = Data(bytes[cursor...])
        let decoded: Data
        if compressed {
            decoded = try inflate(encoded, limit: limit)
        } else {
            guard encoded.count <= limit else { throw DecodeError.tooLarge }
            decoded = encoded
        }
        guard let text = String(data: decoded, encoding: encoding), !decoded.contains(0) else {
            throw DecodeError.invalid
        }
        remainingBytes -= decoded.count
        return Field(key: key, text: text)
    }

    private static func inflate(_ data: Data, limit: Int) throws -> Data {
        guard !data.isEmpty else { throw DecodeError.invalid }
        var capacity = min(max(4096, min(data.count, maximumFieldBytes) * 4), max(1, limit))
        while true {
            var output = [UInt8](repeating: 0, count: capacity)
            var decodedCount = uLongf(capacity)
            let status = data.withUnsafeBytes { raw in
                uncompress(&output, &decodedCount, raw.bindMemory(to: UInt8.self).baseAddress!, uLong(data.count))
            }
            if status == Z_OK {
                guard decodedCount <= limit else { throw DecodeError.tooLarge }
                return Data(output.prefix(Int(decodedCount)))
            }
            guard status == Z_BUF_ERROR else { throw DecodeError.invalid }
            guard capacity < limit else { throw DecodeError.tooLarge }
            capacity = min(capacity * 2, limit)
        }
    }
}

/// Generator vocabulary and key-based signals used by both the probe and remover.
enum MetadataTextClassifier {
    static let provenanceMarkers = ["c2pa", "content credentials", "jumbf", "provenance"]
    static let generativeTypes = ["trainedalgorithmicmedia", "compositewithtrainedalgorithmicmedia",
                                  "compositedwithtrainedalgorithmicmedia", "compositesynthetic"]

    static func isComfyWorkflow(key: String, value: String) -> Bool {
        let key = key.lowercased()
        let value = value.lowercased()
        return key == "workflow" || key.hasSuffix(":workflow") ||
            (key == "prompt" && (value.contains("class_type") || value.contains("ksampler")))
    }

    static func isGenerationParameters(key: String, value: String) -> Bool {
        let key = key.lowercased()
        let value = value.lowercased()
        let hasParameterSyntax = value.contains("steps:") || value.contains("sampler:") ||
            value.contains("cfg scale:") || value.contains("negative prompt:")
        return (key.contains("parameters") || key == "prompt") && hasParameterSyntax
    }

    static func isAIGeneration(key: String, value: String) -> Bool {
        let key = key.lowercased()
        let text = (key + " " + value).lowercased()
        let aiField = isAIMetadataKey(key)
        let explicitSourceType = generativeTypes.contains(where: text.contains)
        let dedicatedSyntax = isComfyWorkflow(key: key, value: value) ||
            isGenerationParameters(key: key, value: value) || key.contains("invokeai_") ||
            key.contains("sd-metadata")
        let dedicatedGenerator = aiField && knownGenerator(in: value) != nil
        let parameterSyntax = text.contains("negative prompt:") ||
            (text.contains("steps:") && text.contains("sampler:")) ||
            (text.contains("sampler:") && text.contains("cfg scale:")) ||
            text.contains("model hash")
        let dedicatedParameters = (aiField || parameterSyntax) && parameterSyntax
        // Merely mentioning “C2PA” or “OpenAI” in a caption is not an AI source
        // signal. Provenance vocabulary counts only inside a dedicated carrier or
        // field whose key establishes that context.
        let dedicatedProvenance = aiField && provenanceMarkers.contains(where: text.contains)
        return explicitSourceType || dedicatedSyntax || dedicatedGenerator ||
            dedicatedParameters || dedicatedProvenance
    }

    static func isGeneratorField(key: String, value: String) -> Bool {
        isAIMetadataKey(key.lowercased()) && knownGenerator(in: value) != nil
    }

    private static func isAIMetadataKey(_ key: String) -> Bool {
        let key = key.lowercased()
        return ["prompt", "parameters", "workflow", "software", "creator", "generator",
                "creatortool", "digital source", "digitalsourcetype", "provenance", "c2pa",
                "credential", "claim_generator", "softwareagent", "xmp", "metadata"].contains {
            key == $0 || key.contains($0)
        }
    }

    static func knownGenerator(in text: String) -> String? {
        let text = text.lowercased()
        let generators: [(String, String)] = [
            ("automatic1111", "AUTOMATIC1111 / Stable Diffusion"), ("stable diffusion", "Stable Diffusion"),
            ("comfyui", "ComfyUI"), ("invokeai", "InvokeAI"), ("novelai", "NovelAI"),
            ("midjourney", "Midjourney"), ("adobe firefly", "Adobe Firefly"), ("firefly", "Adobe Firefly"),
            ("dall-e", "OpenAI DALL-E"), ("dall·e", "OpenAI DALL-E"),
            ("gpt-image", "OpenAI image generation"), ("openai image", "OpenAI image generation"),
            ("ideogram", "Ideogram"), ("leonardo.ai", "Leonardo AI"), ("leonardo ai", "Leonardo AI"),
            ("flux.1", "FLUX"), ("black forest labs", "FLUX / Black Forest Labs"),
        ]
        return generators.first(where: { text.contains($0.0) })?.1
    }
}
