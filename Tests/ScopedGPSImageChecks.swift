import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
enum ScopedGPSImageChecks {
    static func main() throws {
        let fixture = try makeGPSJPEG()
        let inputProperties = try properties(in: fixture)

        require(inputProperties[kCGImagePropertyGPSDictionary] != nil,
                "fixture must carry GPS metadata")
        require(tiffModel(in: inputProperties) == "Kechil Test Camera",
                "fixture must carry unrelated TIFF camera metadata")
        require(exifDate(in: inputProperties) == "2026:08:30 10:48:00",
                "fixture must carry unrelated EXIF capture metadata")

        let result = try MetadataStripper.strip(fixture, preset: .gps)
        let outputProperties = try properties(in: result.data)

        require(outputProperties[kCGImagePropertyGPSDictionary] == nil,
                "Remove GPS must remove the complete GPS dictionary")
        require(tiffModel(in: outputProperties) == "Kechil Test Camera",
                "Remove GPS must preserve TIFF camera metadata")
        require(exifDate(in: outputProperties) == "2026:08:30 10:48:00",
                "Remove GPS must preserve EXIF capture metadata")
        require(decodedPixels(fixture) == decodedPixels(result.data),
                "Remove GPS must not recompress or alter pixels")
        require(result.lossless, "Remove GPS must report a lossless copy")

        do {
            let exifResult = try MetadataStripper.strip(fixture, preset: .exif)
            let exifOutput = try properties(in: exifResult.data)
            require(exifOutput[kCGImagePropertyGPSDictionary] != nil,
                    "Remove EXIF must not remove the separate GPS scope")
            require(tiffModel(in: exifOutput) == nil && exifDate(in: exifOutput) == nil,
                    "Remove EXIF must remove camera and capture fields")
            require(decodedPixels(fixture) == decodedPixels(exifResult.data),
                    "Remove EXIF must not recompress or alter pixels")
            require(exifResult.lossless, "Remove EXIF must report a lossless copy")
        } catch {
            // A format is allowed to refuse scoped EXIF cleanup when ImageIO
            // cannot prove a metadata-only copy. It must fail closed with a
            // user-facing preservation limitation rather than re-encoding.
            let message = error.localizedDescription.lowercased()
            require(message.contains("without re-encoding") ||
                        message.contains("cannot safely clean"),
                    "Remove EXIF must report an explicit preservation limitation")
        }

        if CommandLine.arguments.count > 1 {
            try checkExternalImage(at: CommandLine.arguments[1])
        }

        print("Scoped GPS image checks passed")
    }

    private static func checkExternalImage(at path: String) throws {
        let input = try Data(contentsOf: URL(fileURLWithPath: path))
        let inputProperties = try properties(in: input)
        require(inputProperties[kCGImagePropertyGPSDictionary] != nil,
                "external image must carry GPS metadata")

        let result = try MetadataStripper.strip(input, preset: .gps)
        let outputProperties = try properties(in: result.data)
        require(outputProperties[kCGImagePropertyGPSDictionary] == nil,
                "external image must have no GPS dictionary after Remove GPS")
        require(tiffModel(in: outputProperties) == tiffModel(in: inputProperties),
                "external image camera model must be preserved")
        require(exifDate(in: outputProperties) == exifDate(in: inputProperties),
                "external image capture date must be preserved")
        require(decodedPixels(input) == decodedPixels(result.data),
                "external image pixels must remain identical")
        print("External GPS fixture passed: \(URL(fileURLWithPath: path).lastPathComponent)")
    }

    private static func makeGPSJPEG() throws -> Data {
        let width = 32
        let height = 24
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { raw in
            guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    bytes[offset] = UInt8((x * 7) % 256)
                    bytes[offset + 1] = UInt8((y * 11) % 256)
                    bytes[offset + 2] = UInt8(((x + y) * 5) % 256)
                    bytes[offset + 3] = 255
                }
            }
        }

        let image = pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return context.makeImage()
        }
        guard let image else { throw CheckError("could not create fixture pixels") }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CheckError("could not create JPEG fixture destination") }

        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 3.133758333333333,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 101.5359283333333,
                kCGImagePropertyGPSLongitudeRef: "E",
                kCGImagePropertyGPSAltitude: 52.65,
                kCGImagePropertyGPSAltitudeRef: 0,
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Kechil",
                kCGImagePropertyTIFFModel: "Kechil Test Camera",
                kCGImagePropertyTIFFOrientation: 1,
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:08:30 10:48:00",
                kCGImagePropertyExifFNumber: 1.8,
            ],
            kCGImageDestinationLossyCompressionQuality: 0.86,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length > 0 else {
            throw CheckError("could not encode JPEG fixture")
        }
        return output as Data
    }

    private static func properties(in data: Data) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else {
            throw CheckError("could not read fixture metadata")
        }
        return properties
    }

    private static func tiffModel(in properties: [CFString: Any]) -> String? {
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return tiff?[kCGImagePropertyTIFFModel] as? String
    }

    private static func exifDate(in properties: [CFString: Any]) -> String? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        return exif?[kCGImagePropertyExifDateTimeOriginal] as? String
    }

    private static func decodedPixels(_ data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return Data()
        }
        let stride = image.width * 4
        var pixels = Data(count: stride * image.height)
        pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: stride,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(image, in: CGRect(x: 0, y: 0,
                                           width: image.width, height: image.height))
        }
        return pixels
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fputs("Scoped GPS image check failed: \(message)\n", stderr)
            exit(1)
        }
    }
}

private struct CheckError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
