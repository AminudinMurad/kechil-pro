import Foundation
import ImageIO

/// Scoped image cleanup. The existing byte-level all-metadata path remains the
/// default; these paths only remove the selected scope and keep unrelated fields
/// wherever the container exposes a safe way to do so.
extension MetadataStripper {
    static func strip(_ data: Data, preset: CleanPreset) throws -> StripResult {
        guard preset != .allMetadata else { return try strip(data) }
        guard !data.isEmpty else { throw StripError.emptyFile }

        switch preset {
        case .allMetadata:
            return try strip(data)
        case .aiMetadata:
            switch detect(data) {
            case .jpeg: return try ScopedMetadataStripper.stripJPEGAI(data)
            case .png:  return try ScopedMetadataStripper.stripPNGAI(data)
            case .webp: return try ScopedMetadataStripper.stripWebPAI(data)
            case .other:
                return try ScopedMetadataStripper.stripViaImageIO(data, preset: preset)
            }
        case .exif, .gps:
            return try ScopedMetadataStripper.stripViaImageIO(data, preset: preset)
        }
    }
}

private enum ScopedMetadataStripper {
    // These names mirror the provenance probe's generator vocabulary. Matching
    // full phrases avoids treating an unrelated word such as "chair" as AI data.
    private static let aiMarkers = [
        "c2pa", "content credentials", "jumbf", "provenance",
        "trainedalgorithmicmedia", "compositewithtrainedalgorithmicmedia",
        "compositedwithtrainedalgorithmicmedia", "compositesynthetic",
        "automatic1111", "stable diffusion", "comfyui", "invokeai",
        "novelai", "midjourney", "adobe firefly", "dall-e", "dall·e",
        "gpt-image", "openai image", "ideogram", "leonardo.ai", "leonardo ai",
        "flux.1", "black forest labs", "negative prompt", "sampler:",
        "cfg scale:", "model hash", "digital sourcetype", "digital source type",
    ]

    static func stripJPEGAI(_ data: Data) throws -> StripResult {
        let bytes = [UInt8](data)
        guard bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
            throw StripError.malformed("JPEG signature is missing")
        }

        let n = bytes.count
        var output = Data(bytes[0..<2])
        var removed: [String] = []
        var index = 2

