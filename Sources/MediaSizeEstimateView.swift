import SwiftUI

/// Shared live-size presentation for Clean and Watermark. The card keeps the
/// exact byte count visible, while the larger decimal value is easier to scan.
struct MediaSizeEstimateCard: View {
    let title: String
    let estimate: MediaSizeEstimate?
    let isEstimating: Bool
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(title, systemImage: "chart.bar.xaxis")
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer(minLength: 6)
                if isEstimating { ProgressView().controlSize(.small) }
            }

            if let estimate {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Estimated output")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                        Text(MediaSizeText.bytes(estimate.estimatedBytes))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(MediaSizeText.exactBytes(estimate.estimatedBytes))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Change")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                        Text(MediaSizeText.signedBytes(estimate.deltaBytes))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(estimate.deltaBytes <= 0 ? .green : .orange)
                            .monospacedDigit()
                        Text("from \(MediaSizeText.bytes(estimate.sourceBytes))")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider()
                Text(estimate.basis.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(estimate.detail)
                    .font(.system(size: 9.3))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isEstimating {
                Text("Measuring a real output with the current settings…")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a source to measure its output with the current settings.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 1))
    }
}
