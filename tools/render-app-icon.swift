import AppKit
import Foundation

// Renders the Kechil PRO app icon: a solid ink photo card holding a sun and two
// peaks, with a blue spark straddling its top-right corner, on the same light
// squircle tile and vivid green family accent as Klik PRO.
//
// Two deliberate choices, both about legibility at 16 and 32 points, where this icon
// spends most of its life (Finder list, Dock, About box):
//
//   * The photo is a FILLED dark card with light shapes knocked out of it, not an
//     outlined frame. A 26pt stroke on a 1024pt canvas is 0.8px at 32pt — it renders
//     as a faint grey hairline. Solid mass survives the downscale; strokes do not.
//   * The spark carries a tile-coloured halo before its blue fill. Blue #2F6BFF on
//     ink #0C1424 is only about 4.1:1, so on the dark card the shape would mush into
//     it. The halo is what separates them, and it reads as intentional at full size.

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render-app-icon <icon-master.png>\n", stderr)
    exit(64)
}
let destinationPath = CommandLine.arguments[1]

let S = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let ns = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("Unable to allocate bitmap\n", stderr)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ns
let cg = ns.cgContext   // bottom-left origin

func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}
// top-left rect helper (y measured from the top)
func TL(_ x: CGFloat, _ yTop: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: CGFloat(S) - yTop - h, width: w, height: h)
}

// Family tokens shared with Klik PRO. Green anchors the product family while the
// blue sparkle remains Kechil's distinct image-cleanup cue.
let ink = NSColor(srgbRed: 0x0C / 255, green: 0x14 / 255, blue: 0x24 / 255, alpha: 1).cgColor
let familyGreen = NSColor(srgbRed: 25 / 255, green: 187 / 255, blue: 19 / 255, alpha: 1).cgColor
let sparkleBlue = NSColor(srgbRed: 0x2F / 255, green: 0x6B / 255, blue: 0xFF / 255, alpha: 1).cgColor
let tileLight = NSColor(white: 0.985, alpha: 1).cgColor

// ------------------------------------------------------------------ squircle tile
cg.saveGState()
cg.addPath(rr(CGRect(x: 100, y: 100, width: 824, height: 824), 188))
cg.clip()
let grad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [tileLight, NSColor(white: 0.93, alpha: 1).cgColor] as CFArray,
    locations: [0, 1]
)!
cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
cg.restoreGState()

// -------------------------------------------------------------------- photo card
let card = TL(196, 230, 632, 470)          // x 196…828, y 324…794
let cardRadius: CGFloat = 60
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 30,
             color: NSColor(white: 0, alpha: 0.20).cgColor)
cg.addPath(rr(card, cardRadius))
cg.setFillColor(ink)
cg.fillPath()
cg.restoreGState()

// The knocked-out content sits inside a uniform inset, so the ink left around it
// reads as the frame's border rather than as a stroke that has to survive scaling.
let border: CGFloat = 40
let inner = card.insetBy(dx: border, dy: border)
let innerRadius = cardRadius - border * 0.62

cg.saveGState()
cg.addPath(rr(inner, innerRadius))
cg.clip()
cg.setFillColor(tileLight)

// Sun, upper-left of the content. Sits clear of the left peak's slope.
let sunRadius: CGFloat = 54
let sunCentre = CGPoint(x: inner.minX + inner.width * 0.21,
                        y: inner.minY + inner.height * 0.78)
cg.fillEllipse(in: CGRect(x: sunCentre.x - sunRadius, y: sunCentre.y - sunRadius,
                          width: sunRadius * 2, height: sunRadius * 2))

// Rear peak: filled rather than stroked so it remains legible at 16pt.
let rearPeak = CGMutablePath()
rearPeak.move(to: CGPoint(x: inner.minX - 30, y: inner.minY - 10))
rearPeak.addLine(to: CGPoint(x: inner.minX + inner.width * 0.36,
                             y: inner.minY + inner.height * 0.60))
rearPeak.addLine(to: CGPoint(x: inner.minX + inner.width * 0.58,
                             y: inner.minY - 10))
rearPeak.closeSubpath()
cg.addPath(rearPeak)
cg.fillPath()

// The green foreground ridge carries the Klik PRO family colour as a substantial
// shape, rather than a decorative speck that disappears in Finder list views.
let foregroundPeak = CGMutablePath()
foregroundPeak.move(to: CGPoint(x: inner.minX + inner.width * 0.30,
                                y: inner.minY - 10))
foregroundPeak.addLine(to: CGPoint(x: inner.minX + inner.width * 0.545,
                                   y: inner.minY + inner.height * 0.365))
foregroundPeak.addLine(to: CGPoint(x: inner.minX + inner.width * 0.735,
                                   y: inner.minY + inner.height * 0.80))
foregroundPeak.addLine(to: CGPoint(x: inner.maxX + 30, y: inner.minY - 10))
foregroundPeak.closeSubpath()
cg.setFillColor(familyGreen)
cg.addPath(foregroundPeak)
cg.fillPath()
cg.restoreGState()

// -------------------------------------------------------------------------- spark
/// A four-point sparkle centred on `c`. Concave arms via one quadratic per quadrant,
/// with the vertical axis longer than the horizontal — the proportion that reads as
/// "sparkle" rather than "plus sign".
func sparkle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    let rv = r, rh = r * 0.74, k = r * 0.20
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + rv))
    p.addQuadCurve(to: CGPoint(x: c.x + rh, y: c.y), control: CGPoint(x: c.x + k, y: c.y + k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - rv), control: CGPoint(x: c.x + k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x - rh, y: c.y), control: CGPoint(x: c.x - k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + rv), control: CGPoint(x: c.x - k, y: c.y + k))
    p.closeSubpath()
    return p
}

let sparkCentre = CGPoint(x: card.maxX - 34, y: card.maxY - 30)
let sparkRadius: CGFloat = 104
cg.setFillColor(tileLight)
cg.addPath(sparkle(sparkCentre, sparkRadius * 1.20))
cg.fillPath()
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -5), blur: 12,
             color: NSColor(white: 0, alpha: 0.22).cgColor)
cg.setFillColor(sparkleBlue)
cg.addPath(sparkle(sparkCentre, sparkRadius))
cg.fillPath()
cg.restoreGState()

// ---------------------------------------------------------------------- PRO badge
let badge = TL(431, 748, 162, 68)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -4), blur: 9,
             color: NSColor(white: 0, alpha: 0.18).cgColor)
cg.addPath(rr(badge, 20))
cg.setFillColor(familyGreen)
cg.fillPath()
cg.restoreGState()
let pro = "PRO" as NSString
let attr: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 42, weight: .heavy),
    .foregroundColor: NSColor.white,
]
let ts = pro.size(withAttributes: attr)
pro.draw(at: CGPoint(x: badge.midX - ts.width / 2, y: badge.midY - ts.height / 2),
         withAttributes: attr)

NSGraphicsContext.restoreGraphicsState()
guard let out = rep.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode PNG\n", stderr)
    exit(1)
}
try! out.write(to: URL(fileURLWithPath: destinationPath))
