import SwiftUI

/// A compact macOS number field with native increment/decrement arrows. Direct
/// typing remains available, while the stepper gives an obvious bounded control
/// for values such as crop sizes, target sizes, and percentages.
struct KechilNumericStepperField: View {
    let label: String
    @Binding var value: Double
    let step: Double
    let lowerBound: Double
    var upperBound: Double? = nil

    var body: some View {
        HStack(spacing: 2) {
            TextField(label, value: boundedValue,
                      format: .number.precision(.fractionLength(0...2)))
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
            Stepper("", onIncrement: { setValue(value + step) },
                    onDecrement: { setValue(value - step) })
                .labelsHidden()
                .fixedSize()
                .help("Increase or decrease \(label)")
                .accessibilityLabel("Increase or decrease \(label)")
        }
    }

    private var boundedValue: Binding<Double> {
        Binding(get: { value }, set: setValue)
    }

    private func setValue(_ proposedValue: Double) {
        guard proposedValue.isFinite else { return }
        var bounded = max(lowerBound, proposedValue.rounded())
        if let upperBound { bounded = min(upperBound, bounded) }
        value = bounded
    }
}
