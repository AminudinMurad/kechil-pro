import AppKit
import SwiftUI

enum KechilActionMetrics {
    static let actionMinHeight: CGFloat = 30
}

/// One availability rule for both Save All placements, across all six routes.
struct BatchSaveState: Equatable {
    let readyCount: Int
    let isProcessing: Bool

    var canSave: Bool { readyCount > 0 && !isProcessing }

    var help: String {
        if isProcessing { return "Wait for processing to finish before saving the batch." }
        if readyCount == 0 { return "Process files to prepare outputs for saving." }
        return "Save all \(readyCount) ready \(readyCount == 1 ? "file" : "files"), not just the selected preview."
    }

    func saveIfReady(_ action: () -> Void) {
        guard canSave else { return }
        action()
    }
}

struct BatchSaveButton: View {
    let readyCount: Int
    let isProcessing: Bool
    let action: () -> Void

    private var state: BatchSaveState {
        BatchSaveState(readyCount: readyCount, isProcessing: isProcessing)
    }

    var body: some View {
        Button { state.saveIfReady(action) } label: {
            Label("Save All…", systemImage: "square.and.arrow.down")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(KechilSaveButtonStyle())
        .controlSize(.regular)
        .disabled(!state.canSave)
        .help(state.help)
        .accessibilityHint(state.help)
    }
}

/// Keeps the requested green treatment visible even when the window is inactive.
struct KechilSaveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let fixedWidth: CGFloat?

    init(width: CGFloat? = nil) {
        fixedWidth = width
    }

    func makeBody(configuration: Configuration) -> some View {
        sizedLabel(configuration.label)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.72))
            .background(RoundedRectangle(cornerRadius: 6).fill(
                Color(red: 0.06, green: 0.43, blue: 0.23)
                    .opacity(isEnabled ? 1 : 0.38)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(configuration.isPressed && isEnabled ? 0.16 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private func sizedLabel(_ label: Configuration.Label) -> AnyView {
        let height = KechilActionMetrics.actionMinHeight - 12
        if let fixedWidth {
            return AnyView(label
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(minWidth: max(0, fixedWidth - 20),
                       maxWidth: max(0, fixedWidth - 20),
                       minHeight: height))
        }
        return AnyView(label
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: height))
    }
}

@MainActor
enum BatchSaveFolderChooser {
    static func choose(defaultDirectory: URL?, message: String) -> URL? {
        if let defaultDirectory { return defaultDirectory }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Persistent above the results, outside the scrolling list and preview.
struct BatchOutputHeader: View {
    var title = "Batch output"
    let queuedCount: Int
    let readyCount: Int
    let isProcessing: Bool
    let save: () -> Void
    var selectedName: String? = nil
    var selectedCount = 0
    var selectedReadyCount = 0
    var canSaveSelected = false
    var saveSelected: () -> Void = {}

    private var selectionText: String {
        guard selectedCount > 1 else {
            return selectedName.map { "Selected: \($0)" } ?? "Select a file to preview"
        }
        let ready = selectedReadyCount > 0 ? " · \(selectedReadyCount) ready" : ""
        return "Selected: \(selectedCount) files\(ready)"
    }

    private var saveSelectedTitle: String {
        selectedCount > 1 ? "Save Selected (\(selectedReadyCount))…" : "Save Selected…"
    }

    private var saveSelectedHelp: String {
        if selectedCount > 1 {
            return "Save each selected prepared file to one folder. \(selectedReadyCount) of \(selectedCount) selected files are ready; originals stay unchanged."
        }
        return "Save the highlighted file's prepared output. This does not process new settings."
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(isProcessing
                         ? "Processing… · \(readyCount) ready"
                         : "\(queuedCount) queued · \(readyCount) ready")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isProcessing { ProgressView().controlSize(.small) }
                if queuedCount > 0 {
                    BatchSaveButton(readyCount: readyCount, isProcessing: isProcessing,
                                    action: save)
                    Button(saveSelectedTitle) {
                        guard canSaveSelected && !isProcessing else { return }
                        saveSelected()
                    }
                    .buttonStyle(KechilSaveButtonStyle())
                    .controlSize(.regular)
                    .disabled(!canSaveSelected || isProcessing)
                    .help(saveSelectedHelp)
                    .accessibilityHint(saveSelectedHelp)
                }
            }
            if queuedCount > 0 {
                HStack(spacing: 8) {
                    Text(selectionText)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
