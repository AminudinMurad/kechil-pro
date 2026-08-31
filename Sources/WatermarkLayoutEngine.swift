import CoreGraphics
import Foundation

enum WatermarkKind: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case text = "Text"
    case logo = "Logo"
    var id: String { rawValue }
}

enum WatermarkDefaults {
    static let rotationDegrees = 0.0
    static let textAppearance = WatermarkAppearance(opacity: 0.45, rotation: 0,
        scalePercent: 8, position: .bottomRight, marginPercent: 2.5)
    static let logoAppearance = WatermarkAppearance(opacity: 0.90, rotation: 0,
        scalePercent: 40, position: .centre, marginPercent: 2.5)
}

struct WatermarkAppearance: Equatable, Sendable {
    var opacity: Double
    var rotation: Double
    var scalePercent: Double
    var position: WatermarkPosition
    var marginPercent: Double
}

/// Session-only settings per kind. Switching back restores edits; saved presets
/// still take precedence when explicitly applied. Never stores logo bytes or paths.
struct WatermarkAppearanceProfiles {
    private var text = WatermarkDefaults.textAppearance
    private var logo = WatermarkDefaults.logoAppearance

    mutating func switching(from previous: WatermarkKind, to next: WatermarkKind,
                            current: WatermarkAppearance) -> WatermarkAppearance {
        if previous == .text { text = current } else { logo = current }
        return next == .text ? text : logo
    }
}

enum WatermarkPosition: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case topLeft = "Top left"
    case top = "Top"
    case topRight = "Top right"
    case left = "Left"
    case centre = "Centre"
    case right = "Right"
    case bottomLeft = "Bottom left"
    case bottom = "Bottom"
    case bottomRight = "Bottom right"
    var id: String { rawValue }
}

struct RGBAColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
}

enum WatermarkSource: Codable, Equatable, Sendable {
    case text(String)
    case logo
}

struct WatermarkConfiguration: Codable, Equatable, Sendable {
    var source: WatermarkSource
    var textFontName: String = ".AppleSystemUIFontSemibold"
    var textPointScale = 1.0
    var textColor = RGBAColor.white
    var opacity = 0.45
    var rotationDegrees = WatermarkDefaults.rotationDegrees
    var scalePercentOfShortestEdge = 8.0
    var anchor: WatermarkPosition = .bottomRight
    var marginPercent = 2.5
    var tiled = false
    var tileGapPercent = 6.5
    var shadowEnabled = true
    var shadowOpacity = 0.45
}

struct WatermarkLayout: Equatable, Sendable {
    /// Bounds and centres are expressed in top-left UI coordinates.
    let markSize: CGSize
    let centres: [CGPoint]
    let margin: CGFloat
    let rotatedBounds: CGSize
    let mayClip: Bool
}

enum WatermarkLayoutEngine {
    static func layout(canvasSize: CGSize, markSize: CGSize,
                       configuration: WatermarkConfiguration) -> WatermarkLayout {
        let canvas = CGSize(width: max(1, canvasSize.width), height: max(1, canvasSize.height))
        let margin = max(2, min(canvas.width, canvas.height) *
                         CGFloat(max(0, configuration.marginPercent) / 100))
        let rotated = rotatedBounds(size: markSize, degrees: configuration.rotationDegrees)
        let centre = anchoredCentre(size: rotated, canvas: canvas, margin: margin,
                                    position: configuration.anchor)
        let centres: [CGPoint]
        if configuration.tiled {
            let gap = max(12, max(rotated.width, rotated.height) +
                          min(canvas.width, canvas.height) *
                          CGFloat(max(0, configuration.tileGapPercent) / 100))
            let columns = Int(ceil(canvas.width / gap)) + 2
            let rows = Int(ceil(canvas.height / gap)) + 2
            centres = (-1...rows).flatMap { row in
                (-1...columns).map { column in
                    CGPoint(x: CGFloat(column) * gap + (row.isMultiple(of: 2) ? 0 : gap / 2),
                            y: CGFloat(row) * gap)
                }
            }
        } else {
            centres = [centre]
        }
        let mayClip = rotated.width + 2 * margin > canvas.width ||
            rotated.height + 2 * margin > canvas.height
        return WatermarkLayout(markSize: markSize, centres: centres, margin: margin,
                               rotatedBounds: rotated, mayClip: mayClip)
    }

    static func anchoredCentre(size: CGSize, canvas: CGSize, margin: CGFloat,
                               position: WatermarkPosition) -> CGPoint {
        let halfWidth = min(size.width / 2, max(0, canvas.width / 2 - margin))
        let halfHeight = min(size.height / 2, max(0, canvas.height / 2 - margin))
        let left = margin + halfWidth
        let right = canvas.width - margin - halfWidth
        let top = margin + halfHeight
        let bottom = canvas.height - margin - halfHeight
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

    static func rotatedBounds(size: CGSize, degrees: Double) -> CGSize {
        let radians = CGFloat(degrees * .pi / 180)
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))
        return CGSize(width: size.width * cosine + size.height * sine,
                      height: size.width * sine + size.height * cosine)
    }
}
