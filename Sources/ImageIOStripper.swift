import Foundation
import ImageIO
import CoreGraphics

// Fallback path for containers we do not parse by hand: HEIC/HEIF, TIFF, AVIF,
// GIF, BMP, and anything else ImageIO recognises.
//
// `CGImageDestinationCopyImageSource` copies the encoded image *without*
// re-encoding it, and applies a small set of property edits along the way.
// Setting a metadata dictionary to `kCFNull` deletes it. This keeps the HEIC
// path lossless too, which matters because iPhone photos are HEIC and are the
// single most common source of embedded GPS coordinates.
extension MetadataStripper {

    static func stripViaImageIO(_ data: Data) throws -> StripResult {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw StripError.unreadable("unrecognised image format")
        }
        guard let uti = CGImageSourceGetType(source) else {
            throw StripError.unreadable("could not determine image type")
        }

        // Record what was actually present, so the UI reports real findings
        // rather than a generic "metadata removed".
        let removed = presentMetadata(in: source)

        let output = NSMutableData()
        let frameCount = max(1, CGImageSourceGetCount(source))
        guard let dest = CGImageDestinationCreateWithData(output, uti, frameCount, nil) else {
            throw StripError.unreadable("no encoder available for this format")
        }

        // `kCFNull` is imported as an implicitly unwrapped optional. Unwrap it once
        // through an explicitly typed local: putting the IUO straight into an
        // `[CFString: Any]` literal boxes an `Optional`, which ImageIO does not
        // recognise as the delete marker.
        let delete: CFNull = kCFNull

        let deletions: [CFString: Any] = [
            kCGImagePropertyExifDictionary:        delete,
            kCGImagePropertyExifAuxDictionary:     delete,
            kCGImagePropertyGPSDictionary:         delete,
            kCGImagePropertyIPTCDictionary:        delete,
            kCGImagePropertyTIFFDictionary:        delete,
            kCGImagePropertyMakerAppleDictionary:  delete,
        ]

        var cfError: Unmanaged<CFError>?
        let ok = CGImageDestinationCopyImageSource(dest, source, deletions as CFDictionary, &cfError)

        if ok, output.length > 0 {
            var copied = output as Data
            let neutralized = neutralizeC2PABMFFBoxes(in: copied)
            copied = neutralized.data
            var reported = removed
            if neutralized.count > 0 { reported.append("C2PA / Content Credentials") }

            // Prove the edit on its own output. If an unhandled XMP/C2PA carrier still
            // survives, use the decode/re-encode path and say so rather than returning a
            // green false-clean result.
            let verification = ProvenanceProbe.inspect(copied)
            if verification.hasDetectedMetadata,
               let reencoded = reencodeStrippingAll(source: source, uti: uti) {
                let scrubbed = neutralizeC2PABMFFBoxes(in: reencoded)
                let finalReport = ProvenanceProbe.inspect(scrubbed.data)
                if !finalReport.hasDetectedMetadata {
                    if reported.isEmpty { reported.append("All metadata") }
                    return StripResult(data: scrubbed.data,
                                       removed: MetadataStripper.dedupe(reported),
                                       format: .other,
                                       lossless: false)
                }
            }

            return StripResult(data: copied,
                               removed: MetadataStripper.dedupe(reported),
                               format: .other,
                               lossless: true)
        }

        // Some formats (notably animated GIF) refuse CopyImageSource. Fall back to
        // a full re-encode, which drops every metadata block but does touch pixels.
        // Flagged as lossless: false so the UI can say so honestly.
        if let reencoded = reencodeStrippingAll(source: source, uti: uti) {
            return StripResult(data: reencoded,
                               removed: removed.isEmpty ? ["All metadata"] : removed,
                               format: .other,
                               lossless: false)
        }

        let why = cfError?.takeRetainedValue().localizedDescription ?? "encoder rejected the copy"
        throw StripError.unreadable(why)
    }

    /// Inspects which metadata dictionaries the source actually carries.
    private static func presentMetadata(in source: CGImageSource) -> [String] {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return []
        }
        var found: [String] = []
        if props[kCGImagePropertyGPSDictionary] != nil        { found.append("GPS location") }
        if props[kCGImagePropertyExifDictionary] != nil       { found.append("EXIF") }
        if props[kCGImagePropertyExifAuxDictionary] != nil    { found.append("EXIF aux / lens") }
        if props[kCGImagePropertyIPTCDictionary] != nil       { found.append("IPTC") }
        if props[kCGImagePropertyTIFFDictionary] != nil       { found.append("TIFF / camera") }
        if props[kCGImagePropertyMakerAppleDictionary] != nil { found.append("Apple maker notes") }
        return found
    }

    private static func reencodeStrippingAll(source: CGImageSource, uti: CFString) -> Data? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, uti, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: 1.0
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest), out.length > 0 else { return nil }
        return out as Data
    }

}

// Keep the existing helper used by provenance checks and the ImageIO fallback;
// the implementation itself is shared with video Clean.
extension MetadataStripper {
    static func neutralizeC2PABMFFBoxes(in data: Data) -> (data: Data, count: Int) {
        MediaContainerSanitizer.neutralizeC2PABMFFBoxes(in: data)
    }
}
