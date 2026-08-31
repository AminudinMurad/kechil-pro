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
    var sourceWidth: Int?
    var sourceHeight: Int?
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
    @Published var selectedItemID: UUID? {
        didSet {
            guard !selectionMutationInProgress else { return }
            selectedItemIDs = selectedItemID.map { [$0] } ?? []
            selectionAnchorID = selectedItemID
        }
    }
    @Published private(set) var selectedItemIDs: Set<UUID> = []
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
    /// Live size for the selected image using the full Watermark image encoder.
    /// It is intentionally separate from queue output so changing a control
    /// never silently replaces an already prepared result.
    @Published private(set) var watermarkSizeEstimate: MediaSizeEstimate?
    @Published private(set) var watermarkSizeEstimateItemID: UUID?
    @Published private(set) var isWatermarkSizeEstimating = false
    @Published private(set) var watermarkSizeEstimateError: String?

    // These values form a snapshot when processing begins. Changing a control never
    // silently changes an already-rendered image; the user must choose Apply again.
    @Published var cropAspect: CropAspect = .original
    @Published var cropFocusX = 0.5
    @Published var cropFocusY = 0.5
    @Published var cropWidth = 0.0
    @Published var cropHeight = 0.0
    /// Controls whether a custom crop may enlarge a smaller queued source before
    /// cropping. This is intentionally independent from Resize's output policy.
    @Published var cropUpscalePolicy: ImageCropUpscalePolicy = .keepNative
    @Published var resizeMode: ResizeMode = .none
    @Published var resizeValue = 100.0
    /// A positive, plain-language setting that maps directly to the visible checkbox.
    @Published var allowsUpscaling = ImageResizePolicy.allowsUpscalingByDefault
    /// Custom crop sizes remain independent unless the user explicitly links them.
    @Published var locksCustomCropAspect = false {
        didSet {
            if locksCustomCropAspect && !oldValue {
                // Capture once. Browsing another image must not change the batch ratio.
                if let width = selectedItem?.sourceWidth,
                   let height = selectedItem?.sourceHeight, width > 0, height > 0 {
                    linkedCropRatio = Double(width) / Double(height)
                } else if let target = customCropTargetSize {
                    linkedCropRatio = Double(target.width / target.height)
                }
                setCropDimension(isWidth: true, value: cropWidth)
            } else if !locksCustomCropAspect {
                linkedCropRatio = nil
            }
        }
    }
    private var linkedCropRatio: Double?
    @Published var outputFormat: ImageOutputFormat = .webp
    @Published var qualityFloor = 60.0
    @Published var qualityCeiling = 82.0
    @Published var targetKilobytes = 0.0
    @Published var webPLossless = false
    @Published var webPMethod = 4.0
    @Published var watermarkKind: WatermarkKind = .text {
        didSet {
            guard watermarkKind != oldValue else { return }
            let next = watermarkAppearances.switching(from: oldValue, to: watermarkKind,
                current: WatermarkAppearance(opacity: watermarkOpacity, rotation: watermarkRotation,
                    scalePercent: watermarkScalePercent, position: watermarkPosition,
                    marginPercent: watermarkMarginPercent))
            watermarkOpacity = next.opacity
            watermarkRotation = next.rotation
            watermarkScalePercent = next.scalePercent
            watermarkPosition = next.position
            watermarkMarginPercent = next.marginPercent
        }
    }
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
    private var watermarkAppearances = WatermarkAppearanceProfiles()
    private var watermarkPreviewTask: Task<Void, Never>?
    private var optimizePreviewTask: Task<Void, Never>?
    private var optimizePreviewGeneration = 0
    private var watermarkSizeEstimateTask: Task<Void, Never>?
    private var watermarkSizeEstimateGeneration = 0
    private var selectionAnchorID: UUID?
    private var selectionMutationInProgress = false
    private static let watermarkPresetKey = "kechil.watermarkPresets.v1"

    private let acceptedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "webp", "heic", "heif", "tif", "tiff",
        "gif", "bmp", "avif", "dng",
    ]

    var completedCount: Int { items.filter { $0.outputData != nil }.count }
    var pendingCount: Int { items.filter { $0.outputData == nil && $0.savedTo == nil }.count }
    var selectedItem: TransformItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    var selectedIDs: Set<UUID> {
        let validIDs = Set(items.map(\.id))
        let current = selectedItemIDs.intersection(validIDs)
        if !current.isEmpty { return current }
        if let selectedItemID, validIDs.contains(selectedItemID) { return [selectedItemID] }
        return []
    }

    var selectedItems: [TransformItem] {
        let ids = selectedIDs
        return items.filter { ids.contains($0.id) }
    }

    var selectedItemCount: Int { selectedIDs.count }
    var selectedSaveItems: [TransformItem] { selectedItems.filter { $0.outputData != nil } }
    var selectedSaveCount: Int { selectedSaveItems.count }
    func isSelected(_ item: TransformItem) -> Bool { selectedIDs.contains(item.id) }

    private func setSelection(_ ids: Set<UUID>, primary: UUID?) {
        selectionMutationInProgress = true
        selectedItemIDs = ids
        selectedItemID = primary
        selectionMutationInProgress = false
        selectionAnchorID = primary
    }

    /// A compact value used by the view to invalidate the estimate whenever a
    /// watermark or output control changes. Logo data itself is observed by the
    /// dedicated published property; the name and byte count make the key useful
    /// for a changed logo as well.
    var watermarkEstimateSettingsKey: String {
        [
            watermarkKind.rawValue, watermarkText, watermarkLogoName ?? "",
            "\(watermarkLogoData?.count ?? 0)",
            String(format: "%.4f", watermarkOpacity),
            String(format: "%.2f", watermarkRotation),
            String(format: "%.2f", watermarkScalePercent),
            watermarkPosition.rawValue, "\(watermarkTiled)",
            String(format: "%.4f", watermarkTextColor.red),
            String(format: "%.4f", watermarkTextColor.green),
            String(format: "%.4f", watermarkTextColor.blue),
            String(format: "%.4f", watermarkTextColor.alpha),
            String(format: "%.4f", watermarkMarginPercent),
            String(format: "%.4f", watermarkTileGapPercent),
            "\(watermarkShadowEnabled)",
            String(format: "%.4f", watermarkShadowOpacity),
            outputFormat.rawValue, "\(webPLossless)",
            String(format: "%.2f", qualityFloor),
            String(format: "%.2f", qualityCeiling),
            String(format: "%.2f", targetKilobytes),
            String(format: "%.2f", webPMethod),
        ].joined(separator: "|")
    }

    /// The requested custom crop target, normalized the same way as the geometry
    /// contract. Unlike the old selected-source clamp, this remains stable across a
    /// batch so one small image cannot silently change the target for every image.
    var customCropTargetSize: CGSize? {
        guard cropAspect == .custom,
              cropWidth.isFinite, cropHeight.isFinite,
              cropWidth > 0, cropHeight > 0 else { return nil }
        return CGSize(width: max(1, cropWidth.rounded()),
                      height: max(1, cropHeight.rounded()))
    }

    /// Number of queued images for which source dimensions are available. This is
    /// kept separate from `knownSmallerCropCount` so the UI can distinguish “none
    /// are smaller” from “dimensions are still being read”.
    var knownCropSourceCount: Int {
        items.filter { item in
            guard let width = item.sourceWidth, let height = item.sourceHeight else {
                return false
            }
            return width > 0 && height > 0
        }.count
    }

    /// Number of known source images that cannot cover the requested custom crop
    /// without enlargement in at least one dimension.
    var knownSmallerCropCount: Int {
        guard let target = customCropTargetSize else { return 0 }
        return items.filter { item in
            guard let width = item.sourceWidth, let height = item.sourceHeight,
                  width > 0, height > 0 else { return false }
            return CGFloat(width) < target.width || CGFloat(height) < target.height
        }.count
    }

    func setCropDimension(isWidth: Bool, value: Double) {
        guard value.isFinite, value > 0 else { return }
        let dimension = max(1, value.rounded())
        if isWidth { cropWidth = dimension } else { cropHeight = dimension }
        guard locksCustomCropAspect else { return }
        if linkedCropRatio == nil, let target = customCropTargetSize {
            linkedCropRatio = Double(target.width / target.height)
        }
        guard let ratio = linkedCropRatio, ratio.isFinite, ratio > 0 else { return }
        if isWidth { cropHeight = max(1, (dimension / ratio).rounded()) }
        else { cropWidth = max(1, (dimension * ratio).rounded()) }
    }

    var batchCropImpactSummary: String {
        guard customCropTargetSize != nil else { return "" }
        guard !items.isEmpty else { return "Add images to see batch impact." }
        let known = knownCropSourceCount
        let smaller = knownSmallerCropCount
        let unknown = items.count - known
        var summary: String
        if known == 0 {
            summary = "Source dimensions are not available yet."
        } else if smaller == 0 {
            summary = "All \(known) checked images cover the crop target."
        } else {
            let outcome = cropUpscalePolicy == .fillTarget
                ? "will be enlarged before crop" : "will keep a smaller crop"
            summary = "\(smaller) of \(known) checked images \(outcome)."
        }
        if unknown > 0 && known > 0 {
            summary += " \(unknown) source sizes unavailable."
        }
        return summary
    }

    /// A prediction for the current controls, never a claim about an existing export.
    func cropPrediction(for item: TransformItem) -> String? {
        guard let target = customCropTargetSize,
              let width = item.sourceWidth, let height = item.sourceHeight,
              width > 0, height > 0 else { return nil }
        let source = CGSize(width: width, height: height)
        let crop = ImageCropGeometry.cropSize(source: source, aspect: nil,
            customSize: target, cropUpscalePolicy: cropUpscalePolicy)
        let scale = ImageCropGeometry.cropUpscaleScale(source: source,
            customSize: target, policy: cropUpscalePolicy)
        let action = scale > 1 ? String(format: "enlarge %.2f×", Double(scale))
            : (crop.width < target.width || crop.height < target.height ? "below target" : "native pixels")
        return "Next crop: \(Int(crop.width)) × \(Int(crop.height)) · \(action)"
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
                    var item = TransformItem(sourceURL: url, originalSize: Self.fileSize(of: url))
                    if let dimensions = Self.pixelSize(of: url) {
                        item.sourceWidth = dimensions.width
                        item.sourceHeight = dimensions.height
                    }
                    return item
                }
            }.value

            guard let self else { return }
            guard !newItems.isEmpty else {
                self.statusMessage = "No supported images found."
                return
            }
            self.items.append(contentsOf: newItems)
            if self.selectedItemID == nil, let first = newItems.first { self.select(first) }
            if self.watermarkMode { self.refreshWatermarkPreview() }
            self.process(itemIDs: Set(newItems.map(\.id)))
        }
    }

    func reprocessAll() {
        guard canProcessAll else { return }
        process(itemIDs: Set(items.map(\.id)))
    }

    var canProcessAll: Bool {
        !items.isEmpty && !isProcessing &&
            (!watermarkMode || watermarkKind != .logo || watermarkLogoData != nil)
    }

    var canProcessSelected: Bool {
        canProcessAll && !selectedItems.isEmpty
    }

    func reprocessSelected() {
        guard canProcessSelected else { return }
        process(itemIDs: selectedIDs)
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
            message: "Choose a folder for \(pending.count) selected image\(pending.count == 1 ? "" : "s")") else { return }
        var saved = 0
        for item in pending {
            guard let data = item.outputData else { continue }
            let destination = uniqueURL(in: folder,
                                        filename: item.suggestedFilename(
                                            extension: (item.outputFormat ?? outputFormat).fileExtension))
            if write(data, to: destination, itemID: item.id) { saved += 1 }
        }
        statusMessage = "Saved \(saved) selected image\(saved == 1 ? "" : "s") to \(folder.lastPathComponent)."
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
        watermarkSizeEstimateTask?.cancel()
        optimizePreviewGeneration &+= 1
        watermarkSizeEstimateGeneration &+= 1
        items.removeAll()
        setSelection([], primary: nil)
        watermarkPreview = nil
        watermarkPreviewError = nil
        watermarkSizeEstimate = nil
        watermarkSizeEstimateItemID = nil
        watermarkSizeEstimateError = nil
        isWatermarkSizeEstimating = false
        clearOptimizePreview()
        statusMessage = nil
    }

    func remove(item: TransformItem) {
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
        clearOptimizePreview()
        if watermarkMode {
            refreshWatermarkPreview()
            refreshWatermarkSizeEstimate()
        }
    }

    func select(_ item: TransformItem) {
        select(item, modifiers: [])
    }

    func select(_ item: TransformItem, modifiers: NSEvent.ModifierFlags) {
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
        if watermarkMode {
            refreshWatermarkPreview()
            refreshWatermarkSizeEstimate()
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

    /// Performs a complete image render and encode with the current Watermark
    /// settings. The output bytes are discarded after the measurement; the
    /// queue is not changed until the user chooses Watermark Selected or All.
    func refreshWatermarkSizeEstimate() {
        guard watermarkMode else { return }
        watermarkSizeEstimateTask?.cancel()
        watermarkSizeEstimateGeneration &+= 1
        let generation = watermarkSizeEstimateGeneration
        guard let selected = selectedItem else {
            watermarkSizeEstimate = nil
            watermarkSizeEstimateItemID = nil
            watermarkSizeEstimateError = nil
            isWatermarkSizeEstimating = false
            return
        }

        let settings = snapshot
        watermarkSizeEstimateItemID = selected.id
        watermarkSizeEstimate = nil
        watermarkSizeEstimateError = nil
        isWatermarkSizeEstimating = true
        let itemID = selected.id
        watermarkSizeEstimateTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                try Task.checkCancellation()
                let estimate = try await Task.detached(priority: .userInitiated) {
                    let source = try Data(contentsOf: selected.sourceURL, options: .mappedIfSafe)
                    let output = try TransformPipeline.process(source, settings: settings)
                    try Task.checkCancellation()
                    return MediaSizeEstimate(
                        sourceBytes: Int64(source.count),
                        estimatedBytes: Int64(output.data.count),
                        basis: .fullImageEncode,
                        detail: "Measured by fully encoding the selected image with the current Watermark settings; it is not saved yet.")
                }.value
                try Task.checkCancellation()
                guard let self,
                      self.watermarkSizeEstimateGeneration == generation,
                      self.selectedItemID == itemID else { return }
                self.watermarkSizeEstimate = estimate
                self.watermarkSizeEstimateError = nil
                self.isWatermarkSizeEstimating = false
            } catch is CancellationError {
                // A newer selection or setting owns the next measurement.
            } catch {
                guard let self,
                      self.watermarkSizeEstimateGeneration == generation,
                      self.selectedItemID == itemID else { return }
                self.watermarkSizeEstimate = nil
                self.watermarkSizeEstimateError = error.localizedDescription
                self.isWatermarkSizeEstimating = false
            }
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
        let watermarkEstimateKey = watermarkMode ? watermarkEstimateSettingsKey : ""
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
                if self.watermarkMode,
                   result.id == self.selectedItemID,
                   self.watermarkEstimateSettingsKey == watermarkEstimateKey,
                   let outputSize = result.outputSize {
                    self.watermarkSizeEstimateItemID = result.id
                    self.watermarkSizeEstimate = MediaSizeEstimate(
                        sourceBytes: Int64(result.originalSize),
                        estimatedBytes: Int64(outputSize),
                        basis: .actualOutput,
                        detail: "Measured prepared output from the current Watermark operation.")
                    self.watermarkSizeEstimateError = nil
                    self.isWatermarkSizeEstimating = false
                }
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
                                  cropWidth: cropWidth, cropHeight: cropHeight,
                                  cropUpscalePolicy: cropUpscalePolicy,
                                  resizeMode: resizeMode, resizeValue: resizeValue,
                                  allowsUpscaling: allowsUpscaling,
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
                result.sourceWidth = output.sourceWidth
                result.sourceHeight = output.sourceHeight
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

    nonisolated private static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsAxes = (5...8).contains(orientation)
        return swapsAxes ? (height, width) : (width, height)
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
