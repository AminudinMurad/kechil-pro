import SwiftUI

/// Per-file detail for the selected row.
///
/// This pane is also how the breakdown chart stays readable without colour: every count
/// in it is reachable here as plain text, file by file.
struct InspectorPanel: View {
    @ObservedObject var model: ScrubModel

    var body: some View {
        Group {
            if let item = model.selectedItem {
                detail(for: item)
            } else {
                placeholder
            }
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 380, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: Detail

    private func detail(for item: ScrubItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                preview(for: item)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text(sizeLine(for: item))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                losslessBadge(for: item)
                Divider()
                findings(for: item)

                if let saved = item.savedTo {
                    Divider()
                    Label("Saved as \(saved.lastPathComponent)", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else if item.cleanedData != nil {
                    Button("Save Clean Copy…") { model.save(item: item) }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(14)
        }
        .kechilScrollbars()
    }

    private func preview(for item: ScrubItem) -> some View {
        Group {
            if let image = item.thumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sizeLine(for item: ScrubItem) -> String {
        var parts = [item.format.rawValue]
        if let cleaned = item.cleanedSize {
            parts.append("\(Fmt.bytes(item.originalSize)) → \(Fmt.bytes(cleaned))")
        } else {
            parts.append(Fmt.bytes(item.originalSize))
        }
        return parts.joined(separator: "  ·  ")
    }

    /// Reads `item.lossless` rather than assuming it. A file that went through the
    /// re-encode fallback has to say so.
    @ViewBuilder
    private func losslessBadge(for item: ScrubItem) -> some View {
        if item.errorText == nil {
            if item.lossless {
                Label("Lossless — pixels untouched", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Label("Re-encoded — pixels changed", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VizPalette.serious)
            }
        }
    }

    @ViewBuilder
    private func findings(for item: ScrubItem) -> some View {
        if let error = item.errorText {
            detailSection(title: "Could not process",
                          symbol: "xmark.octagon.fill",
                          tone: .caution) {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 13) {
                if let ai = item.provenance.generativeFinding {
                    aiBanner(ai)
                }

                if item.provenance.carriers.isEmpty && item.provenance.findings.isEmpty &&
                    item.removed.isEmpty {
                    detailSection(title: "Detected in original", symbol: "scope") {
                        Text("No supported metadata or AI-provenance carrier was found in the input.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !item.provenance.carriers.isEmpty {
                        detailSection(title: "Detected in original",
                                      symbol: "scope",
                                      tone: .failure) {
                            ForEach(Array(item.provenance.carriers.enumerated()), id: \.offset) { _, carrier in
                                Text(carrier)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if !item.provenance.findings.isEmpty {
                        detailSection(title: "Original file revealed", symbol: "eye.fill") {
                            ForEach(item.provenance.findings) { finding in
                                findingRow(finding)
                            }
                        }
                    }
                }

                if !item.removed.isEmpty {
                    detailSection(title: "Removed", symbol: "trash.slash.fill", tone: .action) {
                        // Already in fixed order, so GPS leads whenever it is present.
                        ForEach(item.removedCategories) { category in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: category.symbolName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(VizPalette.color(for: category))
                                    .frame(width: 13)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(category.displayName)
                                        .font(.system(size: 11.5, weight: .medium))
                                    Text(category.blurb)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        Text(item.removed.joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }

                verificationSection(item)

                detailSection(title: "Still present",
                              symbol: "exclamationmark.shield.fill",
                              tone: .caution) {
                    ForEach(Array(item.provenance.stillPresent.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Text("Invisible in-pixel watermarks such as SynthID are not metadata and are not removed.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                if !item.provenance.limitations.isEmpty {
                    detailSection(title: "Verification limits",
                                  symbol: "info.circle",
                                  tone: .caution) {
                        ForEach(Array(item.provenance.limitations.enumerated()), id: \.offset) { _, limit in
                            Text(limit).font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func aiBanner(_ finding: ProvenanceFinding) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("GENERATIVE AI", systemImage: "sparkles")
                .font(.system(size: 11, weight: .bold))
            Text(finding.title)
                .font(.system(size: 12.5, weight: .semibold))
            Text("\(finding.confidence.rawValue) · \(finding.protocolName)")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(VizPalette.critical)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(VizPalette.critical.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(VizPalette.critical.opacity(0.55), lineWidth: 1))
    }

    private enum DetailSectionTone {
        case source
        case action
        case success
        case caution
        case failure
    }

    private func sectionAccent(_ tone: DetailSectionTone) -> Color {
        switch tone {
        case .source: return Color.secondary
        case .action: return Color.accentColor
        case .success: return Color.green
        case .caution: return Color.orange
        case .failure: return VizPalette.critical
        }
    }

    private func detailSection<Content: View>(
        title: String,
        symbol: String,
        tone: DetailSectionTone = .source,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let accent = sectionAccent(tone)
        let isFailure = tone == .failure
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(accent.opacity(0.12)))
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isFailure ? accent : Color.primary)
                    .tracking(0.25)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            Divider()
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(isFailure
                  ? accent.opacity(0.055)
                  : Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(accent.opacity(isFailure ? 0.55 : (tone == .source ? 0.16 : 0.28)),
                          lineWidth: 1))
    }

    private func findingRow(_ finding: ProvenanceFinding) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(finding.title)
                .font(.system(size: 11.5, weight: .medium))
            if !finding.detail.isEmpty {
                Text(finding.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Text("\(finding.confidence.rawValue) · \(finding.protocolName)")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 3)
    }

    @ViewBuilder
    private func verificationSection(_ item: ScrubItem) -> some View {
        detailSection(title: "Verified output",
                      symbol: verificationSymbol(for: item),
                      tone: verificationTone(for: item)) {
            switch item.verificationState {
            case .clean:
                Label(item.preset == .allMetadata
                      ? "Re-read clean — no supported metadata or provenance carrier remains."
                      : "Re-read clean — the \(item.preset.title) scope is no longer detected.",
                      systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.green)
                if item.preset != .allMetadata,
                   let output = item.outputProvenance,
                   output.hasDetectedMetadata {
                    Text("Other metadata outside this selected scope remains in the output.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if item.preset != .gps,
                       output.findings.contains(where: { $0.kind == .location }) {
                        Label("GPS remains. Choose GPS or All metadata to remove it.",
                              systemImage: "location.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(VizPalette.critical)
                    }
                }
            case .remaining:
                Label(item.preset == .allMetadata
                      ? "The cleaned output still contains detectable metadata."
                      : "The cleaned output still contains selected-scope metadata.",
                      systemImage: "xmark.octagon.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(VizPalette.critical)
                if let output = item.outputProvenance {
                    ForEach(Array(output.carriers.enumerated()), id: \.offset) { _, carrier in
                        Text(carrier).font(.system(size: 10, design: .monospaced))
                    }
                }
            case .partial:
                Label("Output was re-read, but this container has partial verification coverage.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func verificationTone(for item: ScrubItem) -> DetailSectionTone {
        switch item.verificationState {
        case .clean: return .success
        case .remaining: return .failure
        case .partial: return .caution
        }
    }

    private func verificationSymbol(for item: ScrubItem) -> String {
        switch item.verificationState {
        case .clean: return "checkmark.shield.fill"
        case .remaining: return "xmark.shield.fill"
        case .partial: return "exclamationmark.shield.fill"
        }
    }

    // MARK: Empty

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.items.isEmpty ? "No images yet" : "No image selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if !model.items.isEmpty {
                Text("Select a row to see what it was carrying.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
