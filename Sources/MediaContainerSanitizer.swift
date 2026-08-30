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
        "c2pa", "content credentials", "provenance", "openai", "generative ai",
        "trainedalgorithmicmedia", "compositewithtrainedalgorithmicmedia",
        "automatic1111", "stable diffusion", "comfyui", "invokeai", "midjourney",
        "adobe firefly", "dall-e", "gpt-image", "negative prompt", "sampler:",
        "cfg scale:", "model hash", "digital source type",
    ]

    /// Replaces C2PA/JUMBF boxes with equal-sized `free` boxes and zeroes their
    /// payload. Keeping every box length and byte offset intact protects media
    /// data references while ensuring the credential bytes cannot be recovered
    /// from the cleaned output.
    static func neutralizeC2PABMFFBoxes(in data: Data) -> (data: Data, count: Int) {
        var bytes = [UInt8](data)
        var removed = 0
        scan(bytes: &bytes, start: 0, end: bytes.count, removed: &removed)
        return (Data(bytes), removed)
    }

    private static func scan(bytes: inout [UInt8], start: Int, end: Int,
                             removed: inout Int) {
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
            } else if type == "ilst" {
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
                    scan(bytes: &bytes, start: childStart, end: boxEnd, removed: &removed)
                }
            }

            // A zero-sized box consumes the enclosing range by definition; the
            // parser returns that exact size, so this also guarantees progress.
            offset = boxEnd
        }
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
