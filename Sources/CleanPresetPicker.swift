import SwiftUI

/// The four legacy image Clean choices. Video Clean uses the more precise
/// multi-select `VideoCleanScopePicker` because movie metadata has different
/// container-level boundaries.
struct CleanPresetPicker: View {
    @Binding var selection: CleanPreset
    let media: MediaKind
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Remove", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selection == .allMetadata ? "All supported groups" : selection.title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                      spacing: 8) {
                ForEach(CleanPreset.allCases) { preset in
                    option(preset)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .opacity(isDisabled ? 0.62 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image metadata groups to remove")
    }

    private func option(_ preset: CleanPreset) -> some View {
        let selected = selection == preset
        return Button {
            guard !isDisabled else { return }
            selection = preset
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: preset.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(preset.detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(preset.scopeDescription)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(preset.title), \(preset.detail)")
    }
}
