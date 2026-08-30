import CoreGraphics

enum KechilScrollbarAxis {
    case vertical
    case horizontal
}

/// Geometry shared by the AppKit scroller and its regression checks.
///
/// AppKit normally makes a scrollbar thumb proportional to the visible content.
/// Kechil uses a compact overlay thumb instead: ten percent of the available track,
/// with a small accessibility floor on unusually short controls.
enum KechilScrollbarGeometry {
    static let thumbFraction: CGFloat = 0.10
    static let minimumThumbLength: CGFloat = 28

    static func thumbRect(
        in slot: CGRect,
        value: Double,
        axis: KechilScrollbarAxis
    ) -> CGRect {
        guard !slot.isEmpty else { return .zero }

        let trackLength = axis == .vertical ? slot.height : slot.width
        guard trackLength > 0 else { return .zero }

        let thumbLength = min(
            trackLength,
            max(minimumThumbLength, trackLength * thumbFraction))
        let normalisedValue = CGFloat(min(1, max(0, value)))
        let thumbOffset = (trackLength - thumbLength) * normalisedValue

        switch axis {
        case .vertical:
            return CGRect(
                x: slot.minX,
                y: slot.minY + thumbOffset,
                width: slot.width,
                height: thumbLength)
        case .horizontal:
            return CGRect(
                x: slot.minX + thumbOffset,
                y: slot.minY,
                width: thumbLength,
                height: slot.height)
        }
    }
}
