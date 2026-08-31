import SwiftUI

/// Shared review/action row for image and video Clean. It keeps both routes on the
/// same inspect -> review -> explicit clean lifecycle and button geometry.
struct CleanReviewBar: View {
    let media: MediaKind
    let readyCount: Int
    let plannedChangeCount: Int
    let preparedCount: Int
    let isInspecting: Bool
    let isCleaning: Bool
    let clean: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: stateSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(stateColor)
                .frame(width: 16)
            Text(stateTitle)
                .font(.system(size: 11, weight: .semibold))
            Text("·")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(compactStateDetail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if isInspecting || isCleaning {
                ProgressView().controlSize(.small)
                Button("Cancel", action: cancel)
                    .controlSize(.small)
                    .frame(minWidth: 104)
            } else if readyCount == 0, preparedCount > 0 {
                Label("Use Save or Save All", systemImage: "square.and.arrow.down")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 104)
            } else {
                Button(action: clean) {
                    Label(actionTitle, systemImage: actionSymbol)
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(minWidth: 104)
                    .disabled(readyCount == 0)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clean review action")
        .help(stateDetail)
    }

    private var actionTitle: String {
        CleanBatchActionState(readyCount: readyCount, plannedChangeCount: plannedChangeCount,
                              isProcessing: isInspecting || isCleaning).title
    }

    private var actionSymbol: String {
        plannedChangeCount > 0 ? "checkmark.shield" : "doc.on.doc"
    }

    private var stateTitle: String {
        if isCleaning { return "Cleaning queued \(media.title.lowercased())" }
        if isInspecting { return "Inspecting sources" }
        if readyCount == 0, preparedCount > 0 { return "Prepared outputs ready to save" }
        if readyCount == 0 { return "Waiting for inspection" }
        if plannedChangeCount == 0 { return "No matching metadata selected" }
        return "Ready for review"
    }

    private var stateDetail: String {
        if isCleaning {
            return "Outputs are prepared from the inspected originals, then verified before Save is enabled."
        }
        if isInspecting {
            return "Inspection does not create or modify an output file."
        }
        if readyCount == 0, preparedCount > 0 {
            return "\(preparedCount) verified or unchanged cop\(preparedCount == 1 ? "y is" : "ies are") ready. Use Save or Save All."
        }
        if readyCount == 0 {
            return "Add \(media.title.lowercased()) to inspect their metadata."
        }
        if plannedChangeCount == 0 {
            return "Prepare an explicitly labelled unchanged copy; no remux or metadata rewrite will run."
        }
        return "\(plannedChangeCount) of \(readyCount) reviewed \(media.title.lowercased()) match the current selection."
    }

    private var compactStateDetail: String {
        if isCleaning { return "Preparing and verifying copies" }
        if isInspecting { return "Originals remain unchanged" }
        if readyCount == 0, preparedCount > 0 { return "\(preparedCount) ready to save" }
        if readyCount == 0 { return "Add files to inspect" }
        if plannedChangeCount == 0 { return "No matching metadata" }
        return "\(plannedChangeCount) of \(readyCount) match the selection"
    }

    private var stateSymbol: String {
        if isCleaning { return "checkmark.shield.fill" }
        if isInspecting { return "doc.text.magnifyingglass" }
        if readyCount == 0, preparedCount > 0 { return "checkmark.circle.fill" }
        if plannedChangeCount == 0 { return "doc.on.doc" }
        return "list.bullet.clipboard"
    }

    private var stateColor: Color {
        if readyCount == 0, preparedCount > 0 { return .green }
        if isCleaning || plannedChangeCount > 0 { return .accentColor }
        return .secondary
    }
}
