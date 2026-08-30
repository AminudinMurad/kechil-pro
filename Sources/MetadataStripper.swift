import Foundation

// MARK: - Types

public enum ImageFormat: String {
    case jpeg = "JPEG"
    case png  = "PNG"
    case webp = "WebP"
    case other = "Other"
}

public struct StripResult {
    /// The cleaned image bytes.
    public let data: Data
    /// Human-readable names of the metadata blocks that were removed.
    public let removed: [String]
    public let format: ImageFormat
    /// True when pixel data was copied verbatim (no re-encode, zero quality loss).
    public let lossless: Bool
}

public enum StripError: LocalizedError {
    case emptyFile
    case malformed(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyFile:            return "File is empty"
        case .malformed(let why):   return "Malformed image: \(why)"
        case .unreadable(let why):  return "Could not read image: \(why)"
        }
    }
}

// MARK: - Stripper

/// Removes metadata from image bytes by surgically deleting metadata
/// segments/chunks from the container, leaving compressed pixel data untouched.
///
/// This is a byte-level container edit, not a decode/re-encode, so output pixels
/// are bit-for-bit identical to the input. Verified by `Tests/verify_algorithm.py`.
public enum MetadataStripper {

    // PNG fails closed: keep only the standard chunks needed to decode/render the
    // image. A denylist silently passes every vendor preview or future metadata chunk.
    private static let pngKeep: Set<String> = [
        "IHDR", "PLTE", "IDAT", "IEND",       // critical image data
        "iCCP", "gAMA", "cHRM", "sRGB", "sBIT", // colour / precision
        "tRNS", "bKGD", "pHYs",                // rendering / dimensions
        "acTL", "fcTL", "fdAT",                // animated PNG
    ]

    // WebP also fails closed. These are the image, animation, alpha and colour chunks;
    // EXIF, XMP, C2PA and unknown vendor chunks are metadata and are dropped.
    private static let webPKeep: Set<String> = [
        "VP8 ", "VP8L", "VP8X", "ALPH", "ANIM", "ANMF", "ICCP",
    ]

    // MARK: Entry point

    public static func strip(_ data: Data) throws -> StripResult {
        guard !data.isEmpty else { throw StripError.emptyFile }
        // Work on a plain array: Data slices preserve parent indices, which is a
        // classic source of off-by-N bugs when slicing repeatedly.
        let bytes = [UInt8](data)

        switch detect(bytes) {
        case .jpeg:  return try stripJPEG(bytes)
        case .png:   return try stripPNG(bytes)
        case .webp:  return try stripWebP(bytes)
        case .other: return try stripViaImageIO(data)   // ImageIOStripper.swift
        }
    }

