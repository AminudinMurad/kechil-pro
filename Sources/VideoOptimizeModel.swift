import AppKit
import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers

@MainActor
final class VideoOptimizeModel: ObservableObject {
    @Published var items: [VideoQueueItem] = []
    @Published var selectedItemID: UUID? {
        didSet {
            guard !selectionMutationInProgress else { return }
            selectedItemIDs = selectedItemID.map { [$0] } ?? []
            selectionAnchorID = selectedItemID
        }
    }
    @Published private(set) var selectedItemIDs: Set<UUID> = []
    @Published var settings = VideoOptimizeSettings()
    @Published var previewSeconds = 0.0
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var isProcessing = false
    @Published var statusMessage: String?
    /// A lightweight identity for the derived estimate card. Settings are a
    /// value type, so changing any nested control can replace the card without
    /// disturbing the rest of the preview or queue.
    @Published private(set) var estimateRevision = 0

    private var processingTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var playerTimeObserver: Any?
    private var playerEndObserver: NSObjectProtocol?
    private var resumesAfterScrubbing = false
    private var selectionAnchorID: UUID?
    private var selectionMutationInProgress = false

    var selectedItem: VideoQueueItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }
    var completedCount: Int { items.filter(\.isSaveReady).count }

    var selectedIDs: Set<UUID> {
        let validIDs = Set(items.map(\.id))
        let current = selectedItemIDs.intersection(validIDs)
        if !current.isEmpty { return current }
        if let selectedItemID, validIDs.contains(selectedItemID) { return [selectedItemID] }
        return []
    }

    var selectedItems: [VideoQueueItem] {
        let ids = selectedIDs
        return items.filter { ids.contains($0.id) }
    }

    var selectedItemCount: Int { selectedIDs.count }
    var selectedSaveItems: [VideoQueueItem] { selectedItems.filter(\.isSaveReady) }
    var selectedSaveCount: Int { selectedSaveItems.count }
    func isSelected(_ item: VideoQueueItem) -> Bool { selectedIDs.contains(item.id) }

    private func setSelection(_ ids: Set<UUID>, primary: UUID?) {
        selectionMutationInProgress = true
        selectedItemIDs = ids
        selectedItemID = primary
        selectionMutationInProgress = false
        selectionAnchorID = primary
    }

    var selectedPlan: VideoEncodingPlan? {
        guard let descriptor = selectedItem?.descriptor,
              let width = descriptor.displayWidth, let height = descriptor.displayHeight,
              let duration = descriptor.duration else { return nil }
        return try? VideoSizeTargetPolicy.plan(sourceSize: CGSize(width: width, height: height),
            sourceFrameRate: max(1, descriptor.frameRate ?? 30),
            sourceDuration: CMTimeGetSeconds(duration), settings: settings)
    }

    func refreshEstimate() {
        estimateRevision &+= 1
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.message = "Choose MOV, MP4 or M4V videos to optimize"
        guard panel.runModal() == .OK else { return }
        add(urls: panel.urls)
    }

    func add(urls: [URL]) {
        let expanded = VideoURLExpansion.expand(urls: urls)
        guard !expanded.isEmpty else {
            statusMessage = "No supported MOV, MP4 or M4V videos were found."
            return
        }
        let existing = Set(items.map { $0.sourceURL.standardizedFileURL })
        let newItems = expanded.filter { !existing.contains($0.standardizedFileURL) }
            .map(VideoQueueItem.init(sourceURL:))
        guard !newItems.isEmpty else { statusMessage = "Those videos are already queued."; return }
        items.append(contentsOf: newItems)
        if selectedItemID == nil, let first = newItems.first { select(first) }
        analyse(ids: Set(newItems.map(\.id)))
    }

    func select(_ item: VideoQueueItem) {
        select(item, modifiers: [])
    }

    func select(_ item: VideoQueueItem, modifiers: NSEvent.ModifierFlags) {
        let orderedIDs = items.map(\.id)
        let result = MediaSelection.update(current: selectedIDs,
                                           anchorID: selectionAnchorID,
                                           tappedID: item.id,
                                           orderedIDs: orderedIDs,
                                           modifiers: modifiers)
        setSelection(result.ids,
                     primary: MediaSelection.primaryID(for: result.ids,
                                                       preferredID: item.id,
                                                       orderedIDs: orderedIDs))
        selectionAnchorID = result.anchorID
        if let selected = selectedItem {
            previewSeconds = max(settings.trimStartSeconds, 0)
            configurePlayer(for: selected.sourceURL)
            seekPreview()
        } else {
            previewSeconds = 0
            resetPlayer()
        }
    }

    func refreshPreview() {
        if player != nil {
            seekPreview()
            return
        }
        guard let item = selectedItem else { return }
        previewTask?.cancel()
        let time = previewSeconds
        previewTask = Task { [weak self] in
            // Keep marker dragging responsive without starting an image
            // generator task for every pointer event.
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled, let self else { return }
            let poster = await VideoPosterGenerator.image(for: item.sourceURL, at: time)
            guard !Task.isCancelled,
                  let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].poster = poster
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }

        if let duration = sourceDuration, previewSeconds >= duration - 0.05 {
            previewSeconds = max(0, settings.trimStartSeconds)
            seekPreview()
        }
        player.play()
        isPlaying = true
    }

    func skipPreview(by seconds: Double) {
        setPreviewPosition(previewSeconds + seconds)
    }

    func setPreviewPosition(_ seconds: Double) {
        previewSeconds = clampedPreviewSeconds(seconds)
        seekPreview()
    }

    func previewScrubbingChanged(_ isScrubbing: Bool) {
        guard let player else { return }
        if isScrubbing {
            resumesAfterScrubbing = isPlaying
            player.pause()
            isPlaying = false
        } else {
            seekPreview()
            if resumesAfterScrubbing {
                player.play()
                isPlaying = true
            }
            resumesAfterScrubbing = false
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    func seekPreview() {
        guard let player else { return }
        previewSeconds = clampedPreviewSeconds(previewSeconds)
        player.seek(to: CMTime(seconds: previewSeconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func applyAll() {
        apply(itemIDs: Set(items.map(\.id)))
    }

    var canApplyAll: Bool {
        !isProcessing && items.contains { $0.descriptor != nil && $0.stage != .analysing }
    }

    var canApplySelected: Bool {
        canApplyAll && selectedItems.contains {
            $0.descriptor != nil && $0.stage != .analysing
        }
    }

    func applySelected() {
        guard canApplySelected else { return }
        apply(itemIDs: selectedIDs)
    }

    var canSaveSelected: Bool {
        !isProcessing && !selectedSaveItems.isEmpty
    }

    func saveSelected() {
        let pending = selectedSaveItems
        guard canSaveSelected else { return }
        if selectedItemCount == 1, let item = pending.first {
            save(item: item)
            return
        }
        guard let folder = BatchSaveFolderChooser.choose(
            defaultDirectory: AppSettings.shared.defaultSaveDirectory,
            message: "Choose a folder for \(pending.count) selected video\(pending.count == 1 ? "" : "s")") else { return }
        var saved = 0
        for item in pending {
            guard let outputURL = item.outputURL else { continue }
            let filename = item.suggestedFilename(suffix: "optimized",
                                                  extension: outputURL.pathExtension)
            let destination = MediaSaveService.uniqueURL(in: folder, filename: filename)
            if write(itemID: item.id, outputURL: outputURL, destination: destination) { saved += 1 }
        }
        statusMessage = "Saved \(saved) selected optimized video\(saved == 1 ? "" : "s") to \(folder.lastPathComponent)."
    }

    private func apply(itemIDs: Set<UUID>) {
        let ready = items.filter {
            itemIDs.contains($0.id) && $0.descriptor != nil && $0.stage != .analysing
        }
        guard !ready.isEmpty, !isProcessing, processingTask == nil else { return }
        let snapshot = settings
        isProcessing = true
        processingTask = Task { [weak self] in
            guard let self else { return }
            self.player?.pause()
            self.isPlaying = false
            var completed = 0
            for queued in ready {
                if Task.isCancelled { break }
                guard let index = self.items.firstIndex(where: { $0.id == queued.id }) else { continue }
                self.cleanup(self.items[index].outputURL)
                self.items[index].outputURL = nil
                self.items[index].outputDescriptor = nil
                self.items[index].savedTo = nil
                self.items[index].stage = .processing
                self.items[index].phase = .rendering
                self.items[index].progress = 0
                self.items[index].statusText = "Rendering video frames…"
                self.statusMessage = "Optimizing \(completed + 1) of \(ready.count) videos…"
                do {
                    let itemID = queued.id
                    let result = try await VideoOptimizePipeline.optimize(sourceURL: queued.sourceURL,
                        settings: snapshot) { fraction in
                            Task { @MainActor [weak self] in
                                guard let self,
                                      let current = self.items.firstIndex(where: { $0.id == itemID }) else { return }
                                self.items[current].progress = fraction
                            }
                        }
                    guard let final = self.items.firstIndex(where: { $0.id == queued.id }) else {
                        self.cleanup(result.outputURL); continue
                    }
                    self.items[final].outputDescriptor = result.descriptor
                    self.items[final].outputURL = result.outputURL
                    self.items[final].outputFileSize = Int64((try? result.outputURL.resourceValues(
                        forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    self.items[final].remainingFindings = result.remainingMetadata
                    self.items[final].stage = .completed
                    self.items[final].phase = .verifying
                    self.items[final].progress = 1
                    let targetNote = result.plan.targetBytes == nil ? "" :
                        " · target \(Self.megabytes(result.plan.targetBytes ?? 0))"
                    self.items[final].statusText = result.metadataVerified
                        ? "Re-encoded and metadata verified\(targetNote)"
                        : "Re-encoded; some metadata could not be removed"
                    self.items[final].errorText = nil
                    completed += 1
                } catch {
                    if let current = self.items.firstIndex(where: { $0.id == queued.id }) {
                        self.items[current].outputDescriptor = nil
                        self.items[current].stage = Task.isCancelled ? .cancelled : .failed
                        self.items[current].errorText = error.localizedDescription
                        self.items[current].statusText = Task.isCancelled
                            ? "Cancelled; original is unchanged" : "Optimization failed"
                        self.items[current].progress = nil
                    }
                    if Task.isCancelled { break }
                }
            }
            self.isProcessing = false
            self.processingTask = nil
            self.statusMessage = Task.isCancelled
                ? "Cancelled; every original is unchanged."
                : "Optimized \(completed) of \(ready.count) video\(ready.count == 1 ? "" : "s")."
        }
    }

    func cancel() { processingTask?.cancel(); statusMessage = "Cancelling…" }

    func clear() {
        processingTask?.cancel(); previewTask?.cancel()
        resetPlayer()
        items.forEach { cleanup($0.outputURL) }
        items.removeAll(); setSelection([], primary: nil); previewSeconds = 0
        statusMessage = nil; isProcessing = false
    }

    func remove(item: VideoQueueItem) {
        cleanup(item.outputURL)
        items.removeAll { $0.id == item.id }
        let retained = selectedIDs.subtracting([item.id]).intersection(Set(items.map(\.id)))
        if retained.isEmpty {
            let next = items.first?.id
            setSelection(next.map { [$0] } ?? [], primary: next)
        } else {
            setSelection(retained,
                         primary: MediaSelection.primaryID(for: retained,
                                                           preferredID: selectedItemID,
                                                           orderedIDs: items.map(\.id)))
        }
        if let primary = selectedItem, primary.id != item.id {
            previewSeconds = max(settings.trimStartSeconds, 0)
            configurePlayer(for: primary.sourceURL)
            seekPreview()
        } else if selectedItem == nil {
            previewSeconds = 0
            resetPlayer()
        }
    }

    func save(item: VideoQueueItem) {
        guard let outputURL = item.outputURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.suggestedFilename(suffix: "optimized",
                                                            extension: outputURL.pathExtension)
        panel.directoryURL = AppSettings.shared.defaultSaveDirectory
        panel.canCreateDirectories = true
        panel.message = "Save the optimized copy of \(item.displayName)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        write(itemID: item.id, outputURL: outputURL, destination: destination)
    }

    func saveAll() {
        let pending = items.filter(\.isSaveReady)
        guard !pending.isEmpty else { return }
        guard let folder = OutputFolderChooser.choose(defaultDirectory: AppSettings.shared.defaultSaveDirectory,
            message: "Choose a folder for \(pending.count) optimized video\(pending.count == 1 ? "" : "s")") else { return }
        var saved = 0
        for item in pending {
            guard let outputURL = item.outputURL else { continue }
            let name = item.suggestedFilename(suffix: "optimized", extension: outputURL.pathExtension)
            let destination = MediaSaveService.uniqueURL(in: folder, filename: name)
            if write(itemID: item.id, outputURL: outputURL, destination: destination) { saved += 1 }
        }
        statusMessage = "Saved \(saved) optimized video\(saved == 1 ? "" : "s") to \(folder.lastPathComponent)."
    }

    private func analyse(ids: Set<UUID>) {
        Task { [weak self] in
            guard let self else { return }
            for queued in self.items where ids.contains(queued.id) {
                guard let index = self.items.firstIndex(where: { $0.id == queued.id }) else { continue }
                self.items[index].stage = .analysing
                self.items[index].statusText = "Reading video details…"
                do {
                    async let poster = VideoPosterGenerator.image(for: queued.sourceURL)
                    let descriptor = try await MediaCapabilityProbe.inspectVideo(at: queued.sourceURL)
                    guard let final = self.items.firstIndex(where: { $0.id == queued.id }) else { continue }
                    self.items[final].descriptor = descriptor
                    self.items[final].poster = await poster
                    self.items[final].stage = .ready
                    self.items[final].statusText = "Ready to optimize"
                } catch {
                    if let final = self.items.firstIndex(where: { $0.id == queued.id }) {
                        self.items[final].stage = .failed
                        self.items[final].errorText = error.localizedDescription
                        self.items[final].statusText = "Unsupported video"
                    }
                }
            }
            self.statusMessage = "Choose settings, then Optimize Selected or Optimize All. Save prepared outputs separately."
        }
    }

    private var sourceDuration: Double? {
        guard let duration = selectedItem?.descriptor?.duration else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    private func clampedPreviewSeconds(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        return min(max(0, seconds), sourceDuration ?? max(0, seconds))
    }

    private func configurePlayer(for sourceURL: URL) {
        resetPlayer()
        let player = AVPlayer(url: sourceURL)
        player.isMuted = isMuted
        self.player = player

        playerTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player] time in
            guard let self, let player else { return }
            MainActor.assumeIsolated {
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite { self.previewSeconds = self.clampedPreviewSeconds(seconds) }
                self.isPlaying = player.rate != 0
            }
        }

        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.isPlaying = false
            }
        }
    }

    private func resetPlayer() {
        player?.pause()
        if let playerTimeObserver, let player {
            player.removeTimeObserver(playerTimeObserver)
        }
        if let playerEndObserver {
            NotificationCenter.default.removeObserver(playerEndObserver)
        }
        playerTimeObserver = nil
        playerEndObserver = nil
        player = nil
        isPlaying = false
        resumesAfterScrubbing = false
    }

    @discardableResult
    private func write(itemID: UUID, outputURL: URL, destination: URL) -> Bool {
        do {
            try MediaSaveService.protectOriginals(
                destination: destination, sourceURLs: items.map(\.sourceURL))
            try MediaSaveService.copyTemporaryOutput(from: outputURL, to: destination)
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { return true }
            items[index].savedTo = destination; items[index].stage = .saved
            cleanup(items[index].outputURL); items[index].outputURL = nil
            return true
        } catch {
            statusMessage = "Could not save \(destination.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    private func cleanup(_ url: URL?) { if let url { try? FileManager.default.removeItem(at: url) } }

    private static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }
}

enum VideoURLExpansion {
    static func expand(urls: [URL]) -> [URL] {
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
}

@MainActor
enum OutputFolderChooser {
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
