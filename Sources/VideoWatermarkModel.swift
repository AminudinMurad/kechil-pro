import AppKit
import AVFoundation
import Foundation

@MainActor
final class VideoWatermarkModel: ObservableObject {
    @Published var items: [VideoQueueItem] = []
    @Published var selectedItemID: UUID?
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published var previewSeconds = 0.0
    @Published var previewOverlay: NSImage?
    @Published var previewError: String?
    @Published var isPreviewRendering = false
    @Published var player: AVPlayer?

    @Published var kind: WatermarkKind = .text
    @Published var text = "© Kechil PRO"
    @Published var logoData: Data?
    @Published var logoName: String?
    @Published var opacity = 0.45
    @Published var rotation = WatermarkDefaults.rotationDegrees
    @Published var scalePercent = 8.0
    @Published var position: WatermarkPosition = .bottomRight
    @Published var tiled = false
    @Published var textColor = RGBAColor.white
    @Published var marginPercent = 2.5
    @Published var tileGapPercent = 6.5
    @Published var shadowEnabled = true
    @Published var shadowOpacity = 0.45
    @Published var codec: VideoCodecChoice = .h264
    @Published var audioPolicy: VideoAudioPolicy = .keep
    @Published var container: VideoContainerChoice = .mp4
    @Published var quality = 0.82

    private var processingTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    var selectedItem: VideoQueueItem? {
        guard let selectedItemID else { return items.first }
        return items.first { $0.id == selectedItemID }
    }
    var completedCount: Int { items.filter(\.isSaveReady).count }
    var configuration: WatermarkConfiguration {
        WatermarkConfiguration(source: kind == .text ? .text(text) : .logo,
            textColor: textColor, opacity: opacity, rotationDegrees: rotation,
            scalePercentOfShortestEdge: scalePercent, anchor: position,
            marginPercent: marginPercent, tiled: tiled, tileGapPercent: tileGapPercent,
            shadowEnabled: shadowEnabled, shadowOpacity: shadowOpacity)
    }
    var settings: VideoWatermarkSettings {
        VideoWatermarkSettings(configuration: configuration, logoData: logoData,
                               codec: codec, audioPolicy: audioPolicy,
                               container: container, quality: quality)
    }
    var canApply: Bool {
        !items.isEmpty && !isProcessing && (kind == .text ? !text.trimmingCharacters(
            in: .whitespacesAndNewlines).isEmpty : logoData != nil)
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.message = "Choose MOV, MP4 or M4V videos to watermark"
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
        if selectedItemID == nil { select(newItems[0]) }
        analyse(ids: Set(newItems.map(\.id)))
    }

    func select(_ item: VideoQueueItem) {
        selectedItemID = item.id
        previewSeconds = 0
        player?.pause()
        player = AVPlayer(url: item.sourceURL)
        refreshPreviewOverlay()
    }

