import AppKit
import Foundation
import ImageIO

struct TransformItem: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let originalSize: Int

    var outputData: Data?
    var outputSize: Int?
    var outputFormat: ImageOutputFormat?
    var width: Int?
    var height: Int?
    var quality: Int?
    var targetMet = true
    var iterations = 0
    var statusText: String?
    var errorText: String?
    var thumbnail: NSImage?
    var sourceThumbnail: NSImage?
    var savedTo: URL?

    var displayName: String { sourceURL.lastPathComponent }

    func suggestedFilename(extension outputExtension: String) -> String {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        return "\(base)-kechil.\(outputExtension)"
    }
}

@MainActor
final class TransformModel: ObservableObject {
    @Published var items: [TransformItem] = []
    @Published var selectedItemID: UUID?
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published var watermarkPreview: NSImage?
    @Published var watermarkPreviewError: String?
    @Published var isWatermarkPreviewRendering = false
    /// A preview rendered from the current controls for the selected image. This is
    /// deliberately separate from `TransformItem.thumbnail` and `outputData`: changing
    /// a control must never make a stale preview look like a saved/export-ready result.
    @Published private(set) var optimizePreview: NSImage?
    @Published private(set) var optimizePreviewItemID: UUID?
    @Published private(set) var optimizePreviewWidth: Int?
    @Published private(set) var optimizePreviewHeight: Int?
    @Published private(set) var optimizePreviewFormat: ImageOutputFormat?
    @Published private(set) var optimizePreviewQuality: Int?
    @Published private(set) var optimizePreviewStatus: String?
    @Published private(set) var optimizePreviewError: String?
    @Published private(set) var isOptimizePreviewRendering = false

    // These values form a snapshot when processing begins. Changing a control never
    // silently changes an already-rendered image; the user must choose Apply again.
    @Published var cropAspect: CropAspect = .original
    @Published var cropFocusX = 0.5
    @Published var cropFocusY = 0.5
    @Published var resizeMode: ResizeMode = .none
    @Published var resizeValue = 1600.0
    @Published var dontUpscale = true
    @Published var outputFormat: ImageOutputFormat = .webp
    @Published var qualityFloor = 60.0
    @Published var qualityCeiling = 82.0
    @Published var targetKilobytes = 0.0
    @Published var webPLossless = false
    @Published var webPMethod = 4.0
    @Published var watermarkKind: WatermarkKind = .text
    @Published var watermarkText = "© Kechil PRO"
    @Published var watermarkLogoData: Data?
    @Published var watermarkLogoName: String?
    @Published var watermarkOpacity = 0.45
    @Published var watermarkRotation = WatermarkDefaults.rotationDegrees
    @Published var watermarkScalePercent = 8.0
    @Published var watermarkPosition: WatermarkPosition = .bottomRight
    @Published var watermarkTiled = false
    @Published var watermarkTextColor = RGBAColor.white
    @Published var watermarkMarginPercent = 2.5
    @Published var watermarkTileGapPercent = 6.5
    @Published var watermarkShadowEnabled = true
    @Published var watermarkShadowOpacity = 0.45
    @Published private(set) var watermarkPresetNames: [String] = []
    @Published var selectedWatermarkPreset = ""

    private let watermarkMode: Bool
    private var watermarkPreviewTask: Task<Void, Never>?
    private var optimizePreviewTask: Task<Void, Never>?
    private var optimizePreviewGeneration = 0
    private static let watermarkPresetKey = "kechil.watermarkPresets.v1"

