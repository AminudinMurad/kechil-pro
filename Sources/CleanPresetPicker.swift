import SwiftUI

/// Compact, single-select image metadata scope rail.
struct CleanPresetPicker: View {
    @Binding var selection: CleanPreset
    let media: MediaKind
    var isDisabled = false

    var body: some View {
        CompactFlowLayout(spacing: CleanCompactStyle.chipSpacing, lineSpacing: 6) {
            Label("Remove", systemImage: "checkmark.shield.fill")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(height: CleanCompactStyle.scopeHeight)
                .padding(.trailing, 2)

            ForEach(CleanPreset.allCases) { preset in
                CleanScopeChip(title: preset.title,
                               symbolName: preset.symbolName,
                               help: preset.scopeDescription,
                               selected: selection == preset,
                               disabled: isDisabled) {
                    selection = preset
                }
            }
        }
        .padding(.horizontal, CleanCompactStyle.horizontalPadding)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .opacity(isDisabled ? 0.62 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image metadata groups to remove")
    }
}
