import AppKit
import SwiftUI

/// The Kechil PRO dashboard lockup: app icon, title, raised tier badge, and version.
///
/// It follows Klik PRO's single-line dashboard hierarchy. The icon is the same bundle
/// resource shown by the Dock and Finder, not a second drawing.
struct BrandLockup: View {
    // Klik PRO renders its 21pt base wordmark at 2× in the dashboard header.
    var iconSize: CGFloat = 52
    var titleSize: CGFloat = 42

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .shadow(color: .black.opacity(0.14), radius: 1.5, y: 0.5)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                wordmark
                Text(versionString)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kechil PRO, \(versionString)")
    }

    // MARK: Wordmark

    private var wordmark: some View {
        HStack(alignment: .firstTextBaseline, spacing: titleSize * (3 / 21)) {
            Text("Kechil")
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(Brand.textPrimary)
            Text("PRO")
                .font(.system(size: titleSize * (5 / 21), weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, titleSize * (1 / 21))
                .frame(height: titleSize * (8 / 21))
                .background(
                    RoundedRectangle(cornerRadius: titleSize * (1.5 / 21), style: .continuous)
                        .fill(Brand.badgeFill)
                )
                // Raised to sit against the wordmark's cap height, so it reads as a tier
                // marker rather than a second word of equal weight. A larger baseline
                // guide lifts the view, so the badge's bottom lands this far *above* the
                // wordmark's baseline.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + titleSize * (4 / 21) }
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else {
            return "v\(short)"
        }
        return "v\(short) (\(build))"
    }
}

/// Adaptive brand tokens shared by the dashboard wordmark.
enum Brand {
    /// Klik PRO family green, matching the foreground and badge in the app icon.
    static let badgeFill = Color(.sRGB, red: 25 / 255, green: 187 / 255, blue: 19 / 255)

    /// Klik PRO's legibility-adjusted adaptive text values, shared here so the two PRO
    /// product headers carry the same visual weight in light and dark appearances.
    static let textPrimary = dynamic(light: 0x1C1C1C, dark: 0xF5F5F5)
    static let textSecondary = dynamic(light: 0x666666, dark: 0xB8B8B8)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                           green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255,
                           alpha: 1)
        })
    }
}
