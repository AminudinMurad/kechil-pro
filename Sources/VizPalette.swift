import SwiftUI
import AppKit

/// Colours for the dashboard's data marks.
///
/// There is no asset catalog in this project (no Xcode project at all), so dark mode is
/// a *selected* second set of values rather than an automatic flip: each token resolves
/// through `NSColor(name:dynamicProvider:)` against the current appearance.
///
/// Every value below was checked with the data-viz palette validator against the
/// surfaces this UI actually renders on — `#ffffff` light and `#1e1e1e` dark, which is
/// `NSColor.textBackgroundColor` in each appearance. Re-run it if any hex changes:
///
///     node scripts/validate_palette.js "#2a78d6" --mode light --surface "#ffffff"
///     node scripts/validate_palette.js "#3987e5" --mode dark  --surface "#1e1e1e"
///
/// Results on record:
///
/// - `series` — all checks PASS in both modes (inside the lightness band, chroma floor
///   clear, ≥3:1 against its surface).
/// - `critical` / `serious` — the fixed status pair, never re-themed per appearance.
///   Separation between them is CVD ΔE 13.9 (deutan) and normal-vision ΔE 15.7, clear of
///   the ≥8 / ≥15 floors. `critical` clears 3:1 on both surfaces; `serious` measures
///   2.64:1 on white, so the **relief rule** applies — every status mark in this UI
///   ships a visible count label *and* an SF Symbol, so colour never carries meaning
///   alone. (The categorical lightness band does not govern status tokens.)
enum VizPalette {

    /// The single categorical slot. One series, one colour — bars are never shaded by
    /// their own length, which would double-encode magnitude as hue.
    static let series = dynamic(light: 0x2A78D6, dark: 0x3987E5)

    /// Reserved status tokens. Fixed hexes in both appearances.
    static let critical = dynamic(light: 0xD03B3B, dark: 0xD03B3B)
    static let serious  = dynamic(light: 0xEC835A, dark: 0xEC835A)

    /// Colour for a category's bar and pill, chosen by what the category discloses.
    static func color(for category: MetadataCategory) -> Color {
        switch category.severity {
        case .critical:      return critical
        case .serious:       return serious
        case .informational: return series
        }
    }

    /// Recessive hairline for the chart baseline. Native semantic colour, so it tracks
    /// the system's own idea of a separator in both appearances.
    static let axis = Color(nsColor: .separatorColor)

    /// The surface the marks sit on. Also the colour of the 2px gap that separates
    /// touching bars — the gap is surface showing through, not a stroke.
    static let surface = Color(nsColor: .textBackgroundColor)

    // MARK: Plumbing

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    /// `0xRRGGBB` in sRGB. The validator's numbers are sRGB, so the colour space is
    /// pinned rather than left to the generic calibrated space.
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green:   CGFloat((hex >> 8)  & 0xFF) / 255,
                  blue:    CGFloat(hex & 0xFF) / 255,
                  alpha:   1)
    }
}