    func chooseLogo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a PNG, JPEG, WebP or HEIC logo"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            logoData = try Data(contentsOf: url)
            _ = try WatermarkRenderer.decodeLogo(logoData ?? Data())
            logoName = url.lastPathComponent
            refreshPreviewOverlay()
        } catch {
            logoData = nil; logoName = nil
            statusMessage = "Could not read that logo: \(error.localizedDescription)"
        }
    }

    func refreshPreviewOverlay() {
        previewTask?.cancel()
        guard let descriptor = selectedItem?.descriptor,
              let width = descriptor.displayWidth, let height = descriptor.displayHeight else { return }
        let currentConfiguration = configuration
        let currentLogoData = logoData
        isPreviewRendering = true
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                let maximum: CGFloat = 1280
                let scale = min(1, maximum / CGFloat(max(width, height)))
                let canvas = CGSize(width: max(2, CGFloat(width) * scale),
                                    height: max(2, CGFloat(height) * scale))
                let cgImage = try await Task.detached(priority: .userInitiated) {
                    let logo = try currentLogoData.map(WatermarkRenderer.decodeLogo)
                    return try WatermarkRenderer.renderOverlay(configuration: currentConfiguration,
                                                                canvasSize: canvas, logo: logo)
                }.value
                guard !Task.isCancelled else { return }
                self.previewOverlay = NSImage(cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height))
                self.previewError = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.previewOverlay = nil
                self.previewError = error.localizedDescription
            }
            self.isPreviewRendering = false
        }
    }

    func seekPreview() {
        player?.seek(to: CMTime(seconds: max(0, previewSeconds), preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlayback() {
        guard let player else { return }
        if player.rate == 0 { player.play() } else { player.pause() }
    }

    func applyAll() {
        guard canApply else { return }
        let ready = items.filter { $0.descriptor != nil }
        let snapshot = settings
        processingTask = Task { [weak self] in
            guard let self else { return }
            self.player?.pause()
            self.isProcessing = true
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
                self.items[index].statusText = "Rendering watermark across all frames…"
                self.statusMessage = "Watermarking \(completed + 1) of \(ready.count) videos…"
                do {
                    let itemID = queued.id
                    let result = try await VideoWatermarkPipeline.apply(sourceURL: queued.sourceURL,
                        settings: snapshot) { fraction in
                            Task { @MainActor [weak self] in
                                guard let self, let current = self.items.firstIndex(
                                    where: { $0.id == itemID }) else { return }
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
                    self.items[final].statusText = result.metadataVerified
                        ? "Watermark rendered; metadata verified" :
                          "Watermark rendered; some metadata remains"
                    self.items[final].errorText = nil
                    completed += 1
                } catch {
                    if let current = self.items.firstIndex(where: { $0.id == queued.id }) {
                        self.items[current].outputDescriptor = nil
                        self.items[current].stage = Task.isCancelled ? .cancelled : .failed
                        self.items[current].statusText = Task.isCancelled ?
                            "Cancelled; original is unchanged" : "Watermark export failed"
                        self.items[current].errorText = error.localizedDescription
                        self.items[current].progress = nil
                    }
                    if Task.isCancelled { break }
                }
            }
            self.isProcessing = false
            self.processingTask = nil
            self.statusMessage = Task.isCancelled ? "Cancelled; every original is unchanged." :
                "Watermarked \(completed) of \(ready.count) video\(ready.count == 1 ? "" : "s")."
        }
    }

    func cancel() { processingTask?.cancel(); statusMessage = "Cancelling…" }

    func clear() {
        processingTask?.cancel(); previewTask?.cancel(); player?.pause()
        items.forEach { cleanup($0.outputURL) }
        items.removeAll(); selectedItemID = nil; player = nil; previewOverlay = nil
        statusMessage = nil; isProcessing = false
    }

    func remove(item: VideoQueueItem) {
        cleanup(item.outputURL)
        items.removeAll { $0.id == item.id }
        if selectedItemID == item.id {
            if let first = items.first { select(first) }
            else { selectedItemID = nil; player = nil; previewOverlay = nil }
        }
    }

    func save(item: VideoQueueItem) {
        guard let outputURL = item.outputURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.suggestedFilename(suffix: "watermarked",
                                                            extension: outputURL.pathExtension)
        panel.directoryURL = AppSettings.shared.defaultSaveDirectory
        panel.canCreateDirectories = true
        panel.message = "Save the watermarked copy of \(item.displayName)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        write(itemID: item.id, outputURL: outputURL, destination: destination)
    }

    func saveAll() {
        let pending = items.filter(\.isSaveReady)
        guard !pending.isEmpty else { return }
        guard let folder = OutputFolderChooser.choose(defaultDirectory: AppSettings.shared.defaultSaveDirectory,
            message: "Choose a folder for \(pending.count) watermarked video\(pending.count == 1 ? "" : "s")") else { return }
        var saved = 0
        for item in pending {
            guard let outputURL = item.outputURL else { continue }
            let name = item.suggestedFilename(suffix: "watermarked", extension: outputURL.pathExtension)
            let destination = MediaSaveService.uniqueURL(in: folder, filename: name)
            if write(itemID: item.id, outputURL: outputURL, destination: destination) { saved += 1 }
        }
        statusMessage = "Saved \(saved) watermarked video\(saved == 1 ? "" : "s") to \(folder.lastPathComponent)."
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
                    self.items[final].statusText = "Ready to watermark"
                    if self.selectedItemID == queued.id {
                        self.refreshPreviewOverlay()
                    }
                } catch {
                    if let final = self.items.firstIndex(where: { $0.id == queued.id }) {
                        self.items[final].stage = .failed
                        self.items[final].errorText = error.localizedDescription
                        self.items[final].statusText = "Unsupported video"
                    }
                }
            }
            self.statusMessage = "Preview the watermark, then apply it to the queue."
        }
    }

    @discardableResult
    private func write(itemID: UUID, outputURL: URL, destination: URL) -> Bool {
        do {
            try MediaSaveService.protectOriginals(
                destination: destination, sourceURLs: items.map(\.sourceURL))
            try MediaSaveService.copyTemporaryOutput(from: outputURL, to: destination)
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index].savedTo = destination; items[index].stage = .saved
                cleanup(items[index].outputURL); items[index].outputURL = nil
            }
            return true
        } catch {
            statusMessage = "Could not save \(destination.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    private func cleanup(_ url: URL?) { if let url { try? FileManager.default.removeItem(at: url) } }
}
