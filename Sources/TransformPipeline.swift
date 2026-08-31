import Foundation
import AppKit
import CoreGraphics
import CoreImage
import ImageIO

enum CropAspect: String, CaseIterable, Identifiable {
    case original = "No crop"
    case custom = "Custom size"
    case square = "1:1"
    case portrait = "4:5"
    case widescreen = "16:9"
    case story = "9:16"
    case photo = "3:2"

    var id: String { rawValue }
    var ratio: CGFloat? {
        switch self {
        case .original, .custom: return nil
        case .square: return 1
        case .portrait: return 4 / 5
        case .widescreen: return 16 / 9
        case .story: return 9 / 16
        case .photo: return 3 / 2
        }
    }
}

enum ResizeMode: String, CaseIterable, Identifiable {
    case none = "Original size"
    case longEdge = "Long edge"
    case width = "Width"
    case height = "Height"
    case percent = "Percentage"
    var id: String { rawValue }
}

enum ImageOutputFormat: String, CaseIterable, Identifiable {
    case webp = "WebP"
    case jpeg = "JPEG"
    case png = "PNG"
    case heic = "HEIC"
    case avif = "AVIF"
    case tiff = "TIFF"
    case gif = "GIF"

    var id: String { rawValue }
    var fileExtension: String { rawValue.lowercased() }
    var qualityAffectsSize: Bool { self == .webp || self == .jpeg || self == .heic || self == .avif }
    var supportsAlpha: Bool { self == .webp || self == .png || self == .tiff || self == .gif || self == .avif }

    var uti: CFString? {
        switch self {
        case .webp: return nil
        case .jpeg: return "public.jpeg" as CFString
        case .png:  return "public.png" as CFString
        case .heic: return "public.heic" as CFString
        case .avif: return "public.avif" as CFString
        case .tiff: return "public.tiff" as CFString
        case .gif:  return "com.compuserve.gif" as CFString
        }
    }
}

struct WatermarkSettings: Equatable, Sendable {
    var kind: WatermarkKind
    var text: String
    var logoData: Data?
    var opacity: Double
    var rotationDegrees: Double
    /// Percentage of the shortest output edge. Text uses it as font size; logo uses it
    /// as its longest rendered edge.
    var scalePercent: Double
    var position: WatermarkPosition
    var tiled: Bool
    var textColor = RGBAColor.white
    var marginPercent = 2.5
    var tileGapPercent = 6.5
    var shadowEnabled = true
    var shadowOpacity = 0.45
}

extension WatermarkSettings {
    var configuration: WatermarkConfiguration {
        WatermarkConfiguration(source: kind == .text ? .text(text) : .logo,
                               textColor: textColor,
                               opacity: opacity,
                               rotationDegrees: rotationDegrees,
                               scalePercentOfShortestEdge: scalePercent,
                               anchor: position,
                               marginPercent: marginPercent,
                               tiled: tiled,
                               tileGapPercent: tileGapPercent,
                               shadowEnabled: shadowEnabled,
                               shadowOpacity: shadowOpacity)
    }
}

struct TransformSettingsSnapshot {
    var cropAspect: CropAspect = .original
    var cropFocusX: Double = 0.5
    var cropFocusY: Double = 0.5
    var cropWidth = 0.0
    var cropHeight = 0.0
    /// Custom crop policy is separate from the post-crop resize upscaling setting.
    var cropUpscalePolicy: ImageCropUpscalePolicy = .keepNative
    var resizeMode: ResizeMode = .none
    var resizeValue: Double = 1600
    /// When disabled, a resize cannot exceed the pixels retained by the crop.
    var allowsUpscaling = ImageResizePolicy.allowsUpscalingByDefault
    var outputFormat: ImageOutputFormat = .webp
    var qualityFloor = 60
    var qualityCeiling = 82
    var targetBytes: Int?
    var webPLossless = false
    var webPMethod = 4
    var watermark: WatermarkSettings?
}

