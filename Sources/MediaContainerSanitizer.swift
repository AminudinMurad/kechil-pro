import Foundation

/// Byte-preserving edits for ISO Base Media File Format containers (MOV, MP4,
/// HEIF and AVIF). Metadata boxes are often nested under `moov`/`meta`, so a
/// top-level-only scan can claim to remove C2PA while leaving the actual carrier
/// in place. This walker visits only known box containers and never interprets
/// arbitrary media payload bytes as boxes.
enum MediaContainerSanitizer {
    private static let c2paUUID: [UInt8] = [
        0xD8, 0xFE, 0xC3, 0xD6, 0x1B, 0x0E, 0x48, 0x3C,
        0x92, 0x97, 0x58, 0x28, 0x87, 0x7E, 0xC4, 0x81,
    ]

    // ISO BMFF boxes whose payload is itself a sequence of child boxes. `meta`
    // is a FullBox and has a four-byte version/flags prefix before its children.
    private static let containerTypes: Set<String> = [
        "moov", "trak", "mdia", "minf", "stbl", "edts", "dinf", "mvex",
        "moof", "traf", "mfra", "udta", "meta", "ilst", "ipro", "sinf",
        "schi", "stsd", "wave", "gmhd", "tref", "hnti", "hinf", "strk",
    ]

    private static let aiMarkers = [
        // These are structured/generator-specific signals. Generic words such as
        // “OpenAI”, “C2PA” or “provenance” are intentionally excluded because a
        // normal title or description may mention them without being an AI field.
        "trainedalgorithmicmedia", "compositewithtrainedalgorithmicmedia",
        "compositesynthetic", "claim_generator", "digitalsourcetype", "openai-test-genid",
        "negative prompt", "sampler:", "cfg scale:", "model hash",
        "automatic1111", "stable diffusion", "comfyui", "invokeai", "midjourney",
        "adobe firefly", "dall-e", "gpt-image", "digital source type",
    ]

    /// Replaces C2PA/JUMBF boxes with equal-sized `free` boxes and zeroes their
    /// payload. Keeping every box length and byte offset intact protects media
    /// data references while ensuring the credential bytes cannot be recovered
    /// from the cleaned output.
    static func neutralizeC2PABMFFBoxes(in data: Data,
                                      includingAIMetadataItems: Bool = true) -> (data: Data, count: Int) {
        var bytes = [UInt8](data)
        var removed = 0
        scan(bytes: &bytes, start: 0, end: bytes.count, removed: &removed,
             includingAIMetadataItems: includingAIMetadataItems)
        return (Data(bytes), removed)
    }

    /// Reports a C2PA/JUMBF carrier only when it is found in a parsed BMFF box.
    /// A raw string search is intentionally not used here: a perfectly ordinary
    /// title or description can contain the word “C2PA” without carrying a
    /// credential. This detector shares the same bounded box grammar as the
    /// neutralizer so inspection and cleanup cannot disagree about the carrier.
    static func containsC2PABMFFBoxes(in data: Data) -> Bool {
        let bytes = [UInt8](data)
        return containsC2PA(bytes: bytes, start: 0, end: bytes.count)
    }

    /// Returns a short printable excerpt from a structurally identified C2PA
    /// box. This is inspection evidence only: signatures and binary bytes are
    /// never exposed, and the caller still reports that credentials were not
    /// cryptographically validated. Keeping this extraction in the same walker
    /// prevents arbitrary title/description text from being mistaken for a
    /// provenance carrier.
    static func readableC2PAExcerpt(in data: Data, maxBytes: Int = 4096) -> String? {
        guard maxBytes > 0 else { return nil }
        let bytes = [UInt8](data)
        return readableC2PAExcerpt(bytes: bytes, start: 0, end: bytes.count,
                                   maxBytes: maxBytes)
    }

    private static func scan(bytes: inout [UInt8], start: Int, end: Int,
                             removed: inout Int, includingAIMetadataItems: Bool) {
        var offset = start
        while offset + 8 <= end {
            guard let parsed = parseBox(bytes: bytes, offset: offset, end: end) else { return }
            let (size, header, type) = parsed
            let boxEnd = offset + size

            if isC2PA(type: type, bytes: bytes, payloadStart: offset + header,
                      payloadEnd: boxEnd) {
                bytes.replaceSubrange((offset + 4)..<(offset + 8), with: Array("free".utf8))
                for index in (offset + header)..<boxEnd { bytes[index] = 0 }
                removed += 1
            } else if type == "ilst", includingAIMetadataItems {
                // QuickTime item atoms use a numeric/opaque type rather than a
                // printable fourCC. Inspect each item as metadata, and clear an
                // AI-bearing item while retaining its box and offsets.
                scanILST(bytes: &bytes, start: offset + header, end: boxEnd,
                         removed: &removed)
            } else if containerTypes.contains(type) {
                var childStart = offset + header
                if type == "meta" {
                    // Most ISO BMFF files encode `meta` as a FullBox, but
                    // QuickTime metadata written by AVFoundation can omit the
                    // version/flags word. Choose the first offset that actually
                    // begins with a valid child box instead of assuming one form.
                    let fullBoxStart = childStart + 4
                    if parseBox(bytes: bytes, offset: fullBoxStart, end: boxEnd) != nil {
                        childStart = fullBoxStart
                    }
                }
                if childStart < boxEnd {
                    scan(bytes: &bytes, start: childStart, end: boxEnd, removed: &removed,
                         includingAIMetadataItems: includingAIMetadataItems)
                }
            }

            // A zero-sized box consumes the enclosing range by definition; the
            // parser returns that exact size, so this also guarantees progress.
            offset = boxEnd
        }
    }

