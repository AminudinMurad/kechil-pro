import SwiftUI

/// Multi-select cleanup groups for video Clean. The cards mirror the scoped
/// metadata choices in the reference workflow while keeping the selection explicit
/// and reversible before a file is processed.
struct VideoCleanScopePicker: View {
    @Binding var selection: VideoCleanSelection
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Remove", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selection == .all ? "All supported groups" : selection.title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(selection == .all ? "Clear" : "Select all") {
                    guard !isDisabled else { return }
                    selection = selection == .all ? [] : .all
                }
                .buttonStyle(.borderless)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .disabled(isDisabled)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                      spacing: 8) {
                ForEach(VideoCleanScope.allCases) { scope in
                    option(scope)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .opacity(isDisabled ? 0.62 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video metadata groups to remove")
    }

    private func option(_ scope: VideoCleanScope) -> some View {
        let selected = selection.contains(scope)
        return Button {
            guard !isDisabled else { return }
            var next = selection
            next.toggle(scope)
            selection = next
        } label: {
            HStack(alignment: .top, spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.accentColor.opacity(0.14)
                                       : Color.primary.opacity(0.055))
                    Image(systemName: scope.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.title)
                        .font(.system(size: 10, weight: selected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                    Text(scope.detail)
                        .font(.system(size: 8.3))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 57, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(scope.scopeDescription)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(scope.title), \(scope.detail)")
    }
}
