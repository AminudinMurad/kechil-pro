import Foundation
import AppKit
import SwiftUI
import ImageIO

/// One image queued in the app.
struct ScrubItem: Identifiable {
    let id: UUID
    let sourceURL: URL

    var originalSize: Int
    var cleanedSize: Int?
    /// Retained only for snapshot/source compatibility. Production Clean outputs
    /// are URL-backed so a batch does not keep every cleaned file in memory.
    var cleanedData: Data?
    var outputURL: URL?
    var removed: [String] = []
    var preserved: [String] = []
    var format: ImageFormat = .other
    var lossless: Bool = true
    var provenance: ProvenanceReport = .empty(format: .other)
    var outputProvenance: ProvenanceReport?
    var errorText: String?
    var thumbnail: NSImage?
    var savedTo: URL?
    var preset: CleanPreset
    var stage: MediaJobStage
    var sourceIdentity: CleanSourceIdentity?
    var plan: CleanPlanSummary?
    var receipt: CleanReceipt?
    var statusText: String?

    init(id: UUID = UUID(), sourceURL: URL, originalSize: Int,
         preset: CleanPreset = .allMetadata) {
        self.id = id
        self.sourceURL = sourceURL
        self.originalSize = originalSize
        self.cleanedSize = nil
        self.cleanedData = nil
        self.outputURL = nil
        self.removed = []
        self.format = .other
        self.lossless = true
        self.provenance = .empty(format: .other)
        self.outputProvenance = nil
        self.errorText = nil
        self.thumbnail = nil
        self.savedTo = nil
        self.preset = preset
        self.stage = .queued
        self.sourceIdentity = nil
        self.plan = nil
        self.receipt = nil
        self.statusText = nil
    }

    var displayName: String { sourceURL.lastPathComponent }
    var hasPreparedOutput: Bool { cleanedData != nil || outputURL != nil }
    var isSaveReady: Bool {
        hasPreparedOutput && stage == .completed &&
            (receipt?.outcome.isOrdinarySaveAllowed ?? (outputProvenance != nil))
    }
    var isUnchangedCopy: Bool { receipt?.outcome == .unchanged }

    var bytesRemoved: Int {
        guard let cleanedSize else { return 0 }
        return max(0, originalSize - cleanedSize)
    }

    var isClean: Bool {
        errorText == nil && !preset.hasRemaining(in: outputProvenance ?? provenance)
    }

    enum VerificationState {
        case clean
        case remaining
        case partial
    }

    var verificationState: VerificationState {
        guard let outputProvenance else { return .partial }
        if preset.hasRemaining(in: outputProvenance) { return .remaining }
        return outputProvenance.coverage == .containerComplete ? .clean : .partial
    }

    /// "photo.jpg" -> "photo-clean.jpg" (or "photo-copy.jpg" for a no-op).
    var suggestedFilename: String {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let suffix = isUnchangedCopy ? "copy" : "clean"
        return ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
    }
}

@MainActor
final class ScrubModel: ObservableObject {
    @Published var items: [ScrubItem] = []
    @Published private(set) var isInspecting = false
    @Published private(set) var isCleaning = false
    @Published var statusMessage: String?
    @Published private(set) var preset: CleanPreset = .allMetadata

    /// The primary row the inspector is describing. `selectedItemIDs` is the
    /// complete queue selection used by Selected actions.
    @Published var selectedItemID: UUID? {
        didSet {
            guard !selectionMutationInProgress else { return }
            selectedItemIDs = selectedItemID.map { [$0] } ?? []
            selectionAnchorID = selectedItemID
        }
    }
    @Published private(set) var selectedItemIDs: Set<UUID> = []

    /// Live bytes for the selected source and current Clean scope. This is a
    /// preview only: Clean still has to be pressed before a temporary output is
    /// created.
    @Published private(set) var sizeEstimate: MediaSizeEstimate?
    @Published private(set) var sizeEstimateItemID: UUID?
    @Published private(set) var isEstimatingSize = false
    @Published private(set) var sizeEstimateError: String?

