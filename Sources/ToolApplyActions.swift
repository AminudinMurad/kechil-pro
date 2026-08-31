import SwiftUI

struct ToolApplyActions: View {
    let operation: String
    let canProcessAll: Bool
    let canProcessSelected: Bool
    let processAll: () -> Void
    let processSelected: () -> Void
    var selectedCount = 0

    var body: some View {
        VStack(spacing: 7) {
            Button {
                guard canProcessSelected else { return }
                processSelected()
            } label: {
                Label(selectedTitle, systemImage: "scope")
                    .frame(maxWidth: .infinity, minHeight: KechilActionMetrics.actionMinHeight)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, minHeight: KechilActionMetrics.actionMinHeight)
            .disabled(!canProcessSelected)
            .help("Process only the selected file\(selectedCount == 1 ? "" : "s") using the current settings. Command-click or Shift-click rows to select more than one. Other outputs stay unchanged.")

            Button {
                guard canProcessAll else { return }
                processAll()
            } label: {
                Label("\(operation) All", systemImage: "square.stack")
                    .frame(maxWidth: .infinity, minHeight: KechilActionMetrics.actionMinHeight)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, minHeight: KechilActionMetrics.actionMinHeight)
            .disabled(!canProcessAll)
            .help("Process the whole queue using the current settings. Save the prepared outputs separately.")
        }
        .controlSize(.regular)
    }

    private var selectedTitle: String {
        selectedCount > 1 ? "\(operation) Selected (\(selectedCount))" : "\(operation) Selected"
    }
}