struct TransformOutput {
    let data: Data
    let sourceWidth: Int
    let sourceHeight: Int
    let width: Int
    let height: Int
    let quality: Int
    let targetMet: Bool
    let iterations: Int
    let statusText: String?
}

enum TransformError: LocalizedError {
    case unreadable
    case renderFailed
    case encoderUnavailable(String)
    case encodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Could not decode the image"
        case .renderFailed: return "Could not render the crop or resize"
        case .encoderUnavailable(let format): return "The \(format) encoder is unavailable on this Mac"
        case .encodeFailed(let format): return "Could not encode \(format)"
        }
    }
}

enum TransformPipeline {
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false,
    ])

    static func process(_ sourceData: Data, settings: TransformSettingsSnapshot) throws -> TransformOutput {
        guard var image = CIImage(data: sourceData, options: [.applyOrientationProperty: true]) else {
            throw TransformError.unreadable
        }
        let sourceExtent = image.extent.integral
        image = crop(image, aspect: settings.cropAspect,
                     customWidth: settings.cropWidth, customHeight: settings.cropHeight,
                     focusX: settings.cropFocusX, focusY: settings.cropFocusY,
                     cropUpscalePolicy: settings.cropUpscalePolicy)
        image = resize(image, mode: settings.resizeMode, value: settings.resizeValue,
                       allowsUpscaling: settings.allowsUpscaling)

        let extent = image.extent.integral
        guard extent.width >= 1, extent.height >= 1,
              let rendered = context.createCGImage(image, from: extent,
                                                   format: .RGBA8,
                                                   colorSpace: image.colorSpace ??
                                                    CGColorSpace(name: CGColorSpace.sRGB)!) else {
            throw TransformError.renderFailed
        }

        let finalImage = try applyWatermark(settings.watermark, to: rendered)
        let target = settings.targetBytes
        let result = try SizeTargetEncoder.encode(
            targetBytes: target,
            qualityFloor: settings.qualityFloor,
            qualityCeiling: settings.qualityCeiling,
            qualityAffectsSize: settings.outputFormat.qualityAffectsSize && !settings.webPLossless
        ) { quality in
            let encoded: Data
            if settings.outputFormat == .webp {
                encoded = try encodeWebP(finalImage, quality: quality,
                                         lossless: settings.webPLossless,
                                         method: settings.webPMethod)
            } else {
                encoded = try encodeImageIO(finalImage, format: settings.outputFormat,
                                            quality: quality)
            }
            // Transform tools re-encode by design, but they must not reintroduce the
            // metadata the Clean tool exists to remove.
            return try MetadataStripper.strip(encoded).data
        }

        return TransformOutput(data: result.data,
                               sourceWidth: Int(sourceExtent.width),
                               sourceHeight: Int(sourceExtent.height),
                               width: finalImage.width, height: finalImage.height,
                               quality: result.finalQuality,
                               targetMet: result.targetMet,
                               iterations: result.iterations,
                               statusText: result.statusText)
    }

    private static func crop(_ image: CIImage, aspect: CropAspect,
                             customWidth: Double, customHeight: Double,
                             focusX: Double, focusY: Double,
                             cropUpscalePolicy: ImageCropUpscalePolicy) -> CIImage {
        let source = image.extent
        let customSize = aspect == .custom && customWidth > 0 && customHeight > 0
            ? CGSize(width: customWidth, height: customHeight) : nil
        guard aspect != .original else { return normalizeOrigin(image) }
        let upscale = ImageCropGeometry.cropUpscaleScale(
            source: source.size, customSize: customSize, policy: cropUpscalePolicy)
        let workingImage = upscale > 1
            ? image.transformed(by: CGAffineTransform(scaleX: upscale, y: upscale))
            : image
        // Use the actual scaled coverage, not Core Image's outward-rounded extent.
        let coverage = source.applying(CGAffineTransform(scaleX: upscale, y: upscale))
        var rect = ImageCropGeometry.cropRect(source: coverage,
                                              aspect: aspect.ratio,
                                              customSize: customSize,
                                              focusX: focusX, focusY: focusY)
        if aspect == .custom, customSize != nil {
            // Align before cropping. Fractional crop -> normalize -> recrop looks
            // exact until Core Image fuses a later resize and loses a border pixel.
            // A single pixel-aligned crop stays stable through both transforms.
            rect.origin.x = max(coverage.minX.rounded(.up),
                min(rect.minX.rounded(), (coverage.maxX - rect.width + 0.000001).rounded(.down)))
            rect.origin.y = max(coverage.minY.rounded(.up),
                min(rect.minY.rounded(), (coverage.maxY - rect.height + 0.000001).rounded(.down)))
        }
        return normalizeOrigin(workingImage.cropped(to: rect))
    }

    private static func resize(_ image: CIImage, mode: ResizeMode, value: Double,
                               allowsUpscaling: Bool) -> CIImage {
        guard mode != .none, value > 0 else { return image }
        let size = image.extent.size
        let scale: CGFloat
        switch mode {
        case .none: return image
        case .longEdge: scale = CGFloat(value) / max(size.width, size.height)
        case .width: scale = CGFloat(value) / size.width
        case .height: scale = CGFloat(value) / size.height
        case .percent: scale = CGFloat(value / 100)
        }
        let finalScale = ImageResizePolicy.finalScale(requested: scale,
                                                       allowsUpscaling: allowsUpscaling)
        guard abs(finalScale - 1) > 0.0001 else { return image }
        return image.transformed(by: CGAffineTransform(scaleX: finalScale, y: finalScale))
    }

    private static func normalizeOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX,
                                                y: -image.extent.minY))
    }

    private static func applyWatermark(_ settings: WatermarkSettings?, to image: CGImage) throws -> CGImage {
        guard let settings else { return image }
        return try WatermarkRenderer.apply(configuration: settings.configuration,
                                           logoData: settings.logoData, to: image)
        /* Legacy implementation retained below during migration. It is unreachable;
           export and preview now use WatermarkRenderer as their one drawing path. */
#if false
        let shortest = CGFloat(min(image.width, image.height))
        let scale = max(0.01, CGFloat(settings.scalePercent) / 100) * shortest
        guard scale >= 1 else { return image }

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
            CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw TransformError.renderFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let mark: WatermarkMark
        switch settings.kind {
        case .text:
            let text = settings.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return image }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: scale, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let size = attributed.size()
            mark = .text(attributed, size: size)
        case .logo:
            guard let data = settings.logoData,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return image }
            let ratio = CGFloat(logo.width) / CGFloat(max(1, logo.height))
            let size = ratio >= 1 ? CGSize(width: scale, height: scale / ratio)
                                  : CGSize(width: scale * ratio, height: scale)
            mark = .logo(logo, size: size)
        }

        let canvas = CGSize(width: image.width, height: image.height)
        if settings.tiled {
            let gap = max(20, max(mark.size.width, mark.size.height) * 0.65)
            let columns = Int(ceil(canvas.width / gap)) + 2
            let rows = Int(ceil(canvas.height / gap)) + 2
            for row in -1...rows {
                for column in -1...columns {
                    let centre = CGPoint(x: CGFloat(column) * gap + (row.isMultiple(of: 2) ? 0 : gap / 2),
                                         y: CGFloat(row) * gap)
                    draw(mark, at: centre, in: context, opacity: settings.opacity,
                         rotationDegrees: settings.rotationDegrees)
                }
            }
        } else {
            draw(mark, at: anchoredCentre(for: mark.size, in: canvas, position: settings.position),
                 in: context, opacity: settings.opacity, rotationDegrees: settings.rotationDegrees)
        }

        guard let output = context.makeImage() else { throw TransformError.renderFailed }
        return output