    /// Category the list is narrowed to. `nil` means all.
    ///
    /// Scopes the list only — the tiles and chart always describe the whole queue, so
    /// filtering can never make the summary understate what was found.
    @Published var activeFilter: MetadataCategory?

    private let acceptedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "webp", "heic", "heif",
        "tif", "tiff", "gif", "bmp", "avif", "dng",
    ]
    private var workflowTask: Task<Void, Never>?
    private var workflowID: UUID?
    private var selectionRevision: UInt64 = 0
    private var sizeEstimateTask: Task<Void, Never>?
    private var sizeEstimateGeneration = 0
    private var selectionAnchorID: UUID?
    private var selectionMutationInProgress = false

    var totalBytesRemoved: Int { items.reduce(0) { $0 + $1.bytesRemoved } }
    var isProcessing: Bool { isInspecting || isCleaning }
    var cleanedCount: Int { items.filter(\.isSaveReady).count }
    var readyForReviewCount: Int { items.filter { $0.stage == .ready }.count }
    var plannedChangeCount: Int {
        items.filter { $0.stage == .ready && $0.plan?.hasRequestedChanges == true }.count
    }
    var hadMetadataCount: Int {
        items.filter { !$0.removed.isEmpty || $0.provenance.hasDetectedMetadata }.count
    }

    // MARK: Dashboard aggregates

    /// Number of *files* carrying each category — not occurrences. A photo with three
    /// maker-note segments counts once, because the user cares how many of their images
    /// are affected, not how many segments were in them.
    var categoryCounts: [MetadataCategory: Int] {
        var counts: [MetadataCategory: Int] = [:]
        for item in items {
            for category in item.categories {
                counts[category, default: 0] += 1
            }
        }
        return counts
    }

    func count(of category: MetadataCategory) -> Int { categoryCounts[category] ?? 0 }

    /// Categories actually present in this queue, in fixed display order.
    var presentCategories: [MetadataCategory] {
        categoryCounts.keys.sorted { $0.sortRank < $1.sortRank }
    }

    var locationLeakCount: Int { count(of: .gps) }
    var aiGeneratedCount: Int { items.filter { $0.provenance.hasGenerativeAI }.count }
    var reencodedCount: Int { items.filter { $0.hasPreparedOutput && !$0.lossless }.count }
    var losslessCount: Int { items.filter { $0.hasPreparedOutput && $0.lossless }.count }
    var cleanCount: Int { items.filter(\.isClean).count }

    /// The list's contents under the active filter.
    var visibleItems: [ScrubItem] {
        guard let activeFilter else { return items }
        return items.filter { $0.categories.contains(activeFilter) }
    }

    /// Changes presentation only. The queue summary continues to describe every
    /// inspected original and the inspector follows the first visible image when
    /// its previous selection falls outside the filter.
    func selectFilter(_ filter: MetadataCategory?) {
        activeFilter = filter
        correctSelectionForVisibleItems()
        refreshSizeEstimate()
    }

    var selectedItem: ScrubItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    func select(_ item: ScrubItem) {
        select(item, modifiers: [])
    }

    func select(_ item: ScrubItem, modifiers: NSEvent.ModifierFlags) {
        let orderedIDs = visibleItems.map(\.id)
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
        refreshSizeEstimate()
    }

    var selectedIDs: Set<UUID> {
        let validIDs = Set(items.map(\.id))
        let current = selectedItemIDs.intersection(validIDs)
        if !current.isEmpty { return current }
        if let selectedItemID, validIDs.contains(selectedItemID) { return [selectedItemID] }
        return []
    }

    var selectedItems: [ScrubItem] {
        let ids = selectedIDs
        return items.filter { ids.contains($0.id) }
    }

    var selectedItemCount: Int { selectedIDs.count }
    var selectedSaveItems: [ScrubItem] { selectedItems.filter(\.isSaveReady) }
    var selectedSaveCount: Int { selectedSaveItems.count }
    var selectedHasChanges: Bool {
        selectedItems.contains { $0.plan?.hasRequestedChanges == true }
    }

    func isSelected(_ item: ScrubItem) -> Bool { selectedIDs.contains(item.id) }

    private func setSelection(_ ids: Set<UUID>, primary: UUID?) {
        selectionMutationInProgress = true
        selectedItemIDs = ids
        selectedItemID = primary
        selectionMutationInProgress = false
        selectionAnchorID = primary
    }

    /// Changes the cleanup scope by updating cached plans only. No file is re-read,
    /// stripped or regenerated until the user explicitly starts cleanup.
    func selectPreset(_ newPreset: CleanPreset) {
        guard newPreset != preset else { return }
        guard !isCleaning else {
            statusMessage = "Finish the current cleanup before changing the preset."
            return
        }
        preset = newPreset
        selectionRevision &+= 1
        guard !items.isEmpty else { return }

        for index in items.indices {
            items[index].preset = newPreset
            guard let identity = items[index].sourceIdentity else { continue }
            discardPreparedOutput(at: index)
            items[index].plan = Self.makePlan(for: items[index], identity: identity,
                                              preset: newPreset,
                                              revision: selectionRevision)
            items[index].stage = .ready
            items[index].statusText = "Ready for review"
            items[index].errorText = nil
        }
        let affected = plannedChangeCount
        statusMessage = affected == 0
            ? "No inspected images match \(newPreset.title.lowercased()). You can prepare unchanged copies explicitly."
            : "Review updated instantly from cached inspections. \(affected) image\(affected == 1 ? "" : "s") match \(newPreset.title.lowercased())."
        refreshSizeEstimate()
    }

    // MARK: Intake

    func add(urls: [URL]) {
        let expanded = expand(urls: urls)
        guard !expanded.isEmpty else {
            statusMessage = "No supported images found."
            return
        }
        let existing = Set(items.map { $0.sourceURL.standardizedFileURL })
        let unique = expanded.filter { !existing.contains($0.standardizedFileURL) }
        guard !unique.isEmpty else {
            statusMessage = "Those images are already in this queue."
            return
        }
        let newItems = unique.map { ScrubItem(sourceURL: $0, originalSize: 0, preset: preset) }
        items.append(contentsOf: newItems)
        if selectedItemID == nil, let first = newItems.first { select(first) }
        statusMessage = "Queued \(newItems.count) image\(newItems.count == 1 ? "" : "s") for inspection."
        startPendingInspections()
    }

    /// Accepts dropped folders by walking them one level deep on down.
    private func expand(urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let e = fm.enumerator(at: url,
                                      includingPropertiesForKeys: [.isRegularFileKey],
                                      options: [.skipsHiddenFiles])
                while let child = e?.nextObject() as? URL {
                    if acceptedExtensions.contains(child.pathExtension.lowercased()) {
                        result.append(child)
                    }
                }
            } else if acceptedExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result
    }

    // MARK: Work

    /// Runs one bounded inspection at a time. Multiple Add actions feed this same
    /// queue instead of spawning overlapping full-file reads.
    private func startPendingInspections() {
        guard workflowTask == nil, !isCleaning else { return }
        let pendingIDs = items.filter { $0.stage == .queued }.map(\.id)
        guard !pendingIDs.isEmpty else { return }
        let runID = UUID()
        workflowID = runID
        isInspecting = true
        workflowTask = Task { [weak self] in
            guard let self else { return }
            var inspectedCount = 0
            for id in pendingIDs {
                if Task.isCancelled { break }
                guard let index = self.items.firstIndex(where: { $0.id == id }) else { continue }
                self.items[index].stage = .analysing
                self.items[index].statusText = "Inspecting metadata…"
                self.statusMessage = "Inspecting \(inspectedCount + 1) of \(pendingIDs.count) images…"
                var inspected = await Self.inspect(url: self.items[index].sourceURL,
                                                   id: id, preset: self.preset)
                guard self.workflowID == runID else { return }
                if Task.isCancelled {
                    inspected.stage = .cancelled
                    inspected.statusText = "Inspection cancelled"
                } else if let identity = inspected.sourceIdentity {
                    inspected.preset = self.preset
                    inspected.plan = Self.makePlan(for: inspected, identity: identity,
                                                   preset: self.preset,
                                                   revision: self.selectionRevision)
                    inspectedCount += 1
                }
                if let current = self.items.firstIndex(where: { $0.id == id }) {
                    self.items[current] = inspected
                }
            }
            let wasCancelled = Task.isCancelled
            guard self.workflowID == runID else { return }
            self.isInspecting = false
            self.workflowTask = nil
            self.workflowID = nil
            self.statusMessage = wasCancelled
                ? "Inspection cancelled. Originals are unchanged."
                : "Inspected \(inspectedCount) image\(inspectedCount == 1 ? "" : "s"). Review the plan, then choose Clean Selected or Clean All."
            if !wasCancelled { self.refreshSizeEstimate() }
            if !wasCancelled { self.startPendingInspections() }
        }
    }

    /// Inspection reads and probes the original but never creates a modified output.
    private static func inspect(url: URL, id: UUID,
                                preset: CleanPreset) async -> ScrubItem {
        let task = Task.detached(priority: .utility) { () -> ScrubItem in
            var original: Data?
            do {
                try Task.checkCancellation()
                let identity = try CleanSourceIdentity.capture(at: url)
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                original = data
                try Task.checkCancellation()
                guard identity.stillMatches(url) else { throw CleanWorkflowError.sourceChanged }
                var item = ScrubItem(id: id, sourceURL: url, originalSize: data.count,
                                     preset: preset)
                item.sourceIdentity = identity
                item.provenance = ProvenanceProbe.inspect(data)
                item.format = item.provenance.format
                item.thumbnail = Self.thumbnail(from: data)
                item.stage = .ready
                item.statusText = "Ready for review"
                return item
            } catch {
                var item = ScrubItem(id: id, sourceURL: url,
                                     originalSize: original?.count ?? 0,
                                     preset: preset)
                if let original {
                    item.provenance = ProvenanceProbe.inspect(original)
                    item.format = item.provenance.format
                    item.thumbnail = Self.thumbnail(from: original)
                }
                item.stage = error is CancellationError ? .cancelled : .failed
                item.errorText = error.localizedDescription
                item.statusText = error is CancellationError
                    ? "Inspection cancelled" : "Could not inspect this image"
                return item
            }
        }
        return await CleanCancellation.value(of: task)
    }

    var canCleanSelected: Bool {
        !isProcessing && selectedItems.contains {
            $0.stage == .ready && $0.sourceIdentity != nil
        }
    }

    var canSaveSelected: Bool { !isProcessing && !selectedSaveItems.isEmpty }

    func saveSelected() {
        let pending = selectedSaveItems
        guard canSaveSelected else { return }
        if selectedItemCount == 1, let item = pending.first {
            save(item: item)
            return
        }
        guard let folder = BatchSaveFolderChooser.choose(
            defaultDirectory: AppSettings.shared.defaultSaveDirectory,
            message: "Choose a folder for (pending.count) selected image\(pending.count == 1 ? "" : "s")") else { return }
        var saved = 0
        for item in pending {
            let destination = MediaSaveService.uniqueURL(in: folder,
                                                         filename: item.suggestedFilename)
            if write(item: item, to: destination) { saved += 1 }
        }
        statusMessage = "Saved (saved) selected image\(saved == 1 ? "" : "s") to (folder.lastPathComponent)."
    }

    func cleanAll() { clean(itemIDs: Set(items.map(\.id))) }

    func cleanSelected() {
        guard canCleanSelected else { return }
        clean(itemIDs: selectedIDs)
    }

    /// Snapshots only the requested reviewed files; changing the highlight cannot
    /// expand an in-flight Selected operation to the whole queue.
    private func clean(itemIDs: Set<UUID>) {
        guard workflowTask == nil, !isProcessing else { return }
        let work = items.filter {
            itemIDs.contains($0.id) && $0.stage == .ready && $0.sourceIdentity != nil
        }.map(\.id)
        guard !work.isEmpty else {
            statusMessage = "No inspected images are waiting for cleanup."
            return
        }
        sizeEstimateTask?.cancel()
        sizeEstimateGeneration &+= 1
        isEstimatingSize = false
        let runID = UUID()
        workflowID = runID
        isCleaning = true
        workflowTask = Task { [weak self] in
            guard let self else { return }
            var prepared = 0
            for id in work {
                if Task.isCancelled { break }
                guard let index = self.items.firstIndex(where: { $0.id == id }),
                      let identity = self.items[index].sourceIdentity else { continue }
                let snapshot = self.items[index]
                self.items[index].stage = .processing
                self.items[index].statusText = "Cleaning from the inspected original…"
                self.statusMessage = "Cleaning \(prepared + 1) of \(work.count) images…"
                let result = await Self.clean(url: snapshot.sourceURL, id: id,
                                              preset: snapshot.preset,
                                              identity: identity,
                                              revision: snapshot.plan?.selectionRevision ?? self.selectionRevision)
                guard self.workflowID == runID else {
                    if let outputURL = result.outputURL {
                        try? FileManager.default.removeItem(at: outputURL)
                    }
                    return
                }
                if Task.isCancelled {
                    if let outputURL = result.outputURL {
                        try? FileManager.default.removeItem(at: outputURL)
                    }
                    if let current = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[current].stage = .cancelled
                        self.items[current].statusText = "Cleanup cancelled; original unchanged"
                    }
                    break
                }
                if let current = self.items.firstIndex(where: { $0.id == id }) {
                    self.items[current] = result
                    if result.id == self.selectedItemID,
                       let cleanedSize = result.cleanedSize {
                        self.sizeEstimateItemID = result.id
                        self.sizeEstimate = MediaSizeEstimate(
                            sourceBytes: Int64(result.originalSize),
                            estimatedBytes: Int64(cleanedSize),
                            basis: .actualOutput,
                            detail: "Measured prepared output from the verified Clean operation.")
                        self.sizeEstimateError = nil
                        self.isEstimatingSize = false
                    }
                    if result.isSaveReady { prepared += 1 }
                } else if let outputURL = result.outputURL {
                    try? FileManager.default.removeItem(at: outputURL)
                }
            }
            let wasCancelled = Task.isCancelled
            guard self.workflowID == runID else { return }
            if wasCancelled {
                for index in self.items.indices where self.items[index].stage == .processing {
                    self.items[index].stage = .cancelled
                    self.items[index].statusText = "Cleanup cancelled; original unchanged"
                }
            }
            self.isCleaning = false
            self.workflowTask = nil
            self.workflowID = nil
            self.statusMessage = wasCancelled
                ? "Cleanup cancelled. Originals are unchanged."
                : "Prepared \(prepared) of \(work.count) image cop\(work.count == 1 ? "y" : "ies") for saving."
            if !wasCancelled { self.startPendingInspections() }
        }
    }

    private static func clean(url: URL, id: UUID, preset: CleanPreset,
                              identity: CleanSourceIdentity,
                              revision: UInt64) async -> ScrubItem {
        let task = Task.detached(priority: .userInitiated) { () -> ScrubItem in
            var original: Data?
            var temporaryOutput: URL?
            do {
                try Task.checkCancellation()
                guard identity.stillMatches(url) else { throw CleanWorkflowError.sourceChanged }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                original = data
                try Task.checkCancellation()
                let inputReport = ProvenanceProbe.inspect(data)
                var item = ScrubItem(id: id, sourceURL: url, originalSize: data.count,
                                     preset: preset)
                item.sourceIdentity = identity
                item.provenance = inputReport
                item.format = inputReport.format
                item.thumbnail = Self.thumbnail(from: data)
                item.plan = makePlan(for: item, identity: identity,
                                     preset: preset, revision: revision)

                let outputData: Data
                let receiptOutcome: CleanReceiptOutcome
                if preset.hasRemaining(in: inputReport) {
                    let result = try MetadataStripper.strip(data, preset: preset)
                    outputData = result.data
                    item.cleanedSize = result.data.count
                    item.removed = result.removed
                    item.preserved = result.preserved
                    item.format = result.format
                    item.lossless = result.lossless
                    item.outputProvenance = ProvenanceProbe.inspect(result.data)
                    let remaining = item.outputProvenance.map { preset.hasRemaining(in: $0) } ?? true
                    receiptOutcome = remaining || item.outputProvenance?.coverage != .containerComplete
                        ? .partial : .verified
                } else {
                    outputData = data
                    item.cleanedSize = data.count
                    item.lossless = true
                    item.outputProvenance = inputReport
                    receiptOutcome = .unchanged
                }

                try Task.checkCancellation()
                let suffix = receiptOutcome == .unchanged ? "unchanged" : "clean"
                let outputURL = try CleanTemporaryFiles.makeURL(
                    suffix: suffix, extension: url.pathExtension)
                temporaryOutput = outputURL
                try outputData.write(to: outputURL, options: .atomic)
                try Task.checkCancellation()
                guard identity.stillMatches(url) else { throw CleanWorkflowError.sourceChanged }
                let outputIdentity = try CleanSourceIdentity.capture(at: outputURL)
                let remaining = receiptOutcome == .partial
                    ? ["Selected-scope metadata remains or verification coverage is partial."] : []
                item.receipt = CleanReceipt(
                    sourceIdentity: identity,
                    outputIdentity: outputIdentity,
                    selectionRevision: revision,
                    selectionTitle: preset.title,
                    outcome: receiptOutcome,
                    removed: item.removed,
                    preserved: item.preserved,
                    remaining: remaining,
                    unsupported: [],
                    checks: [
                        CleanVerificationCheck(title: "Source identity",
                                               detail: "The source did not change during cleanup.",
                                               outcome: .passed),
                        CleanVerificationCheck(title: "Selected metadata",
                                               detail: receiptOutcome == .partial
                                                   ? "Selected metadata or coverage remains incomplete."
                                                   : "The prepared output was re-inspected.",
                                               outcome: receiptOutcome == .partial ? .failed : .passed),
                    ],
                    limitations: item.outputProvenance?.limitations ?? [])
                item.outputURL = outputURL
                item.stage = receiptOutcome.isOrdinarySaveAllowed ? .completed : .failed
                item.statusText = switch receiptOutcome {
                case .unchanged: "Unchanged copy ready to save"
                case .verified: "Verified clean copy ready to save"
                case .partial: "Selected metadata remains or verification is partial"
                case .failed: "Cleanup failed"
                }
                return item
            } catch {
                if let temporaryOutput { try? FileManager.default.removeItem(at: temporaryOutput) }
                var item = ScrubItem(id: id, sourceURL: url,
                                     originalSize: original?.count ?? Int(identity.fileSize),
                                     preset: preset)
                item.sourceIdentity = identity
                if let original {
                    item.provenance = ProvenanceProbe.inspect(original)
                    item.format = item.provenance.format
                    item.thumbnail = Self.thumbnail(from: original)
                }
                item.stage = error is CancellationError ? .cancelled : .failed
                item.errorText = error.localizedDescription
                item.statusText = error is CancellationError
                    ? "Cleanup cancelled; original unchanged" : "Could not prepare a clean copy"
                return item
            }
        }
        return await CleanCancellation.value(of: task)
    }

    nonisolated private static func makePlan(for item: ScrubItem,
                                             identity: CleanSourceIdentity,
                                             preset: CleanPreset,
                                             revision: UInt64) -> CleanPlanSummary {
        let detected = item.provenance.carriers.count + item.provenance.findings.count
        return CleanPlanSummary(
            sourceIdentity: identity,
            selectionRevision: revision,
            selectionTitle: preset.title,
            detectedEntryCount: detected,
            selectedEntryCount: preset.hasRemaining(in: item.provenance) ? max(1, detected) : 0,
            unsupportedReasons: [],
            warnings: item.provenance.limitations)
    }

    /// Downscales via ImageIO rather than `NSImage.lockFocus`, which is not safe
    /// off the main thread. `nonisolated` because this is called from the detached
    /// processing task, never from the main actor.
    nonisolated static func thumbnail(from data: Data, max side: Int = 160) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Measures the selected image with the same scoped byte-level cleaner used
    /// by Clean. No output is persisted; the source identity is checked both
    /// before and after the measurement so a stale card cannot describe a
    /// changed original.
    func refreshSizeEstimate() {
        sizeEstimateTask?.cancel()
        sizeEstimateGeneration &+= 1
        let generation = sizeEstimateGeneration

        guard let item = selectedItem,
              let identity = item.sourceIdentity,
              item.stage == .ready || item.stage == .completed || item.stage == .saved
        else {
            sizeEstimate = nil
            sizeEstimateItemID = nil
            sizeEstimateError = nil
            isEstimatingSize = false
            return
        }

        sizeEstimateItemID = item.id
        sizeEstimateError = nil
        if let cleanedSize = item.cleanedSize, item.receipt != nil {
            sizeEstimate = MediaSizeEstimate(
                sourceBytes: Int64(item.originalSize),
                estimatedBytes: Int64(cleanedSize),
                basis: .actualOutput,
                detail: "Measured prepared output from the verified Clean operation.")
            isEstimatingSize = false
            return
        }

        sizeEstimate = nil
        isEstimatingSize = true
        let url = item.sourceURL
        let itemID = item.id
        let selectedPreset = item.preset
        sizeEstimateTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 160_000_000)
                try Task.checkCancellation()
                let estimate = try await Task.detached(priority: .utility) {
                    try Task.checkCancellation()
                    guard identity.stillMatches(url) else {
                        throw CleanWorkflowError.sourceChanged
                    }
                    let source = try Data(contentsOf: url, options: .mappedIfSafe)
                    let report = ProvenanceProbe.inspect(source)
                    let output: Data
                    if selectedPreset.hasRemaining(in: report) {
                        output = try MetadataStripper.strip(source, preset: selectedPreset).data
                    } else {
                        output = source
                    }
                    try Task.checkCancellation()
                    guard identity.stillMatches(url) else {
                        throw CleanWorkflowError.sourceChanged
                    }
                    let detail = selectedPreset.hasRemaining(in: report)
                        ? "\(selectedPreset.title) uses the same lossless Clean transformation; no file is saved until Clean."
                        : "No \(selectedPreset.title.lowercased()) fields were found; Clean will prepare an unchanged byte-for-byte copy."
                    return MediaSizeEstimate(sourceBytes: Int64(source.count),
                                             estimatedBytes: Int64(output.count),
                                             basis: .exactClean,
                                             detail: detail)
                }.value
                try Task.checkCancellation()
                guard let self,
                      self.sizeEstimateGeneration == generation,
                      self.selectedItemID == itemID else { return }
                self.sizeEstimate = estimate
                self.sizeEstimateError = nil
                self.isEstimatingSize = false
            } catch is CancellationError {
                // A newer selection or preset owns the next measurement.
            } catch {
                guard let self,
                      self.sizeEstimateGeneration == generation,
                      self.selectedItemID == itemID else { return }
                self.sizeEstimate = nil
                self.sizeEstimateError = error.localizedDescription
                self.isEstimatingSize = false
            }
        }
    }

    // MARK: Saving

    func save(item: ScrubItem) {
        guard item.isSaveReady else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.suggestedFilename
        panel.directoryURL = AppSettings.shared.defaultSaveDirectory
        panel.canCreateDirectories = true
        panel.message = item.isUnchangedCopy
            ? "Save an unchanged copy of \(item.displayName)"
            : "Save the verified clean copy of \(item.displayName)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(item: item, to: url)
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
            panel.message = "Choose a folder for \(pending.count) prepared image cop\(pending.count == 1 ? "y" : "ies")"
            guard panel.runModal() == .OK, let selected = panel.url else { return }
            folder = selected
        }

        var written = 0
        for item in pending {
            let target = MediaSaveService.uniqueURL(in: folder, filename: item.suggestedFilename)
            if write(item: item, to: target) { written += 1 }
        }
        statusMessage = "Saved \(written) image\(written == 1 ? "" : "s") to \(folder.lastPathComponent)."
    }

    @discardableResult
    private func write(item: ScrubItem, to url: URL) -> Bool {
        do {
            try MediaSaveService.protectOriginals(
                destination: url, sourceURLs: items.map(\.sourceURL))
            if let outputURL = item.outputURL {
                try MediaSaveService.copyTemporaryOutput(from: outputURL, to: url)
            } else if let data = item.cleanedData {
                try MediaSaveService.save(data: data, to: url)
            } else {
                throw CleanWorkflowError.outputUnavailable
            }
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].savedTo = url
                items[idx].stage = .saved
                if let outputURL = items[idx].outputURL {
                    try? FileManager.default.removeItem(at: outputURL)
                }
                items[idx].outputURL = nil
                items[idx].cleanedData = nil
            }
            return true
        } catch {
            statusMessage = "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    // MARK: Queue

    func clear() {
        workflowTask?.cancel()
        sizeEstimateTask?.cancel()
        sizeEstimateGeneration &+= 1
        for item in items where item.outputURL != nil {
            try? FileManager.default.removeItem(at: item.outputURL!)
        }
        items.removeAll()
        workflowTask = nil
        workflowID = nil
        isInspecting = false
        isCleaning = false
        statusMessage = nil
        setSelection([], primary: nil)
        sizeEstimate = nil
        sizeEstimateItemID = nil
        sizeEstimateError = nil
        isEstimatingSize = false
        activeFilter = nil
    }

    func remove(item: ScrubItem) {
        if let outputURL = item.outputURL { try? FileManager.default.removeItem(at: outputURL) }
        items.removeAll { $0.id == item.id }
        // A filter with nothing left behind it is a dead end the user cannot see out of.
        if let activeFilter, count(of: activeFilter) == 0 { self.activeFilter = nil }
        correctSelectionForVisibleItems()
        refreshSizeEstimate()
    }

    private func correctSelectionForVisibleItems() {
        let visibleIDs = Set(visibleItems.map(\.id))
        let retained = selectedIDs.intersection(visibleIDs)
        if !retained.isEmpty {
            setSelection(retained,
                         primary: MediaSelection.primaryID(for: retained,
                                                           preferredID: selectedItemID,
                                                           orderedIDs: visibleItems.map(\.id)))
        } else {
            let next = visibleItems.first?.id
            setSelection(next.map { [$0] } ?? [], primary: next)
        }
    }

    func cancel() {
        guard isProcessing else { return }
        for index in items.indices
        where items[index].stage == .analysing || items[index].stage == .processing {
            items[index].stage = .cancelling
            items[index].statusText = "Cancelling…"
        }
        statusMessage = "Cancelling…"
        workflowTask?.cancel()
    }

    private func discardPreparedOutput(at index: Int) {
        if let outputURL = items[index].outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        items[index].outputURL = nil
        items[index].cleanedData = nil
        items[index].cleanedSize = nil
        items[index].removed = []
        items[index].preserved = []
        items[index].outputProvenance = nil
        items[index].receipt = nil
        items[index].savedTo = nil
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose images to scrub"
        guard panel.runModal() == .OK else { return }
        add(urls: panel.urls)
    }
}

// MARK: - Formatting

enum Fmt {
    static func bytes(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1024 * 1024 { return String(format: "%.1f KB", Double(n) / 1024) }
        return String(format: "%.2f MB", Double(n) / 1024 / 1024)
    }
}