    private let acceptedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "webp", "heic", "heif", "tif", "tiff",
        "gif", "bmp", "avif", "dng",
    ]

    var completedCount: Int { items.filter { $0.outputData != nil }.count }
    var pendingCount: Int { items.filter { $0.outputData == nil && $0.savedTo == nil }.count }
    var selectedItem: TransformItem? {
        guard let selectedItemID else { return items.first }
        return items.first { $0.id == selectedItemID }
    }

    init(watermarkMode: Bool = false) {
        self.watermarkMode = watermarkMode
        refreshWatermarkPresetNames()
    }

    func add(urls: [URL]) {
        let extensions = acceptedExtensions
        statusMessage = "Loading images…"

        Task { [weak self] in
            // Folder enumeration and resource-value reads can block on File Provider
            // or external volumes. More importantly, the old intake path read every
            // complete image and decoded a 1200 px thumbnail on the main actor, then
            // `process(item:settings:)` immediately read the same file again. Queue
            // lightweight records off-main and let the existing detached processor
            // produce both source and output thumbnails from its single source read.
            let newItems = await Task.detached(priority: .userInitiated) {
                Self.expand(urls: urls, acceptedExtensions: extensions).map { url in
                    TransformItem(sourceURL: url, originalSize: Self.fileSize(of: url))
                }
            }.value

            guard let self else { return }
            guard !newItems.isEmpty else {
                self.statusMessage = "No supported images found."
                return
            }
            self.items.append(contentsOf: newItems)
            if self.selectedItemID == nil { self.selectedItemID = newItems.first?.id }
            if self.watermarkMode { self.refreshWatermarkPreview() }
            self.process(itemIDs: Set(newItems.map(\.id)))
        }
    }

    func reprocessAll() {
        guard !items.isEmpty else { return }
        process(itemIDs: Set(items.map(\.id)))
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = watermarkMode ? "Choose image files to watermark" : "Choose image files to optimize"
        guard panel.runModal() == .OK else { return }
        add(urls: panel.urls)
    }

    func chooseWatermarkLogo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a logo image for the watermark"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            watermarkLogoData = try Data(contentsOf: url)
            watermarkLogoName = url.lastPathComponent
        } catch {
            statusMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func saveWatermarkPreset() {
        let alert = NSAlert()
        alert.messageText = "Save watermark preset"
        alert.informativeText = "Presets keep watermark and export settings only. They never keep image paths, queued files or logo bytes."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        field.placeholderString = "Preset name"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var presets = storedWatermarkPresets
        presets[name] = WatermarkPreset(kind: watermarkKind.rawValue,
                                        text: watermarkText,
                                        opacity: watermarkOpacity,
                                        rotation: watermarkRotation,
                                        scalePercent: watermarkScalePercent,
                                        position: watermarkPosition.rawValue,
                                        tiled: watermarkTiled,
                                        textColor: watermarkTextColor,
                                        marginPercent: watermarkMarginPercent,
                                        tileGapPercent: watermarkTileGapPercent,
                                        shadowEnabled: watermarkShadowEnabled,
                                        shadowOpacity: watermarkShadowOpacity,
                                        outputFormat: outputFormat.rawValue,
                                        qualityFloor: qualityFloor,
                                        qualityCeiling: qualityCeiling,
                                        targetKilobytes: targetKilobytes,
                                        webPLossless: webPLossless,
                                        webPMethod: webPMethod)
        persistWatermarkPresets(presets)
        selectedWatermarkPreset = name
        statusMessage = "Saved watermark preset “\(name)”."
    }

    func applyWatermarkPreset(named name: String) {
        guard let preset = storedWatermarkPresets[name] else { return }
        watermarkKind = WatermarkKind(rawValue: preset.kind) ?? .text
        watermarkText = preset.text
        watermarkOpacity = preset.opacity
        watermarkRotation = preset.rotation
        watermarkScalePercent = preset.scalePercent
        watermarkPosition = WatermarkPosition(rawValue: preset.position) ?? .bottomRight
        watermarkTiled = preset.tiled
        watermarkTextColor = preset.textColor ?? .white
        watermarkMarginPercent = preset.marginPercent ?? 2.5
        watermarkTileGapPercent = preset.tileGapPercent ?? 6.5
        watermarkShadowEnabled = preset.shadowEnabled ?? true
        watermarkShadowOpacity = preset.shadowOpacity ?? 0.45
        outputFormat = ImageOutputFormat(rawValue: preset.outputFormat) ?? .webp
        qualityFloor = preset.qualityFloor
        qualityCeiling = preset.qualityCeiling
        targetKilobytes = preset.targetKilobytes
        webPLossless = preset.webPLossless
        webPMethod = preset.webPMethod
        selectedWatermarkPreset = name
        if watermarkKind == .logo && watermarkLogoData == nil {
            statusMessage = "Preset “\(name)” selected. Choose its logo again; logo bytes are never stored in presets."
        } else {
            statusMessage = "Preset “\(name)” selected."
        }
    }

    func deleteSelectedWatermarkPreset() {
        guard !selectedWatermarkPreset.isEmpty else { return }
        var presets = storedWatermarkPresets
        presets.removeValue(forKey: selectedWatermarkPreset)
        persistWatermarkPresets(presets)
        selectedWatermarkPreset = ""
        statusMessage = "Deleted watermark preset."
    }

    func clear() {
        watermarkPreviewTask?.cancel()
        optimizePreviewTask?.cancel()
        optimizePreviewGeneration &+= 1
        items.removeAll()
        selectedItemID = nil
        watermarkPreview = nil
        watermarkPreviewError = nil
        clearOptimizePreview()
        statusMessage = nil
    }

    func remove(item: TransformItem) {
        items.removeAll { $0.id == item.id }
        if selectedItemID == item.id {
            selectedItemID = items.first?.id
            clearOptimizePreview()
        }
        if watermarkMode { refreshWatermarkPreview() }
    }

    func select(_ item: TransformItem) {
        selectedItemID = item.id
        if watermarkMode {
            refreshWatermarkPreview()
        } else {
            // A preview belongs to one source and one settings snapshot. Do not show
            // the previous selection while the new selection is being inspected.
            clearOptimizePreview()
        }
    }

    /// Re-renders only the selected image after a control changes. The short debounce
    /// keeps slider drags responsive while avoiding one full encode per mouse event.
    /// Queue items and their export data remain untouched until Apply to All is pressed.
    func refreshOptimizePreview() {
        guard !watermarkMode else { return }
        optimizePreviewTask?.cancel()
        optimizePreviewGeneration &+= 1
        let generation = optimizePreviewGeneration
        guard let selected = selectedItem else {
            clearOptimizePreview()
            return
        }

        let settings = snapshot
        optimizePreviewItemID = selected.id
        optimizePreviewError = nil
        optimizePreviewStatus = nil
        isOptimizePreviewRendering = true
        optimizePreviewTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 140_000_000)
                try Task.checkCancellation()
                let output = try await Task.detached(priority: .userInitiated) {
                    let source = try Data(contentsOf: selected.sourceURL)
                    return try TransformPipeline.process(source, settings: settings)
                }.value
                try Task.checkCancellation()
                let image = Self.thumbnail(from: output.data, maxSide: 1200)
                guard let self,
                      self.optimizePreviewGeneration == generation,
                      self.selectedItemID == selected.id else { return }
                guard let image else {
                    self.optimizePreview = nil
                    self.optimizePreviewError = "Could not create the optimized preview"
                    self.isOptimizePreviewRendering = false
                    return
                }
                self.optimizePreview = image
                self.optimizePreviewWidth = output.width
                self.optimizePreviewHeight = output.height
                self.optimizePreviewFormat = settings.outputFormat
                self.optimizePreviewQuality = output.quality
                self.optimizePreviewStatus = output.statusText
                self.optimizePreviewError = nil
                self.isOptimizePreviewRendering = false
            } catch is CancellationError {
                // A newer settings change owns the next preview state.
            } catch {
                guard let self,
                      self.optimizePreviewGeneration == generation,
                      self.selectedItemID == selected.id else { return }
                self.optimizePreviewError = error.localizedDescription
                self.isOptimizePreviewRendering = false
            }
        }
    }

    private func clearOptimizePreview() {
        optimizePreviewTask?.cancel()
        optimizePreview = nil
        optimizePreviewItemID = nil
        optimizePreviewWidth = nil
        optimizePreviewHeight = nil
        optimizePreviewFormat = nil
        optimizePreviewQuality = nil
        optimizePreviewStatus = nil
        optimizePreviewError = nil
        isOptimizePreviewRendering = false
    }

    func refreshWatermarkPreview() {
        guard watermarkMode else { return }
        watermarkPreviewTask?.cancel()
        guard let selected = selectedItem else {
            watermarkPreview = nil
            watermarkPreviewError = nil
            return
        }
        let configuration = watermarkConfiguration
        let logoData = watermarkLogoData
        isWatermarkPreviewRendering = true
        watermarkPreviewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                let cgImage = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: selected.sourceURL)
                    return try WatermarkRenderer.preview(sourceData: data,
                        configuration: configuration, logoData: logoData)
                }.value
                guard !Task.isCancelled, self.selectedItemID == selected.id else { return }
                self.watermarkPreview = NSImage(cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height))
                self.watermarkPreviewError = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.watermarkPreview = nil
                self.watermarkPreviewError = error.localizedDescription
            }
            self.isWatermarkPreviewRendering = false
        }
    }

    var watermarkConfiguration: WatermarkConfiguration {
        WatermarkConfiguration(source: watermarkKind == .text ? .text(watermarkText) : .logo,
                               textColor: watermarkTextColor,
                               opacity: watermarkOpacity,
                               rotationDegrees: watermarkRotation,
                               scalePercentOfShortestEdge: watermarkScalePercent,
                               anchor: watermarkPosition,
                               marginPercent: watermarkMarginPercent,
                               tiled: watermarkTiled,
                               tileGapPercent: watermarkTileGapPercent,
                               shadowEnabled: watermarkShadowEnabled,
                               shadowOpacity: watermarkShadowOpacity)
    }

    func save(item: TransformItem) {
        guard let data = item.outputData else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.suggestedFilename(
            extension: (item.outputFormat ?? outputFormat).fileExtension)
        panel.directoryURL = AppSettings.shared.defaultSaveDirectory
        panel.canCreateDirectories = true
        panel.message = "Save the converted copy of \(item.displayName)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(data, to: url, itemID: item.id)
    }

    func saveAll() {
        let pending = items.filter { $0.outputData != nil }
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
            panel.message = "Choose a folder for \(pending.count) converted image\(pending.count == 1 ? "" : "s")"
            guard panel.runModal() == .OK, let selected = panel.url else { return }
            folder = selected
        }

        var written = 0
        for item in pending {
            guard let data = item.outputData else { continue }
            let url = uniqueURL(in: folder,
                                filename: item.suggestedFilename(
                                    extension: (item.outputFormat ?? outputFormat).fileExtension))
            if write(data, to: url, itemID: item.id) { written += 1 }
        }
        statusMessage = "Saved \(written) image\(written == 1 ? "" : "s") to \(folder.lastPathComponent)."
    }

    private func process(itemIDs: Set<UUID>) {
        guard !isProcessing else {
            statusMessage = "Current batch is still processing. Apply the new settings when it finishes."
            return
        }
        let queued = items.filter { itemIDs.contains($0.id) }
        guard !queued.isEmpty else { return }
        let settings = snapshot
        isProcessing = true
        statusMessage = "Processing \(queued.count) image\(queued.count == 1 ? "" : "s")…"

        Task {
            // Deliberately one image at a time: Core Image and the codec can each hold a
            // full decoded raster, so unbounded concurrency would turn a folder drop into
            // an avoidable memory spike. This is a bounded batch (one active render).
            for item in queued {
                let result = await Self.process(item: item, settings: settings)
                guard let index = self.items.firstIndex(where: { $0.id == result.id }) else { continue }
                self.items[index] = result
            }
            self.isProcessing = false
            let successes = queued.filter { id in
                self.items.first(where: { $0.id == id.id })?.outputData != nil
            }.count
            self.statusMessage = "Converted \(successes) of \(queued.count) image\(queued.count == 1 ? "" : "s")."
        }
    }

    private var snapshot: TransformSettingsSnapshot {
        TransformSettingsSnapshot(cropAspect: cropAspect,
                                  cropFocusX: cropFocusX, cropFocusY: cropFocusY,
                                  resizeMode: resizeMode, resizeValue: resizeValue,
                                  dontUpscale: dontUpscale,
                                  outputFormat: outputFormat,
                                  qualityFloor: Int(qualityFloor.rounded()),
                                  qualityCeiling: Int(qualityCeiling.rounded()),
                                  targetBytes: targetKilobytes > 0
                                      ? Int((targetKilobytes * 1024).rounded()) : nil,
                                  webPLossless: webPLossless,
                                  webPMethod: Int(webPMethod.rounded()),
                                  watermark: watermarkMode ? WatermarkSettings(
                                      kind: watermarkKind, text: watermarkText,
                                      logoData: watermarkLogoData,
                                      opacity: watermarkOpacity,
                                      rotationDegrees: watermarkRotation,
                                      scalePercent: watermarkScalePercent,
                                      position: watermarkPosition,
                                      tiled: watermarkTiled,
                                      textColor: watermarkTextColor,
                                      marginPercent: watermarkMarginPercent,
                                      tileGapPercent: watermarkTileGapPercent,
                                      shadowEnabled: watermarkShadowEnabled,
                                      shadowOpacity: watermarkShadowOpacity) : nil)
    }

    private static func process(item: TransformItem,
                                settings: TransformSettingsSnapshot) async -> TransformItem {
        await Task.detached(priority: .userInitiated) { () -> TransformItem in
            var result = item
            do {
                let source = try Data(contentsOf: item.sourceURL)
                let output = try TransformPipeline.process(source, settings: settings)
                result.outputData = output.data
                result.outputSize = output.data.count
                result.outputFormat = settings.outputFormat
                result.width = output.width
                result.height = output.height
                result.quality = output.quality
                result.targetMet = output.targetMet
                result.iterations = output.iterations
                result.statusText = output.statusText
                result.errorText = nil
                result.savedTo = nil
                result.thumbnail = thumbnail(from: output.data)
                if result.sourceThumbnail == nil { result.sourceThumbnail = thumbnail(from: source, maxSide: 1200) }
            } catch {
                result.outputData = nil
                result.outputSize = nil
                result.errorText = error.localizedDescription
                result.statusText = nil
                result.thumbnail = thumbnail(from: (try? Data(contentsOf: item.sourceURL)) ?? Data())
                if result.sourceThumbnail == nil { result.sourceThumbnail = result.thumbnail }
            }
            return result
        }.value
    }

    nonisolated private static func thumbnail(from data: Data, maxSide: Int = 160) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    nonisolated private static func expand(urls: [URL],
                                           acceptedExtensions: Set<String>) -> [URL] {
        var result: [URL] = []
        let manager = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let enumerator = manager.enumerator(at: url,
                                                    includingPropertiesForKeys: [.isRegularFileKey],
                                                    options: [.skipsHiddenFiles])
                while let child = enumerator?.nextObject() as? URL {
                    if acceptedExtensions.contains(child.pathExtension.lowercased()) { result.append(child) }
                }
            } else if acceptedExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result
    }

    nonisolated private static func fileSize(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    @discardableResult
    private func write(_ data: Data, to url: URL, itemID: UUID) -> Bool {
        do {
            try MediaSaveService.protectOriginals(
                destination: url, sourceURLs: items.map(\.sourceURL))
            try data.write(to: url, options: .atomic)
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index].savedTo = url
                items[index].outputData = nil
            }
            return true
        } catch {
            statusMessage = "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    private func uniqueURL(in folder: URL, filename: String) -> URL {
        let manager = FileManager.default
        var candidate = folder.appendingPathComponent(filename)
        guard manager.fileExists(atPath: candidate.path) else { return candidate }
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var number = 2
        repeat {
            let name = ext.isEmpty ? "\(base)-\(number)" : "\(base)-\(number).\(ext)"
            candidate = folder.appendingPathComponent(name)
            number += 1
        } while manager.fileExists(atPath: candidate.path) && number < 1000
        return candidate
    }

    private var storedWatermarkPresets: [String: WatermarkPreset] {
        guard let data = UserDefaults.standard.data(forKey: Self.watermarkPresetKey),
              let presets = try? JSONDecoder().decode([String: WatermarkPreset].self, from: data) else {
            return [:]
        }
        return presets
    }

    private func persistWatermarkPresets(_ presets: [String: WatermarkPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.watermarkPresetKey)
        }
        refreshWatermarkPresetNames()
    }

    private func refreshWatermarkPresetNames() {
        watermarkPresetNames = storedWatermarkPresets.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}

/// Stored under one versioned UserDefaults key. This intentionally excludes logo data,
/// image URLs and every queue/result field: presets are reusable settings, never a log
/// of the user's files or a hidden copy of their branding asset.
private struct WatermarkPreset: Codable {
    let kind: String
    let text: String
    let opacity: Double
    let rotation: Double
    let scalePercent: Double
    let position: String
    let tiled: Bool
    let textColor: RGBAColor?
    let marginPercent: Double?
    let tileGapPercent: Double?
    let shadowEnabled: Bool?
    let shadowOpacity: Double?
    let outputFormat: String
    let qualityFloor: Double
    let qualityCeiling: Double
    let targetKilobytes: Double
    let webPLossless: Bool
    let webPMethod: Double

}