#endif
    }

    private enum WatermarkMark {
        case text(NSAttributedString, size: CGSize)
        case logo(CGImage, size: CGSize)

        var size: CGSize {
            switch self {
            case .text(_, let size), .logo(_, let size): return size
            }
        }
    }

    private static func draw(_ mark: WatermarkMark, at centre: CGPoint, in context: CGContext,
                             opacity: Double, rotationDegrees: Double) {
        context.saveGState()
        context.setAlpha(CGFloat(max(0, min(1, opacity))))
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: CGFloat(rotationDegrees * .pi / 180))
        let rect = CGRect(x: -mark.size.width / 2, y: -mark.size.height / 2,
                          width: mark.size.width, height: mark.size.height)
        switch mark {
        case .logo(let image, _):
            context.draw(image, in: rect)
        case .text(let text, _):
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            text.draw(at: rect.origin)
            NSGraphicsContext.restoreGraphicsState()
        }
        context.restoreGState()
    }

    private static func anchoredCentre(for size: CGSize, in canvas: CGSize,
                                      position: WatermarkPosition) -> CGPoint {
        let margin = max(12, min(canvas.width, canvas.height) * 0.025)
        let left = margin + size.width / 2
        let right = canvas.width - margin - size.width / 2
        let bottom = margin + size.height / 2
        let top = canvas.height - margin - size.height / 2
        switch position {
        case .topLeft: return CGPoint(x: left, y: top)
        case .top: return CGPoint(x: canvas.width / 2, y: top)
        case .topRight: return CGPoint(x: right, y: top)
        case .left: return CGPoint(x: left, y: canvas.height / 2)
        case .centre: return CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        case .right: return CGPoint(x: right, y: canvas.height / 2)
        case .bottomLeft: return CGPoint(x: left, y: bottom)
        case .bottom: return CGPoint(x: canvas.width / 2, y: bottom)
        case .bottomRight: return CGPoint(x: right, y: bottom)
        }
    }

    private static func encodeImageIO(_ image: CGImage, format: ImageOutputFormat,
                                      quality: Int) throws -> Data {
        guard let uti = format.uti else { throw TransformError.encoderUnavailable(format.rawValue) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, uti, 1, nil) else {
            throw TransformError.encoderUnavailable(format.rawValue)
        }
        var properties: [CFString: Any] = [:]
        if format.qualityAffectsSize {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 100
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length > 0 else {
            throw TransformError.encodeFailed(format.rawValue)
        }
        return output as Data
    }

    private static func encodeWebP(_ image: CGImage, quality: Int,
                                   lossless: Bool, method: Int) throws -> Data {
        let width = image.width
        let height = image.height
        let rowBytes = width * 4
        var rgba = [UInt8](repeating: 0, count: rowBytes * height)
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
            CGImageAlphaInfo.premultipliedLast.rawValue

        let drew = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: rowBytes,
                                          space: colorSpace, bitmapInfo: bitmapInfo) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { throw TransformError.renderFailed }

        // Core Graphics rendered premultiplied RGBA; libwebp's ImportRGBA expects
        // straight alpha. Undo premultiplication so translucent logos keep their colour.
        for index in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = Int(rgba[index + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0..<3 {
                rgba[index + channel] = UInt8(min(255, Int(rgba[index + channel]) * 255 / alpha))
            }
        }

        var output: UnsafeMutablePointer<UInt8>?
        var outputSize = 0
        let ok = rgba.withUnsafeBytes { buffer in
            KechilWebPEncodeRGBA(buffer.bindMemory(to: UInt8.self).baseAddress,
                                 Int32(width), Int32(height), Int32(rowBytes),
                                 Float(quality), lossless ? 1 : 0, Int32(method),
                                 &output, &outputSize)
        }
        guard ok != 0, let output, outputSize > 0 else {
            throw TransformError.encodeFailed("WebP")
        }
        defer { KechilWebPFree(output) }
        return Data(bytes: output, count: outputSize)
    }
}