    private static func containsC2PA(bytes: [UInt8], start: Int, end: Int) -> Bool {
        var offset = start
        while offset + 8 <= end {
            guard let parsed = parseBox(bytes: bytes, offset: offset, end: end) else { return false }
            let (size, header, type) = parsed
            let boxEnd = offset + size
            if isC2PA(type: type, bytes: bytes, payloadStart: offset + header,
                      payloadEnd: boxEnd) {
                return true
            }
            if containerTypes.contains(type) {
                var childStart = offset + header
                if type == "meta" {
                    let fullBoxStart = childStart + 4
                    if parseBox(bytes: bytes, offset: fullBoxStart, end: boxEnd) != nil {
                        childStart = fullBoxStart
                    }
                }
                if childStart < boxEnd,
                   containsC2PA(bytes: bytes, start: childStart, end: boxEnd) {
                    return true
                }
            }
            offset = boxEnd
        }
        return false
    }

    private static func readableC2PAExcerpt(bytes: [UInt8], start: Int, end: Int,
                                            maxBytes: Int) -> String? {
        var offset = start
        while offset + 8 <= end {
            guard let parsed = parseBox(bytes: bytes, offset: offset, end: end) else { return nil }
            let (size, header, type) = parsed
            let boxEnd = offset + size
            let payloadStart = offset + header
            if isC2PA(type: type, bytes: bytes, payloadStart: payloadStart,
                      payloadEnd: boxEnd) {
                let bounded = bytes[payloadStart..<min(boxEnd, payloadStart + maxBytes)]
                if let excerpt = readableExcerpt(bounded) { return excerpt }
            }
            if containerTypes.contains(type) {
                var childStart = payloadStart
                if type == "meta" {
                    let fullBoxStart = childStart + 4
                    if parseBox(bytes: bytes, offset: fullBoxStart, end: boxEnd) != nil {
                        childStart = fullBoxStart
                    }
                }
                if childStart < boxEnd,
                   let excerpt = readableC2PAExcerpt(bytes: bytes, start: childStart,
                                                     end: boxEnd, maxBytes: maxBytes) {
                    return excerpt
                }
            }
            offset = boxEnd
        }
        return nil
    }

    private static func readableExcerpt<C: Collection>(_ bytes: C) -> String?
        where C.Element == UInt8 {
        var sanitized = [UInt8]()
        sanitized.reserveCapacity(bytes.count)
        for byte in bytes {
            if byte == 9 || byte == 10 || byte == 13 || (byte >= 32 && byte < 127) {
                sanitized.append(byte)
            } else {
                sanitized.append(32)
            }
        }
        let text = String(decoding: sanitized, as: UTF8.self)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        guard ["openai", "sora", "genid", "c2pa", "claim_generator",
               "digital source", "digitalsourcetype", "provenance"]
            .contains(where: lower.contains) else { return nil }
        return text.count > 360 ? String(text.prefix(357)) + "…" : text
    }

    private static func scanILST(bytes: inout [UInt8], start: Int, end: Int,
                                 removed: inout Int) {
        var offset = start
        while offset + 8 <= end {
            guard let parsed = parseBox(bytes: bytes, offset: offset, end: end) else { return }
            let (size, header, _) = parsed
            let boxEnd = offset + size
            let payload = bytes[(offset + header)..<boxEnd]
            if hasAIMarker(payload) {
                for index in (offset + header)..<boxEnd { bytes[index] = 0 }
                removed += 1
            }
            offset = boxEnd
        }
    }

    private static func parseBox(bytes: [UInt8], offset: Int, end: Int)
        -> (size: Int, header: Int, type: String)? {
        guard offset + 8 <= end else { return nil }
        let size32 = readBE32(bytes, offset)
        let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
        var header = 8
        let size: Int
        if size32 == 1 {
            guard offset + 16 <= end else { return nil }
            let extended = readBE64(bytes, offset + 8)
            guard extended >= 16, extended <= UInt64(Int.max) else { return nil }
            size = Int(extended)
            header = 16
        } else if size32 == 0 {
            size = end - offset
        } else {
            size = Int(size32)
        }
        guard size >= header, size <= end - offset else { return nil }
        return (size, header, type)
    }

    private static func isC2PA(type: String, bytes: [UInt8], payloadStart: Int,
                               payloadEnd: Int) -> Bool {
        if type == "c2pa" || type == "jumb" { return true }
        guard type == "uuid", payloadStart <= payloadEnd,
              payloadEnd - payloadStart >= c2paUUID.count else { return false }
        return bytes[payloadStart..<(payloadStart + c2paUUID.count)]
            .elementsEqual(c2paUUID)
    }

    private static func hasAIMarker<C: Collection>(_ bytes: C) -> Bool where C.Element == UInt8 {
        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        return aiMarkers.contains { text.contains($0) }
    }

    private static func readBE32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 |
            UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    private static func readBE64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for byte in bytes[offset..<(offset + 8)] { value = value << 8 | UInt64(byte) }
        return value
    }
}
