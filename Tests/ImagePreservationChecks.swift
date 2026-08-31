import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
enum ImagePreservationChecks {
    static var failures = 0
    static var assertions = 0

    static func main() throws {
        for orientation in 1...8 {
            let input = try fixture(type: UTType.jpeg.identifier, orientation: orientation)
            let output = try MetadataStripper.strip(input)
            check(orientationOf(input) == orientation, "JPEG fixture orientation \(orientation)")
            check(orientationOf(output.data) == orientation, "JPEG preserves orientation \(orientation)")
            check(pixels(input) == pixels(output.data), "JPEG \(orientation) encoded image is not recompressed")
            check(profile(input) == profile(output.data), "JPEG \(orientation) colour profile is retained")
            check(!hasCameraOrGPS(output.data), "JPEG \(orientation) identifying camera/GPS fields removed")
        }
        for orientation in 2...8 {
            let input = try fixture(type: UTType.png.identifier, orientation: orientation)
            let output = try MetadataStripper.strip(input)
            check(orientationOf(output.data) == orientation, "PNG preserves orientation \(orientation)")
            check(pixels(input) == pixels(output.data), "PNG \(orientation) samples are unchanged")
            check(!hasCameraOrGPS(output.data), "PNG \(orientation) camera/GPS removed")
        }
        for type in [UTType.gif.identifier, UTType.tiff.identifier] {
            let input = try fixture(type: type, orientation: 1, frames: 2)
            check(frameCount(input) == 2, "\(type) fixture has two frames")
            do {
                let result = try MetadataStripper.strip(input)
                check(result.lossless && frameCount(result.data) == 2,
                      "\(type) never silently reencodes or flattens frames")
                check(pixels(input, index: 0) == pixels(result.data, index: 0) &&
                      pixels(input, index: 1) == pixels(result.data, index: 1),
                      "\(type) keeps both frames intact")
            } catch {
                check(error.localizedDescription.lowercased().contains("without re-encoding") ||
                      error.localizedDescription.lowercased().contains("multi-frame"),
                      "\(type) explicitly reports preservation limitation")
            }
        }
        let heic = try fixture(type: UTType.heic.identifier, orientation: 6)
        do {
            let result = try MetadataStripper.strip(heic)
            check(result.lossless, "HEIC never silently reencodes")
            check(orientationOf(heic) == orientationOf(result.data), "HEIC preserves orientation")
            check(pixels(heic) == pixels(result.data), "HEIC copy preserves decoded samples")
            check(profile(heic) == profile(result.data), "HEIC copy preserves colour profile")
            check(!hasCameraOrGPS(result.data), "HEIC camera/GPS metadata is removed")
        } catch {
            print("HEIC preservation limitation: \(error.localizedDescription)")
            check(error.localizedDescription.lowercased().contains("without re-encoding"),
                  "HEIC explicitly reports metadata-only limitation")
        }
        print("Image preservation checks: \(assertions - failures)/\(assertions) passed")
        if failures != 0 { exit(1) }
    }

    static func fixture(type: String, orientation: Int, frames: Int = 1) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type as CFString, frames, nil) else {
            throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot encode \(type)"])
        }
        if frames > 1 {
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFLoopCount: 3]] as CFDictionary)
        }
        for frame in 0..<frames {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let context = CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 8,
                                    bytesPerRow: 96, space: space,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red: CGFloat(frame) * 0.4, green: 0.3, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
            context.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 6, height: 9))
            let properties: [CFString: Any] = [
                kCGImagePropertyOrientation: orientation,
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Synthetic camera",
                    kCGImagePropertyTIFFModel: "Preservation fixture", kCGImagePropertyTIFFOrientation: orientation],
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:08:31 12:00:00"],
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 0.0,
                    kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 0.0,
                    kCGImagePropertyGPSLongitudeRef: "E"],
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2 + Double(frame) * 0.1],
                kCGImageDestinationLossyCompressionQuality: 0.85
            ]
            CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "Fixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not finish \(type)"])
        }
        return output as Data
    }

    static func source(_ data: Data) -> CGImageSource { CGImageSourceCreateWithData(data as CFData, nil)! }
    static func frameCount(_ data: Data) -> Int { CGImageSourceGetCount(source(data)) }
    static func properties(_ data: Data) -> [CFString: Any] {
        CGImageSourceCopyPropertiesAtIndex(source(data), 0, nil) as? [CFString: Any] ?? [:]
    }
    static func orientationOf(_ data: Data) -> Int { (properties(data)[kCGImagePropertyOrientation] as? Int) ?? 1 }
    static func hasCameraOrGPS(_ data: Data) -> Bool {
        let props = properties(data)
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        return tiff[kCGImagePropertyTIFFMake] != nil || tiff[kCGImagePropertyTIFFModel] != nil ||
            props[kCGImagePropertyGPSDictionary] != nil
    }
    static func pixels(_ data: Data, index: Int = 0) -> Data? {
        guard index < frameCount(data), let image = CGImageSourceCreateImageAtIndex(source(data), index, nil),
              let bytes = image.dataProvider?.data else { return nil }
        return bytes as Data
    }
    static func profile(_ data: Data) -> Data? {
        guard let image = CGImageSourceCreateImageAtIndex(source(data), 0, nil),
              let bytes = image.colorSpace?.copyICCData() else { return nil }
        return bytes as Data
    }
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        assertions += 1
        if condition() { print("PASS: \(name)") } else { failures += 1; print("FAIL: \(name)") }
    }
}