    public static func strip(fileAt url: URL) throws -> StripResult {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw StripError.unreadable(error.localizedDescription) }
        return try strip(data)
    }

    // MARK: Format detection (by magic bytes, never by file extension)

    public static func detect(_ b: [UInt8]) -> ImageFormat {
        if b.count > 3, b[0] == 0xFF, b[1] == 0xD8 { return .jpeg }
        if b.count > 8, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47,
           b[4] == 0x0D, b[5] == 0x0A, b[6] == 0x1A, b[7] == 0x0A { return .png }
        if b.count > 12, ascii(b, 0, 4) == "RIFF", ascii(b, 8, 4) == "WEBP" { return .webp }
        return .other
    }

    public static func detect(_ data: Data) -> ImageFormat {
        detect([UInt8](data.prefix(16)))
    }

    // MARK: JPEG

    private static func stripJPEG(_ b: [UInt8]) throws -> StripResult {
        let n = b.count
        var out = Data(capacity: n)
        out.append(contentsOf: b[0..<2])          // SOI
        var removed: [String] = []
        var i = 2

        while i < n {
            // Anything that isn't a marker boundary: copy the remainder as-is.
            guard b[i] == 0xFF, i + 1 < n else {
                out.append(contentsOf: b[i..<n]); break
            }
            let marker = b[i + 1]

            if marker == 0xFF { i += 1; continue }          // fill byte
            if marker == 0xD9 {                             // EOI
                out.append(contentsOf: b[i..<min(i + 2, n)])
                i += 2
                if i < n { removed.append("Trailing data after JPEG EOI") }
                break
            }
            if (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01 {
                out.append(contentsOf: b[i..<min(i + 2, n)]); i += 2; continue
            }

            guard i + 3 < n else { out.append(contentsOf: b[i..<n]); break }
            let length = Int(b[i + 2]) << 8 | Int(b[i + 3])
            guard length >= 2 else {
                throw StripError.malformed("JPEG segment length \(length) at offset \(i)")
            }
            let end = i + 2 + length
            guard end <= n else {
                throw StripError.malformed("JPEG segment overruns file at offset \(i)")
            }

            let isMetadata = (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE
            if isMetadata && !keepJPEGSegment(marker: marker, bytes: b,
                                               payloadStart: i + 4, end: end) {
                removed.append(jpegSegmentName(marker: marker, bytes: b, segStart: i))
                i = end
                continue
            }

            out.append(contentsOf: b[i..<end])
            i = end

            if marker == 0xDA {
                // Copy the entropy-coded scan verbatim until an unstuffed marker.
                // FF00 is a literal FF byte and FFD0...FFD7 are restart markers inside
                // the scan. Any other FFxx begins the next marker segment — including
                // APPn between progressive scans and the final EOI.
                let scanStart = i
                var foundNextMarker = false
                while i + 1 < n {
                    guard b[i] == 0xFF else { i += 1; continue }
                    var j = i + 1
                    while j < n, b[j] == 0xFF { j += 1 }
                    guard j < n else { i = n; break }
                    let next = b[j]
                    if next == 0x00 || (next >= 0xD0 && next <= 0xD7) {
                        i = j + 1
                        continue
                    }
                    out.append(contentsOf: b[scanStart..<i])
                    foundNextMarker = true
                    break
                }
                if !foundNextMarker {
                    out.append(contentsOf: b[scanStart..<n])
                    break
                }
            }
        }

        return StripResult(data: out, removed: dedupe(removed), format: .jpeg, lossless: true)
    }

    /// APP numbers are carriers, not content types. Preserve a segment only when its
    /// signature proves it is rendering data; JFXX and MPF use APP0/APP2 too and can
    /// embed thumbnails or complete secondary JPEGs with their own GPS metadata.
    private static func keepJPEGSegment(marker: UInt8, bytes: [UInt8],
                                        payloadStart: Int, end: Int) -> Bool {
        switch marker {
        case 0xE0: return hasPrefix(Array("JFIF\0".utf8), in: bytes, at: payloadStart, end: end)
        case 0xE2: return hasPrefix(Array("ICC_PROFILE".utf8), in: bytes, at: payloadStart, end: end)
        case 0xEE: return hasPrefix(Array("Adobe".utf8), in: bytes, at: payloadStart, end: end)
        default: return false
        }
    }

    private static func jpegSegmentName(marker: UInt8, bytes b: [UInt8], segStart: Int) -> String {
        if marker == 0xFE { return "JPEG comment" }
        let sig = ascii(b, segStart + 4, 32)
        switch marker {
        case 0xE1:
            if sig.hasPrefix("Exif")            { return "EXIF / GPS location" }
            if sig.contains("ns.adobe.com/xap") { return "XMP" }
            return "APP1 metadata"
        case 0xEB: return "C2PA / Content Credentials"
        case 0xED: return "IPTC / Photoshop"
        case 0xEC: return "Picture info"
        case 0xE3: return "Thumbnail / maker data"
        default:   return "APP\(Int(marker) - 0xE0) metadata"
        }
    }

    // MARK: PNG

    private static func stripPNG(_ b: [UInt8]) throws -> StripResult {
        let n = b.count
        var out = Data(capacity: n)
        out.append(contentsOf: b[0..<8])          // signature
        var removed: [String] = []
        var i = 8

        // Chunk layout: length(4, BE) | type(4) | data(length) | CRC(4)
        // Kept chunks are copied byte-for-byte, so their CRCs stay valid and
        // nothing needs recomputing.
        while i + 12 <= n {
            let length = Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
            guard length >= 0, length <= n else {
                throw StripError.malformed("PNG chunk length \(length) at offset \(i)")
            }
            let type = ascii(b, i + 4, 4)
            let end = min(i + 12 + length, n)

            if !pngKeep.contains(type) {
                removed.append(pngChunkName(type))
                i = end
                continue
            }

            out.append(contentsOf: b[i..<end])
            i = end
            if type == "IEND" { break }
        }

        return StripResult(data: out, removed: dedupe(removed), format: .png, lossless: true)
    }

    private static func pngChunkName(_ type: String) -> String {
        switch type {
        case "tEXt": return "Text metadata"
        case "zTXt": return "Compressed text metadata"
        case "iTXt": return "XMP / AI generation params"
        case "eXIf": return "EXIF / GPS location"
        case "tIME": return "Timestamp"
        case "caBX": return "C2PA / Content Credentials"
        case "dSIG": return "Digital signature"
        default:     return "PNG \(type) private metadata"
        }
    }

    // MARK: WebP

    private static func stripWebP(_ b: [UInt8]) throws -> StripResult {
        let n = b.count
        var removed: [String] = []
        var kept: [[UInt8]] = []
        var vp8xIndex = -1
        var i = 12                                 // past "RIFF" + size + "WEBP"

        // Chunk layout: fourcc(4) | size(4, LE) | payload(size) | pad to even
        while i + 8 <= n {
            let fourcc = ascii(b, i, 4)
            let size = Int(b[i + 4]) | Int(b[i + 5]) << 8 | Int(b[i + 6]) << 16 | Int(b[i + 7]) << 24
            guard size >= 0, size <= n else {
                throw StripError.malformed("WebP chunk size \(size) at offset \(i)")
            }
            let end = min(i + 8 + size + (size & 1), n)

            if !webPKeep.contains(fourcc) {
                switch fourcc {
                case "EXIF": removed.append("EXIF / GPS location")
                case "XMP ": removed.append("XMP")
                case "C2PA": removed.append("C2PA / Content Credentials")
                default:     removed.append("WebP \(fourcc) private metadata")
                }
                i = end
                continue
            }
            if fourcc == "VP8X" { vp8xIndex = kept.count }

            kept.append(Array(b[i..<end]))
            i = end
        }

        // The VP8X extended-header flags byte advertises which optional chunks
        // exist. Leaving EXIF/XMP bits set after deleting those chunks yields a
        // technically invalid file, so clear them.
        //   bit 3 (0x08) = EXIF present, bit 2 (0x04) = XMP present
        if vp8xIndex >= 0, kept[vp8xIndex].count > 8 {
            kept[vp8xIndex][8] &= ~UInt8(0x08) & ~UInt8(0x04)
        }

        var body = Data()
        for chunk in kept { body.append(contentsOf: chunk) }

        var out = Data(capacity: body.count + 12)
        out.append(contentsOf: Array("RIFF".utf8))
        let riffSize = UInt32(4 + body.count)      // "WEBP" + payload
        out.append(contentsOf: [
            UInt8(riffSize & 0xFF),
            UInt8((riffSize >> 8) & 0xFF),
            UInt8((riffSize >> 16) & 0xFF),
            UInt8((riffSize >> 24) & 0xFF),
        ])
        out.append(contentsOf: Array("WEBP".utf8))
        out.append(body)

        return StripResult(data: out, removed: dedupe(removed), format: .webp, lossless: true)
    }

    // MARK: Helpers

    /// Reads `len` bytes as ASCII, mapping non-printable bytes to spaces so this
    /// is always safe on arbitrary binary input.
    static func ascii(_ b: [UInt8], _ start: Int, _ len: Int) -> String {
        guard start >= 0, start < b.count else { return "" }
        let end = min(start + len, b.count)
        var s = ""
        s.reserveCapacity(end - start)
        for k in start..<end {
            let c = b[k]
            s.append((c >= 32 && c < 127) ? Character(UnicodeScalar(c)) : " ")
        }
        return s
    }

    /// Preserves first-seen order while removing duplicates, so a file with three
    /// APP1 segments reports "EXIF / GPS location" once.
    static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    private static func hasPrefix(_ prefix: [UInt8], in bytes: [UInt8],
                                  at start: Int, end: Int) -> Bool {
        guard start >= 0, start + prefix.count <= end, end <= bytes.count else { return false }
        return bytes[start..<(start + prefix.count)].elementsEqual(prefix)
    }
}
