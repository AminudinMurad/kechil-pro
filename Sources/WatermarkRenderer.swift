import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum WatermarkRendererError: LocalizedError {
    case invalidCanvas
    case emptyText
    case missingLogo
    case contextUnavailable
    case unreadableSource
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .invalidCanvas: return "The watermark canvas is invalid"
        case .emptyText: return "Enter watermark text before applying"
        case .missingLogo: return "Choose a logo before applying the watermark"
        case .contextUnavailable: return "The watermark could not be rendered"
        case .unreadableSource: return "The preview image could not be decoded"
        case .renderFailed: return "The preview image could not be rendered"
        }
    }
}

enum WatermarkRenderer {
    private static let previewContext = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false,
    ])

    static func preview(sourceData: Data, configuration: WatermarkConfiguration,
                        logoData: Data?, maximumSide: CGFloat = 1400) throws -> CGImage {
        guard var image = CIImage(data: sourceData, options: [.applyOrientationProperty: true]) else {
            throw WatermarkRendererError.unreadableSource
        }
        let longest = max(image.extent.width, image.extent.height)
        if longest > maximumSide {
            let scale = maximumSide / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let extent = image.extent.integral
        image = image.transformed(by: CGAffineTransform(translationX: -extent.minX,
                                                        y: -extent.minY))
        let bounds = image.extent.integral
        guard let base = previewContext.createCGImage(image, from: bounds,
                    format: .RGBA8,
                    colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!) else {
            throw WatermarkRendererError.renderFailed
        }
        return try apply(configuration: configuration, logoData: logoData, to: base)
    }

    static func renderOverlay(configuration: WatermarkConfiguration, canvasSize: CGSize,
                              logo: CGImage?) throws -> CGImage {
        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        guard width > 0, height > 0 else { throw WatermarkRendererError.invalidCanvas }
        guard let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colourSpace,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                        CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw WatermarkRendererError.contextUnavailable
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        let shortest = min(canvasSize.width, canvasSize.height)
        let scale = max(1, shortest * CGFloat(configuration.scalePercentOfShortestEdge / 100))
        let mark: Mark
        switch configuration.source {
        case .text(let rawText):
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw WatermarkRendererError.emptyText }
            let fontSize = max(1, scale * CGFloat(configuration.textPointScale))
            let font = NSFont(name: configuration.textFontName, size: fontSize) ??
                NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            let colour = NSColor(srgbRed: configuration.textColor.red,
                                 green: configuration.textColor.green,
                                 blue: configuration.textColor.blue,
                                 alpha: configuration.textColor.alpha)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: colour,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            mark = .text(attributed, size: attributed.size())
        case .logo:
            guard let logo else { throw WatermarkRendererError.missingLogo }
            let ratio = CGFloat(logo.width) / CGFloat(max(1, logo.height))
            let size = ratio >= 1 ? CGSize(width: scale, height: scale / ratio)
                                  : CGSize(width: scale * ratio, height: scale)
            mark = .logo(logo, size: size)
        }

        let layout = WatermarkLayoutEngine.layout(canvasSize: canvasSize, markSize: mark.size,
                                                   configuration: configuration)
        for uiCentre in layout.centres {
            let quartzCentre = CGPoint(x: uiCentre.x, y: canvasSize.height - uiCentre.y)
            draw(mark, at: quartzCentre, context: context, configuration: configuration)
        }
        guard let result = context.makeImage() else { throw WatermarkRendererError.contextUnavailable }
        return result
    }

    static func apply(configuration: WatermarkConfiguration, logoData: Data?,
                      to image: CGImage) throws -> CGImage {
        let logo = try logoData.map(decodeLogo)
        let size = CGSize(width: image.width, height: image.height)
        let overlay = try renderOverlay(configuration: configuration, canvasSize: size, logo: logo)
        let colourSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: colourSpace,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                        CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw WatermarkRendererError.contextUnavailable
        }
        let rect = CGRect(origin: .zero, size: size)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        drawOverlay(overlay, into: context, at: rect)
        guard let output = context.makeImage() else { throw WatermarkRendererError.contextUnavailable }
        return output
    }

    static func drawOverlay(_ overlay: CGImage, into context: CGContext, at canvasRect: CGRect) {
        context.draw(overlay, in: canvasRect)
    }

    static func decodeLogo(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw WatermarkRendererError.missingLogo
        }
        return image
    }

    private enum Mark {
        case text(NSAttributedString, size: CGSize)
        case logo(CGImage, size: CGSize)

        var size: CGSize {
            switch self {
            case .text(_, let size), .logo(_, let size): return size
            }
        }
    }

    private static func draw(_ mark: Mark, at centre: CGPoint, context: CGContext,
                             configuration: WatermarkConfiguration) {
        context.saveGState()
        context.setAlpha(CGFloat(max(0, min(1, configuration.opacity))))
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: CGFloat(configuration.rotationDegrees * .pi / 180))
        let rect = CGRect(x: -mark.size.width / 2, y: -mark.size.height / 2,
                          width: mark.size.width, height: mark.size.height)
        switch mark {
        case .logo(let image, _):
            context.draw(image, in: rect)
        case .text(let text, _):
            if configuration.shadowEnabled {
                context.setShadow(offset: CGSize(width: 0, height: -max(1, mark.size.height * 0.025)),
                                  blur: max(1, mark.size.height * 0.055),
                                  color: NSColor.black.withAlphaComponent(
                                    max(0, min(1, configuration.shadowOpacity))).cgColor)
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            text.draw(at: rect.origin)
            NSGraphicsContext.restoreGraphicsState()
        }
        context.restoreGState()
    }
}