        while index < n {
            guard bytes[index] == 0xFF, index + 1 < n else {
                output.append(contentsOf: bytes[index..<n])
                break
            }
            let marker = bytes[index + 1]
            if marker == 0xFF { index += 1; continue }
            if marker == 0xD9 {
                output.append(contentsOf: bytes[index..<min(index + 2, n)])
                index += 2
                break
            }
            if (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01 {
                output.append(contentsOf: bytes[index..<min(index + 2, n)])
                index += 2
                continue
            }

            guard index + 3 < n else {
                output.append(contentsOf: bytes[index..<n])
                break
            }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2 else {
                throw StripError.malformed("JPEG segment length \(length) at offset \(index)")
            }
            let end = index + 2 + length
            guard end <= n else {
                throw StripError.malformed("JPEG segment overruns file at offset \(index)")
            }

            let payloadStart = index + 4
            let payload = Array(bytes[payloadStart..<end])
            let metadata = (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE
            let shouldRemove = metadata && (marker == 0xEB || hasAIMarker(payload))
            if shouldRemove {
                removed.append(jpegName(marker: marker, payload: payload))
            } else {
                output.append(contentsOf: bytes[index..<end])
            }
            index = end

            if marker == 0xDA {
                // Entropy-coded data may contain FF00 and restart markers. Copy it
                // verbatim until the next unescaped marker so pixels never change.
                let scanStart = index
                var foundNextMarker = false
                while index + 1 < n {
                    guard bytes[index] == 0xFF else { index += 1; continue }
                    var nextIndex = index + 1
                    while nextIndex < n, bytes[nextIndex] == 0xFF { nextIndex += 1 }
                    guard nextIndex < n else { index = n; break }
                    let next = bytes[nextIndex]
                    if next == 0x00 || (next >= 0xD0 && next <= 0xD7) {
                        index = nextIndex + 1
                        continue
                    }
                    output.append(contentsOf: bytes[scanStart..<index])
                    foundNextMarker = true
                    break
                }
                if !foundNextMarker {
                    output.append(contentsOf: bytes[scanStart..<n])
                    break
                }
            }
        }

        guard !removed.isEmpty else {
            return StripResult(data: data, removed: [], format: .jpeg, lossless: true)
        }
        return StripResult(data: output, removed: MetadataStripper.dedupe(removed),
                           format: .jpeg, lossless: true)
    }

    static func stripPNGAI(_ data: Data) throws -> StripResult {
        let bytes = [UInt8](data)
        guard bytes.count >= 8,
              bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
              bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A
        else { throw StripError.malformed("PNG signature is missing") }

        var output = Data(bytes[0..<8])
        var removed: [String] = []
        var index = 8
        while index + 12 <= bytes.count {
            let length = Int(bytes[index]) << 24 | Int(bytes[index + 1]) << 16 |
                Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 0, length <= bytes.count - index - 12 else {
                throw StripError.malformed("PNG chunk overruns file at offset \(index)")
            }
            let type = ascii(bytes, index + 4, 4)
            let payloadStart = index + 8
            let end = index + 12 + length
            let payload = Array(bytes[payloadStart..<(payloadStart + length)])
            let remove = type == "caBX" ||
                ((type == "tEXt" || type == "zTXt" || type == "iTXt" || type == "dSIG") &&
                 hasAIMarker(payload))
            if remove {
                removed.append(pngName(type))
            } else {
                output.append(contentsOf: bytes[index..<end])
            }
            index = end
            if type == "IEND" { break }
        }

        guard !removed.isEmpty else {
            return StripResult(data: data, removed: [], format: .png, lossless: true)
        }
        return StripResult(data: output, removed: MetadataStripper.dedupe(removed),
                           format: .png, lossless: true)
    }

    static func stripWebPAI(_ data: Data) throws -> StripResult {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, ascii(bytes, 0, 4) == "RIFF", ascii(bytes, 8, 4) == "WEBP"
        else { throw StripError.malformed("WebP signature is missing") }

        var kept: [[UInt8]] = []
        var removed: [String] = []
        var vp8xIndex = -1
        var index = 12
        while index + 8 <= bytes.count {
            let fourCC = ascii(bytes, index, 4)
            let size = Int(bytes[index + 4]) | Int(bytes[index + 5]) << 8 |
                Int(bytes[index + 6]) << 16 | Int(bytes[index + 7]) << 24
            guard size >= 0, size <= bytes.count - index - 8 else {
                throw StripError.malformed("WebP chunk overruns file at offset \(index)")
            }
            let end = index + 8 + size + (size & 1)
            let payload = Array(bytes[(index + 8)..<(index + 8 + size)])
            let remove = fourCC == "C2PA" ||
                ((fourCC == "XMP " || fourCC == "EXIF") && hasAIMarker(payload))
            if remove {
                removed.append(webPName(fourCC))
            } else {
                if fourCC == "VP8X" { vp8xIndex = kept.count }
                kept.append(Array(bytes[index..<end]))
            }
            index = end
        }

        guard !removed.isEmpty else {
            return StripResult(data: data, removed: [], format: .webp, lossless: true)
        }

        // VP8X advertises optional EXIF/XMP chunks. Clear only those bits when
        // the corresponding chunks were removed; the image payload stays intact.
        if vp8xIndex >= 0, kept[vp8xIndex].count > 8 {
            kept[vp8xIndex][8] &= ~UInt8(0x08) & ~UInt8(0x04)
        }
        var body = Data()
        for chunk in kept { body.append(contentsOf: chunk) }
        let riffSize = UInt32(4 + body.count)
        var output = Data("RIFF".utf8)
        output.append(contentsOf: [UInt8(riffSize & 0xFF), UInt8((riffSize >> 8) & 0xFF),
                                   UInt8((riffSize >> 16) & 0xFF), UInt8((riffSize >> 24) & 0xFF)])
        output.append(contentsOf: Data("WEBP".utf8))
        output.append(body)
        return StripResult(data: output, removed: MetadataStripper.dedupe(removed),
                           format: .webp, lossless: true)
    }

    static func stripViaImageIO(_ data: Data, preset: CleanPreset) throws -> StripResult {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(source) else {
            throw StripError.unreadable("unrecognised image format")
        }

        let before = ProvenanceProbe.inspect(data)
        guard preset.hasRemaining(in: before) else {
            return StripResult(data: data, removed: [], format: MetadataStripper.detect(data), lossless: true)
        }

        let delete: CFNull = kCFNull
        var copyOptions: [CFString: Any] = [:]
        switch preset {
        case .gps:
            // `CGImageDestinationCopyImageSource` accepts destination-copy options,
            // not the property dictionaries returned by CGImageSource. Passing
            // `kCGImagePropertyGPSDictionary: kCFNull` therefore fails on current
            // macOS with kCGImageDestinationMetadata/-Orientation/-DateTime or an
            // exclude flag required. Supply the source metadata explicitly so all
            // non-location EXIF/TIFF/XMP fields survive, then use ImageIO's dedicated
            // GPS exclusion flag to remove both EXIF GPS and mirrored XMP GPS tags.
            guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
                throw StripError.unreadable(
                    "could not preserve the image metadata while removing GPS")
            }
            copyOptions[kCGImageDestinationMetadata] = metadata
            copyOptions[kCGImageMetadataShouldExcludeGPS] = true
        case .exif:
            copyOptions[kCGImagePropertyExifDictionary] = delete
            copyOptions[kCGImagePropertyExifAuxDictionary] = delete
            copyOptions[kCGImagePropertyTIFFDictionary] = delete
            copyOptions[kCGImagePropertyMakerAppleDictionary] = delete
        case .aiMetadata:
            // ImageIO does not expose a portable XMP/C2PA deletion key on every
            // macOS-supported container. Remove the known metadata dictionaries
            // and let the output probe report any opaque carrier that remains.
            copyOptions[kCGImagePropertyExifDictionary] = delete
            copyOptions[kCGImagePropertyExifAuxDictionary] = delete
            copyOptions[kCGImagePropertyTIFFDictionary] = delete
            copyOptions[kCGImagePropertyMakerAppleDictionary] = delete
            copyOptions[kCGImagePropertyIPTCDictionary] = delete
        case .allMetadata:
            return try MetadataStripper.strip(data)
        }

        let frameCount = max(1, CGImageSourceGetCount(source))
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, uti, frameCount, nil) else {
            throw StripError.unreadable("no encoder available for this format")
        }

