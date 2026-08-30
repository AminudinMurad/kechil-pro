import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class VideoCleanModel: ObservableObject {
    @Published var items: [VideoQueueItem] = []
    @Published var selectedItemID: UUID?
    @Published var isProcessing = false
    @Published var statusMessage: String?
    /// Video Clean is multi-select. All supported groups are selected by default,
    /// matching the safe broad-clean behaviour users already had.
    @Published private(set) var selection: VideoCleanSelection = .all
    /// Kept for compatibility with older integrations that read the old single
    /// preset. The video UI and pipeline use `selection`.
    @Published private(set) var preset: CleanPreset = .allMetadata

    private var processingTask: Task<Void, Never>?

    var selectedItem: VideoQueueItem? {
        guard let selectedItemID else { return items.first }
        return items.first { $0.id == selectedItemID }
    }
    var completedCount: Int { items.filter(\.isSaveReady).count }
    var unsavedCount: Int { items.filter { $0.isSaveReady && $0.savedTo == nil }.count }

    /// Changes the cleanup scope and re-runs the queued videos from their originals.
    /// A video export is never chained from a previous cleaned copy.
    func selectPreset(_ newPreset: CleanPreset) {
        selectSelection(newPreset.videoSelection)
    }

    /// Toggles one of the five visible video metadata groups. Reprocessing always
    /// starts from the original source, so changing a selection cannot compound a
    /// previous partial clean.
    func toggle(_ scope: VideoCleanScope) {
        var next = selection
        next.toggle(scope)
        selectSelection(next)
    }

    func selectSelection(_ newSelection: VideoCleanSelection) {
        guard newSelection != selection else { return }
        guard !isProcessing else {
            statusMessage = "Finish the current cleanup before changing the groups."
            return
        }
        selection = newSelection
        // `preset` is only a compatibility value for older callers. A multi-select
        // cannot be represented by one of the original four image presets.
        preset = .allMetadata
        guard !items.isEmpty else { return }
        process(ids: Set(items.map(\.id)), selection: newSelection)
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.message = "Choose MOV, MP4 or M4V videos to clean"
        guard panel.runModal() == .OK else { return }
        add(urls: panel.urls)
    }

    func add(urls: [URL]) {
        let expanded = expand(urls: urls)
        guard !expanded.isEmpty else {
            statusMessage = "No supported MOV, MP4 or M4V videos were found."
            return
        }
        let existing = Set(items.map { $0.sourceURL.standardizedFileURL })
        let newItems = expanded.filter { !existing.contains($0.standardizedFileURL) }
            .map(VideoQueueItem.init(sourceURL:))
        guard !newItems.isEmpty else {
            statusMessage = "Those videos are already in this queue."
            return
        }
        items.append(contentsOf: newItems)
        if selectedItemID == nil { selectedItemID = newItems.first?.id }
        process(ids: Set(newItems.map(\.id)))
    }

    func cancel() {
        guard isProcessing else { return }
        statusMessage = "Cancelling…"
        processingTask?.cancel()
    }

    func clear() {
        processingTask?.cancel()
        for item in items { cleanup(item.outputURL) }
        items.removeAll()
        selectedItemID = nil
        statusMessage = nil
        isProcessing = false
    }

    func remove(item: VideoQueueItem) {
        cleanup(item.outputURL)
        items.removeAll { $0.id == item.id }
        if selectedItemID == item.id { selectedItemID = items.first?.id }
    }

    func save(item: VideoQueueItem) {
        guard let outputURL = item.outputURL else { return }
        let ext = outputURL.pathExtension
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.suggestedFilename(suffix: "clean", extension: ext)
        panel.directoryURL = AppSettings.shared.defaultSaveDirectory
        panel.canCreateDirectories = true
        panel.message = "Save the verified cleaned copy of \(item.displayName)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        write(itemID: item.id, outputURL: outputURL, destination: destination)
    }

    func saveAll() {
        let pending = items.filter(\.isSaveReady)
        guard !pending.isEmpty else { return }
        let folder: URL
        if let configured = AppSettings.shared.defaultSaveDirectory {
            folder = configured
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Save Here"
            panel.message = "Choose a folder for \(pending.count) cleaned video\(pending.count == 1 ? "" : "s")"
            guard panel.runModal() == .OK, let selected = panel.url else { return }
            folder = selected
        }
        var saved = 0
        for item in pending {
            guard let outputURL = item.outputURL else { continue }
            let filename = item.suggestedFilename(suffix: "clean", extension: outputURL.pathExtension)
            let destination = MediaSaveService.uniqueURL(in: folder, filename: filename)
            if write(itemID: item.id, outputURL: outputURL, destination: destination) { saved += 1 }
        }
        statusMessage = "Saved \(saved) cleaned video\(saved == 1 ? "" : "s") to \(folder.lastPathComponent)."
    }

    private func process(ids: Set<UUID>, selection selectedSelection: VideoCleanSelection? = nil) {
        guard !isProcessing else {
            statusMessage = "The current video is still being cleaned. New videos remain queued."
            return
        }
        let activeSelection = selectedSelection ?? self.selection
        processingTask = Task { [weak self] in
            guard let self else { return }
            self.isProcessing = true
            let queue = self.items.filter { ids.contains($0.id) }
            var completed = 0
            for queued in queue {
                if Task.isCancelled { break }
                guard let index = self.items.firstIndex(where: { $0.id == queued.id }) else { continue }
                self.cleanup(self.items[index].outputURL)
                self.items[index].outputURL = nil
                self.items[index].outputDescriptor = nil
                self.items[index].outputFileSize = nil
                self.items[index].savedTo = nil
                self.items[index].selection = activeSelection
                self.items[index].preset = .allMetadata
                self.items[index].stage = .analysing
                self.items[index].phase = .reading
                self.items[index].statusText = "Reading video details…"
                self.statusMessage = "\(activeSelection.actionTitle) \(completed + 1) of \(queue.count) videos…"
                do {
                    async let poster = VideoPosterGenerator.image(for: queued.sourceURL)
                    let descriptor = try await MediaCapabilityProbe.inspectVideo(at: queued.sourceURL)
                    guard let current = self.items.firstIndex(where: { $0.id == queued.id }) else { continue }
                    self.items[current].descriptor = descriptor
                    self.items[current].poster = await poster
                    self.items[current].stage = .processing
                    self.items[current].phase = .writing
                    self.items[current].statusText = "Rewriting the container without selected metadata…"
                    let result = try await VideoCleanPipeline.clean(sourceURL: queued.sourceURL,
                                                                     selection: activeSelection)
                    guard let final = self.items.firstIndex(where: { $0.id == queued.id }) else {
                        self.cleanup(result.outputURL)
                        continue
                    }
                    self.items[final].outputDescriptor = result.outputDescriptor
                    self.items[final].detectedFindings = result.inputFindings
                    self.items[final].findings = result.inputFindings.filter { activeSelection.matches($0) }
                    self.items[final].remainingFindings = result.remainingFindings
                    self.items[final].verification = result.verification
                    self.items[final].outputURL = result.outputURL
                    self.items[final].outputFileSize = Int64((try? result.outputURL.resourceValues(
                        forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    self.items[final].phase = .verifying
                    self.items[final].stage = .completed
                    self.items[final].statusText = result.remainingFindings.isEmpty
                        ? result.verification.label
                        : "Some selected metadata remains"
                    self.items[final].errorText = nil
                    completed += 1
                } catch is CancellationError {
                    if let current = self.items.firstIndex(where: { $0.id == queued.id }) {
                        self.items[current].stage = .cancelled
                        self.items[current].statusText = "Cancelled; original is unchanged"
                    }
                    break
                } catch {
                    if let current = self.items.firstIndex(where: { $0.id == queued.id }) {
                        self.items[current].stage = .failed
                        self.items[current].errorText = error.localizedDescription
                        self.items[current].statusText = "Could not clean this video"
                    }
                }
            }
            self.isProcessing = false
            self.processingTask = nil
            self.statusMessage = Task.isCancelled
                ? "Cancelled; every original is unchanged."
                : "\(activeSelection.actionTitle) completed for \(completed) of \(queue.count) video\(queue.count == 1 ? "" : "s")."
            let waiting = Set(self.items.filter { $0.stage == .queued }.map(\.id))
            if !waiting.isEmpty, !Task.isCancelled { self.process(ids: waiting) }
        }
    }

    @discardableResult
    private func write(itemID: UUID, outputURL: URL, destination: URL) -> Bool {
        do {
            try MediaSaveService.protectOriginals(
                destination: destination, sourceURLs: items.map(\.sourceURL))
            try MediaSaveService.copyTemporaryOutput(from: outputURL, to: destination)
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { return true }
            items[index].savedTo = destination
            items[index].stage = .saved
            cleanup(items[index].outputURL)
            items[index].outputURL = nil
            return true
        } catch {
            statusMessage = "Could not save \(destination.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    private func expand(urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let enumerator = FileManager.default.enumerator(at: url,
                    includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let child = enumerator?.nextObject() as? URL {
                    if MediaCapabilityProbe.videoExtensions.contains(child.pathExtension.lowercased()) {
                        result.append(child)
                    }
                }
            } else if MediaCapabilityProbe.videoExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result
    }

    private func cleanup(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
