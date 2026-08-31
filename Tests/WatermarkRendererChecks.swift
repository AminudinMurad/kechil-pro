import CoreGraphics
import Foundation

@main
enum WatermarkRendererChecks {
    static func main() {
        let canvas = CGSize(width: 1000, height: 600)
        let mark = CGSize(width: 200, height: 60)
        let defaults = WatermarkConfiguration(source: .text("Kechil"))
        expect(defaults.rotationDegrees == WatermarkDefaults.rotationDegrees,
               "watermark defaults to zero rotation")
        let logo = WatermarkDefaults.logoAppearance
        expect(logo.opacity == 0.9 && logo.rotation == 0 && logo.scalePercent == 40 &&
               logo.position == .centre && logo.marginPercent == 2.5,
               "logo appearance matches the requested 90%, 0 degrees, 40%, centre and 2.5%")
        var profiles = WatermarkAppearanceProfiles()
        var textEdits = WatermarkDefaults.textAppearance
        textEdits.opacity = 0.60
        expect(profiles.switching(from: .text, to: .logo, current: textEdits) == logo,
               "first logo use gets its own defaults, not text adjustments")
        var logoEdits = logo
        logoEdits.scalePercent = 25
        expect(profiles.switching(from: .logo, to: .text, current: logoEdits) == textEdits,
               "switching back to text restores text adjustments")
        expect(profiles.switching(from: .text, to: .logo, current: textEdits) == logoEdits,
               "switching back to logo preserves customized logo settings")
        var configuration = WatermarkConfiguration(source: .text("Kechil"),
                                                   rotationDegrees: 0,
                                                   anchor: .topLeft)
        let topLeft = WatermarkLayoutEngine.layout(canvasSize: canvas, markSize: mark,
                                                    configuration: configuration)
        expect(topLeft.centres.count == 1, "single watermark has one centre")
        expect(topLeft.centres[0].x < canvas.width / 2 && topLeft.centres[0].y < canvas.height / 2,
               "top-left anchor uses top-left UI coordinates")

        configuration.anchor = .bottomRight
        let bottomRight = WatermarkLayoutEngine.layout(canvasSize: canvas, markSize: mark,
                                                        configuration: configuration)
        expect(bottomRight.centres[0].x > canvas.width / 2 &&
               bottomRight.centres[0].y > canvas.height / 2,
               "bottom-right anchor remains in its named quadrant")

        configuration.rotationDegrees = 90
        let rotated = WatermarkLayoutEngine.layout(canvasSize: canvas, markSize: mark,
                                                    configuration: configuration)
        expect(close(rotated.rotatedBounds.width, mark.height) &&
               close(rotated.rotatedBounds.height, mark.width),
               "90-degree rotation swaps the layout bounds")

        configuration.tiled = true
        configuration.rotationDegrees = -30
        let tiledA = WatermarkLayoutEngine.layout(canvasSize: canvas, markSize: mark,
                                                  configuration: configuration)
        let tiledB = WatermarkLayoutEngine.layout(canvasSize: canvas, markSize: mark,
                                                  configuration: configuration)
        expect(tiledA.centres.count > 4, "tiled watermark spans the canvas")
        expect(tiledA == tiledB, "tile phase is deterministic")

        let encoded = try! JSONEncoder().encode(configuration)
        let decoded = try! JSONDecoder().decode(WatermarkConfiguration.self, from: encoded)
        expect(decoded == configuration, "watermark configuration round-trips through Codable")
        print("Watermark layout checks passed")
    }

    private static func close(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