        var cfError: Unmanaged<CFError>?
        let copied = CGImageDestinationCopyImageSource(destination, source,
                                                        copyOptions as CFDictionary, &cfError)
        guard copied, output.length > 0 else {
            let why = cfError?.takeRetainedValue().localizedDescription ?? "the encoder rejected the copy"
            throw StripError.unreadable(why)
        }

        let resultData = output as Data
        let removed = labelsRemoved(from: before, preset: preset)
        return StripResult(data: resultData,
                           removed: removed,
                           format: MetadataStripper.detect(resultData),
                           lossless: true)
    }

    private static func hasAIMarker(_ bytes: [UInt8]) -> Bool {
        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        return aiMarkers.contains { text.contains($0) }
    }

    private static func ascii(_ bytes: [UInt8], _ start: Int, _ length: Int) -> String {
        guard start >= 0, start < bytes.count else { return "" }
        let end = min(start + length, bytes.count)
        return String(bytes: bytes[start..<end], encoding: .ascii) ?? ""
    }

    private static func jpegName(marker: UInt8, payload: [UInt8]) -> String {
        if marker == 0xEB { return "C2PA / Content Credentials" }
        let text = String(decoding: payload, as: UTF8.self).lowercased()
        if text.contains("xmp") || text.contains("ns.adobe.com") {
            return "XMP / AI generation data"
        }
        return "AI metadata"
    }

    private static func pngName(_ type: String) -> String {
        switch type {
        case "caBX": return "C2PA / Content Credentials"
        case "iTXt", "tEXt", "zTXt": return "XMP / AI generation data"
        case "dSIG": return "Digital signature"
        default: return "PNG \(type) AI metadata"
        }
    }

    private static func webPName(_ fourCC: String) -> String {
        switch fourCC {
        case "C2PA": return "C2PA / Content Credentials"
        case "XMP ": return "XMP / AI generation data"
        default: return "WebP \(fourCC) AI metadata"
        }
    }

    private static func labelsRemoved(from report: ProvenanceReport,
                                      preset: CleanPreset) -> [String] {
        let labels = report.carriers + report.findings.map(\.title)
        let lowerMarkers: [String]
        switch preset {
        case .gps: lowerMarkers = ["gps", "location", "iso6709", "xyz"]
        case .exif: lowerMarkers = ["exif", "tiff", "maker", "camera", "lens"]
        case .aiMetadata: lowerMarkers = aiMarkers
        case .allMetadata: lowerMarkers = []
        }
        let filtered = labels.filter { label in
            let lower = label.lowercased()
            return lowerMarkers.contains { lower.contains($0) }
        }
        if !filtered.isEmpty { return MetadataStripper.dedupe(filtered) }
        return [preset.title]
    }
}
