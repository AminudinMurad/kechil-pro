import SwiftUI

/// Best-fit size picker: one tile per MacBook, plus a line saying which is on now.
///
/// The SwiftUI counterpart of Klik PRO's `DashboardBestFitControl`, which is an
/// `NSView` drawing its own tiles. Same five models, same drawn-MacBook affordance,
/// same "On now" / "Custom" status; rebuilt in SwiftUI because this app has no AppKit
/// view hierarchy to hang a custom control off.
struct DashboardSizeControl: View {
    @ObservedObject var sizer: DashboardSizer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DASHBOARD BEST FIT")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 8) {
                ForEach(DashboardPreset.allCases) { preset in
                    tile(preset)
                }
            }
            .frame(maxWidth: .infinity)

            status
            Text("Choose a MacBook model to apply its best-fit dashboard height. "
                 + "Width stays fixed at 940; the window remains vertically resizable.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        // A radio group, not five unrelated buttons: exactly one is in effect at a time.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dashboard best fit")
    }

    // MARK: Tile

    private func tile(_ preset: DashboardPreset) -> some View {
        let isActive = sizer.activePreset == preset

        return Button {
            sizer.apply(preset)
        } label: {
            VStack(spacing: 5) {
                MacBookGlyph(preset: preset, isActive: isActive)
                Text(preset.controlTitle)
                    .font(.system(size: 10.5, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(preset.sizeTitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isActive ? Color.accentColor : Color.clear, lineWidth: 1.5))
            )
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .help("\(preset.controlTitle) MacBook — \(preset.sizeTitle) points")
        .accessibilityLabel("\(preset.controlTitle), \(preset.sizeTitle)")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Status

    /// Green when a preset is in effect, secondary ink when it is not — and it always
    /// prints the actual numbers, so "Custom" still tells the user where they are.
    private var status: some View {
        Group {
            if let preset = sizer.activePreset {
                Label("On now: \(preset.controlTitle) · \(preset.sizeTitle)",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Custom height · 940 × \(Int(sizer.contentSize.height.rounded()))",
                      systemImage: "arrow.up.and.down")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, weight: .medium))
    }
}

// MARK: - Glyph

/// A MacBook drawn to scale, so the row reads as a ladder of sizes on sight.
///
/// Width tracks the diagonal exactly as Klik PRO's `DashboardPresetTileButton` does,
/// and the notch appears on every model that has one.
private struct MacBookGlyph: View {
    let preset: DashboardPreset
    let isActive: Bool

    private var width: CGFloat { 26 + (preset.diagonal - 13.3) * 3.4 }
    private var height: CGFloat { (width * 0.64).rounded() }
    private var tint: Color { isActive ? Color.accentColor : Color.secondary }

    var body: some View {
        VStack(spacing: 1.5) {
            RoundedRectangle(cornerRadius: 2.5)
                .strokeBorder(tint, lineWidth: 1.2)
                .frame(width: width, height: height)
                .overlay(alignment: .top) {
                    if preset.hasNotch {
                        // Inset by the stroke so the notch reads as part of the bezel
                        // rather than a mark floating above it.
                        Rectangle()
                            .fill(tint)
                            .frame(width: (width * 0.24).rounded(), height: 2)
                            .offset(y: 0.6)
                    }
                }
            Capsule()
                .fill(tint)
                .frame(width: (width * 1.16).rounded(), height: 1.8)
        }
        // Fixed cell, so the labels below sit on one line across all five tiles even
        // though the glyphs differ in height.
        .frame(width: 46, height: 30, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
