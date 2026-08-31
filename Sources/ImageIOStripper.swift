import Foundation
import ImageIO
import CoreGraphics

// Metadata-only copying for ImageIO containers. Unsupported copies fail closed;
// Clean never substitutes a re-encoded image or flattens an animation to frame zero.
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

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount == 1 else {
            throw StripError.unsupported("multi-frame/page cleaning is not yet verified without re-encoding; the original is unchanged")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = (properties[kCGImagePropertyOrientation] as? Int) ??
            (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        guard (1...8).contains(orientation) else {
            throw StripError.unsupported("invalid display orientation cannot be preserved without re-encoding")
        }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, uti, frameCount, nil) else {
            throw StripError.unsupported("this format has no supported copy without re-encoding")
        }

        // CopyImageSource takes destination-copy options, not property-dictionary
        // deletion keys. Replace identifying tags and retain display orientation.
        let metadata = CGImageMetadataCreateMutable()
        if orientation != 1 {
            guard CGImageMetadataSetValueMatchingImageProperty(metadata,
                kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation,
                NSNumber(value: orientation)) else {
                throw StripError.unsupported("display orientation cannot be retained without re-encoding")
            }
        }
        let deletions: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeGPS: true,
            kCGImageMetadataShouldExcludeXMP: true,
        ]

        var cfError: Unmanaged<CFError>?
        let ok = CGImageDestinationCopyImageSource(dest, source, deletions as CFDictionary, &cfError)

        if ok, output.length > 0 {
            var copied = output as Data
            let neutralized = neutralizeC2PABMFFBoxes(in: copied)
            copied = neutralized.data
            var reported = removed
            if neutralized.count > 0 { reported.append("C2PA / Content Credentials") }

            // Verify the supported copy; never fall back to re-encoding/flattening.
            let verification = ProvenanceProbe.inspect(copied)
            guard !verification.hasDetectedMetadata else {
                throw StripError.unsupported("some metadata cannot be removed without re-encoding; the original is unchanged")
            }
            guard let copiedSource = CGImageSourceCreateWithData(copied as CFData, nil),
                  CGImageSourceGetType(copiedSource) as String? == uti as String,
                  CGImageSourceGetCount(copiedSource) == frameCount,
                  let after = CGImageSourceCopyPropertiesAtIndex(copiedSource, 0, nil) as? [CFString: Any],
                  sameRenderingProperties(properties, after) else {
                throw StripError.unsupported("image structure/orientation could not be preserved without re-encoding")
            }
            var preserved = ["ImageIO metadata-only copy; no re-encoding"]
            if orientation != 1 { preserved.append("Display orientation (\(orientation))") }
            return StripResult(data: copied,
                               removed: MetadataStripper.dedupe(reported),
                               format: .other,
                               lossless: true, preserved: preserved)
        }

        let why = cfError?.takeRetainedValue().localizedDescription ?? "encoder rejected the copy"
        throw StripError.unsupported("this file cannot be copied without re-encoding (\(why))")
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

    private static func sameRenderingProperties(_ before: [CFString: Any], _ after: [CFString: Any]) -> Bool {
        for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight,
                    kCGImagePropertyDepth, kCGImagePropertyColorModel, kCGImagePropertyProfileName] {
            if before[key].map({ String(describing: $0) }) != after[key].map({ String(describing: $0) }) {
                return false
            }
        }
        let beforeOrientation = (before[kCGImagePropertyOrientation] as? Int) ??
            (before[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let afterOrientation = (after[kCGImagePropertyOrientation] as? Int) ??
            (after[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return beforeOrientation == afterOrientation
    }

}

// Keep the existing helper used by provenance checks and the ImageIO fallback;
// the implementation itself is shared with video Clean.
extension MetadataStripper {
    static func neutralizeC2PABMFFBoxes(in data: Data) -> (data: Data, count: Int) {
        MediaContainerSanitizer.neutralizeC2PABMFFBoxes(in: data)
    }
}
