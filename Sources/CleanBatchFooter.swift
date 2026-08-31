import SwiftUI

/// Clean All means all reviewed files, using the chosen removal groups.
/// A no-match batch prepares unchanged copies rather than claiming cleanup.
struct CleanBatchActionState: Equatable {
    let readyCount: Int
    let plannedChangeCount: Int
    let isProcessing: Bool

    var canClean: Bool { readyCount > 0 && !isProcessing }
    var title: String {
        readyCount > 0 && plannedChangeCount == 0 ? "Re-Save All" : "Clean All"
    }

    func cleanIfReady(_ action: () -> Void) {
        guard canClean else { return }
        action()
    }
}

/// Stays below the scrolling Clean queue, separating processing from saving.
struct CleanBatchFooter: View {
    let readyCount: Int
    let plannedChangeCount: Int
    let preparedCount: Int
    let isProcessing: Bool
    let clean: () -> Void
    let cancel: () -> Void
    var canCleanSelected = false
    var selectedHasChanges = true
    var selectedCount = 0
    var cleanSelected: () -> Void = {}

    private var state: CleanBatchActionState {
        CleanBatchActionState(readyCount: readyCount, plannedChangeCount: plannedChangeCount,
                              isProcessing: isProcessing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(detail)
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if isProcessing {
                Button("Cancel", action: cancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: KechilActionMetrics.actionMinHeight)
            } else {
                Button {
                    guard canCleanSelected else { return }
                    cleanSelected()
                } label: {
                    Label(selectedActionTitle, systemImage: selectedHasChanges
                          ? "checkmark.shield" : "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: KechilActionMetrics.actionMinHeight)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, minHeight: KechilActionMetrics.actionMinHeight)
                .disabled(!canCleanSelected)
                .help("Process only the selected inspected file\(selectedCount == 1 ? "" : "s"), using the chosen metadata-removal settings. Command-click or Shift-click rows to select more than one.")
                Button { state.cleanIfReady(clean) } label: {
                    Label(state.title, systemImage: plannedChangeCount > 0
                          ? "checkmark.shield" : "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: KechilActionMetrics.actionMinHeight)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: KechilActionMetrics.actionMinHeight)
                .disabled(!state.canClean)
                .help("Uses the selected metadata-removal settings for every inspected file waiting in this queue, including files hidden by a findings filter. Originals stay unchanged; save outputs separately.")
            }
        }
        .controlSize(.regular)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var selectedActionTitle: String {
        let suffix = selectedCount > 1 ? " (\(selectedCount))" : ""
        return (selectedHasChanges ? "Clean Selected" : "Re-Save Selected") + suffix
    }

    private var detail: String {
        if isProcessing { return "Processing the batch. Originals stay unchanged." }
        if readyCount == 0, preparedCount > 0 { return "Outputs ready. Use Save All above to save them." }
        if readyCount == 0 { return "No inspected files waiting for cleanup." }
        let files = readyCount == 1 ? "1 inspected file" : "\(readyCount) inspected files"
        if plannedChangeCount == 0 { return "No matching metadata. Re-save unchanged files from \(files)." }
        return "\(files) · chosen metadata settings. Save outputs after cleaning."
    }
}
