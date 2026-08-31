import SwiftUI

/// Compact, multi-select video metadata scope rail.
struct VideoCleanScopePicker: View {
    @Binding var selection: VideoCleanSelection
    var isDisabled = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CompactFlowLayout(spacing: CleanCompactStyle.chipSpacing, lineSpacing: 6) {
                Label("Remove", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(height: CleanCompactStyle.scopeHeight)
                    .padding(.trailing, 2)

                ForEach(VideoCleanScope.allCases) { scope in
                    CleanScopeChip(title: scope.title,
                                   symbolName: scope.symbolName,
                                   help: "\(scope.detail). \(scope.scopeDescription)",
                                   selected: selection.contains(scope),
                                   disabled: isDisabled) {
                        var next = selection
                        next.toggle(scope)
                        selection = next
                    }
                }
            }

            Spacer(minLength: 0)
            Button(selection == .all ? "Clear" : "All") {
                selection = selection == .all ? [] : .all
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .font(.system(size: 10))
            .frame(height: CleanCompactStyle.scopeHeight)
            .disabled(isDisabled)
            .help(selection == .all ? "Clear every removal scope" : "Select every supported removal scope")
        }
        .padding(.horizontal, CleanCompactStyle.horizontalPadding)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .opacity(isDisabled ? 0.62 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video metadata groups to remove")
    }
}
