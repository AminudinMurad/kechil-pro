import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class VideoCleanModel: ObservableObject {
    @Published var items: [VideoQueueItem] = []
    @Published var selectedItemID: UUID? {
        didSet {
            guard !selectionMutationInProgress else { return }
            selectedItemIDs = selectedItemID.map { [$0] } ?? []
            selectionAnchorID = selectedItemID
        }
    }
    @Published private(set) var selectedItemIDs: Set<UUID> = []
    @Published var activeFilter: VideoFindingFilter?
    @Published private(set) var isProcessing = false
    @Published private(set) var isCleaning = false
    @Published var statusMessage: String?
    /// Video Clean is multi-select. All supported groups are selected by default,
    /// matching the safe broad-clean behaviour users already had.
    @Published private(set) var selection: VideoCleanSelection = .all
    /// Kept for compatibility with older integrations that read the old single
    /// preset. The video UI and pipeline use `selection`.
    @Published private(set) var preset: CleanPreset = .allMetadata
    /// Live bytes for the selected video and current metadata scope. Clean
    /// remains an explicit action; this card only measures what that action would
    /// produce.
    @Published private(set) var sizeEstimate: MediaSizeEstimate?
    @Published private(set) var sizeEstimateItemID: UUID?
    @Published private(set) var isEstimatingSize = false
    @Published private(set) var sizeEstimateError: String?

    private var processingTask: Task<Void, Never>?
    private var processingID: UUID?
    private var selectionRevision: UInt64 = 0
    private var sizeEstimateTask: Task<Void, Never>?
    private var sizeEstimateGeneration = 0
    private var selectionAnchorID: UUID?
    private var selectionMutationInProgress = false

    var selectedItem: VideoQueueItem? {
        guard let selectedItemID else { return nil }
        return visibleItems.first { $0.id == selectedItemID }
    }
    var completedCount: Int { items.filter(\.isSaveReady).count }
    var unsavedCount: Int { items.filter { $0.isSaveReady && $0.savedTo == nil }.count }
    var readyForReviewCount: Int { items.filter { $0.stage == .ready }.count }
    var plannedChangeCount: Int {
        items.filter { $0.stage == .ready && $0.plan?.hasRequestedChanges == true }.count
    }
    var withMetadataCount: Int { items.filter { !$0.sourceFindings.isEmpty }.count }
    var aiGeneratedCount: Int { count(of: .generativeAI) }
    var locationLeakCount: Int { count(of: .location) }
    var audioCount: Int { items.filter { $0.descriptor?.hasAudio == true }.count }

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
    var selectedHasChanges: Bool {
        selectedItems.contains { $0.plan?.hasRequestedChanges == true }
    }

    func isSelected(_ item: VideoQueueItem) -> Bool { selectedIDs.contains(item.id) }

    private func setSelection(_ ids: Set<UUID>, primary: UUID?) {
        selectionMutationInProgress = true
        selectedItemIDs = ids
        selectedItemID = primary
        selectionMutationInProgress = false
        selectionAnchorID = primary
    }

    /// Per-file counts. Several matching fields in one video still count once,
    /// while one video may appear in multiple overlapping categories.
    var categoryCounts: [VideoFindingFilter: Int] {
        var result: [VideoFindingFilter: Int] = [:]
        for item in items {
            for filter in VideoFindingFilter.filters(in: item.sourceFindings) {
                result[filter, default: 0] += 1
            }
        }
        return result
    }

    func count(of filter: VideoFindingFilter) -> Int { categoryCounts[filter] ?? 0 }

    var presentFilters: [VideoFindingFilter] {
        VideoFindingFilter.allCases.filter { count(of: $0) > 0 }
    }

    var visibleItems: [VideoQueueItem] {
        guard let activeFilter else { return items }
        return items.filter { item in
            item.sourceFindings.contains(where: activeFilter.matches)
        }
    }

    func selectFilter(_ filter: VideoFindingFilter?) {
        activeFilter = filter
        correctSelectionForVisibleItems()
    }

    /// Changes the cleanup scope without re-reading or exporting any video.
    func selectPreset(_ newPreset: CleanPreset) {
        selectSelection(newPreset.videoSelection)
    }

    /// Toggles one of the five visible video metadata groups. The new plan is
    /// calculated from the cached inspection; cleaning remains a deliberate action.
    func toggle(_ scope: VideoCleanScope) {
        var next = selection
        next.toggle(scope)
        selectSelection(next)
    }

    func selectSelection(_ newSelection: VideoCleanSelection) {
        guard newSelection != selection else { return }
        guard !isCleaning else {
            statusMessage = "Finish the current cleanup before changing the groups."
            return
        }
        selection = newSelection
        selectionRevision &+= 1
        // `preset` is only a compatibility value for older callers. A multi-select
        // cannot be represented by one of the original four image presets.
        preset = .allMetadata
        guard !items.isEmpty else { return }
        for index in items.indices {
            items[index].selection = newSelection
            guard let identity = items[index].sourceIdentity,
                  let report = items[index].inspectionReport else { continue }
            discardPreparedOutput(at: index)
            items[index].findings = report.findings.filter(newSelection.matches)
            items[index].remainingFindings = []
            items[index].plan = Self.makePlan(identity: identity, report: report,
                                              selection: newSelection,
                                              revision: selectionRevision)
            items[index].stage = .ready
            items[index].phase = nil
            items[index].statusText = Self.reviewStatus(for: items[index].findings,
                                                        selection: newSelection)
            items[index].errorText = nil
        }
        let affected = plannedChangeCount
        statusMessage = affected == 0
            ? "No inspected videos match the selected groups. You can prepare unchanged copies explicitly."
            : "Review updated instantly from cached inspections. \(affected) video\(affected == 1 ? "" : "s") need cleanup."
        refreshSizeEstimate()
    }

    func select(_ item: VideoQueueItem) {
        select(item, modifiers: [])
    }

    func select(_ item: VideoQueueItem, modifiers: NSEvent.ModifierFlags) {
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
        if selectedItemID == nil, let first = newItems.first { select(first) }
        statusMessage = "Queued \(newItems.count) video\(newItems.count == 1 ? "" : "s") for inspection."
        startPendingInspections()
    }

    func cancel() {
        guard isProcessing else { return }
        statusMessage = "Cancelling…"
        for index in items.indices
        where items[index].stage == .analysing || items[index].stage == .processing {
            items[index].stage = .cancelling
            items[index].statusText = "Cancelling…"
        }
        processingTask?.cancel()
    }

    func clear() {
        processingTask?.cancel()
        sizeEstimateTask?.cancel()
        sizeEstimateGeneration &+= 1
        for item in items { cleanup(item.outputURL) }
        items.removeAll()
        processingTask = nil
        processingID = nil
        setSelection([], primary: nil)
        activeFilter = nil
        statusMessage = nil
        isProcessing = false
        isCleaning = false
        sizeEstimate = nil
        sizeEstimateItemID = nil
        sizeEstimateError = nil
        isEstimatingSize = false
    }

    func remove(item: VideoQueueItem) {
        cleanup(item.outputURL)
        items.removeAll { $0.id == item.id }
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

    func save(item: VideoQueueItem) {
        guard item.isSaveReady, let outputURL = item.outputURL else { return }
        let ext = outputURL.pathExtension
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.suggestedFilename(
            suffix: item.verification == .unchanged ? "copy" : "clean", extension: ext)
        panel.directoryURL = AppSettings.shared.defaultSaveDirectory
        panel.canCreateDirectories = true
        panel.message = item.verification == .unchanged
            ? "Save an unchanged copy of \(item.displayName)"
            : "Save the processed copy of \(item.displayName)"
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
            panel.message = "Choose a folder for \(pending.count) video cop\(pending.count == 1 ? "y" : "ies")"
            guard panel.runModal() == .OK, let selected = panel.url else { return }
            folder = selected
        }
        var saved = 0
        for item in pending {
            guard let outputURL = item.outputURL else { continue }
            let filename = item.suggestedFilename(
                suffix: item.verification == .unchanged ? "copy" : "clean",
                extension: outputURL.pathExtension)
            let destination = MediaSaveService.uniqueURL(in: folder, filename: filename)
            if write(itemID: item.id, outputURL: outputURL, destination: destination) { saved += 1 }
        }
        statusMessage = "Saved \(saved) video cop\(saved == 1 ? "y" : "ies") to \(folder.lastPathComponent)."
    }

    /// Imports stop here after descriptor, poster and metadata inspection. Only one
    /// video is inspected at a time; additional Add actions join the same queue.
    private func startPendingInspections() {
        guard processingTask == nil, !isCleaning else { return }
        let pendingIDs = items.filter { $0.stage == .queued }.map(\.id)
        guard !pendingIDs.isEmpty else { return }
        let runID = UUID()
        processingID = runID
        processingTask = Task { [weak self] in
            guard let self else { return }
            self.isProcessing = true
            var inspected = 0
            for id in pendingIDs {
                if Task.isCancelled { break }
                guard let index = self.items.firstIndex(where: { $0.id == id }) else { continue }
                let sourceURL = self.items[index].sourceURL
                self.items[index].stage = .analysing
                self.items[index].phase = .reading
                self.items[index].statusText = "Inspecting video and metadata…"
                self.statusMessage = "Inspecting \(inspected + 1) of \(pendingIDs.count) videos…"
                do {
                    let identity = try CleanSourceIdentity.capture(at: sourceURL)
                    async let poster = VideoPosterGenerator.image(for: sourceURL)
                    async let descriptor = MediaCapabilityProbe.inspectVideo(at: sourceURL)
                    async let report = VideoMetadataProbe.inspect(url: sourceURL)
                    let (loadedDescriptor, loadedReport) = try await (descriptor, report)
                    try Task.checkCancellation()
                    guard self.processingID == runID else { return }
                    guard identity.stillMatches(sourceURL) else {
                        throw CleanWorkflowError.sourceChanged
                    }
                    guard let current = self.items.firstIndex(where: { $0.id == id }) else { continue }
                    self.items[current].sourceIdentity = identity
                    self.items[current].descriptor = loadedDescriptor
                    self.items[current].poster = await poster
                    self.items[current].inspectionReport = loadedReport
                    self.items[current].detectedFindings = loadedReport.findings
                    self.items[current].selection = self.selection
                    self.items[current].findings = loadedReport.findings.filter(self.selection.matches)
                    self.items[current].remainingFindings = []
                    self.items[current].plan = Self.makePlan(identity: identity,
                                                            report: loadedReport,
                                                            selection: self.selection,
                                                            revision: self.selectionRevision)
                    self.items[current].stage = .ready
                    self.items[current].phase = nil
                    self.items[current].statusText = Self.reviewStatus(
                        for: self.items[current].findings, selection: self.selection)
                    self.items[current].errorText = nil
                    inspected += 1
                } catch is CancellationError {
                    if let current = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[current].stage = .cancelled
                        self.items[current].statusText = "Inspection cancelled; original unchanged"
                    }
                    break
                } catch {
                    if let current = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[current].stage = .failed
                        self.items[current].errorText = error.localizedDescription
                        self.items[current].statusText = "Could not inspect this video"
                    }
                }
            }
            let wasCancelled = Task.isCancelled
            guard self.processingID == runID else { return }
            self.isProcessing = false
            self.processingTask = nil
            self.processingID = nil
            self.statusMessage = wasCancelled
                ? "Inspection cancelled. Originals are unchanged."
                : "Inspected \(inspected) video\(inspected == 1 ? "" : "s"). Review the plan, then choose Clean Selected or Clean All."
            if !wasCancelled { self.refreshSizeEstimate() }
            if !wasCancelled { self.startPendingInspections() }
        }
    }

    var canCleanSelected: Bool {
        !isProcessing && selectedItems.contains {
            $0.stage == .ready && $0.sourceIdentity != nil &&
                $0.descriptor != nil && $0.inspectionReport != nil
        }
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
            let filename = item.suggestedFilename(
                suffix: item.verification == .unchanged ? "copy" : "clean",
                extension: outputURL.pathExtension)
            let destination = MediaSaveService.uniqueURL(in: folder, filename: filename)
            if write(itemID: item.id, outputURL: outputURL, destination: destination) { saved += 1 }
        }
        statusMessage = "Saved \(saved) selected video\(saved == 1 ? "" : "s") to \(folder.lastPathComponent)."
    }

    func cleanAll() { clean(itemIDs: Set(items.map(\.id))) }

    func cleanSelected() {
        guard canCleanSelected else { return }
        clean(itemIDs: selectedIDs)
    }

    /// Runs the chosen files from their inspected originals, never from a preview.
    private func clean(itemIDs: Set<UUID>) {
        guard processingTask == nil, !isProcessing else { return }
        let work = items.filter {
            itemIDs.contains($0.id) && $0.stage == .ready && $0.sourceIdentity != nil &&
                $0.descriptor != nil && $0.inspectionReport != nil
        }.map(\.id)
        guard !work.isEmpty else {
            statusMessage = "No inspected videos are waiting for cleanup."
            return
        }
        sizeEstimateTask?.cancel()
        sizeEstimateGeneration &+= 1
        isEstimatingSize = false
        let activeSelection = selection
        let runID = UUID()
        processingID = runID
        isCleaning = true
        isProcessing = true
        processingTask = Task { [weak self] in
            guard let self else { return }
            var prepared = 0
            for id in work {
                if Task.isCancelled { break }
                guard let index = self.items.firstIndex(where: { $0.id == id }),
                      let identity = self.items[index].sourceIdentity,
                      let descriptor = self.items[index].descriptor,
                      let report = self.items[index].inspectionReport else { continue }
                let sourceURL = self.items[index].sourceURL
                self.discardPreparedOutput(at: index)
                self.items[index].selection = activeSelection
                self.items[index].findings = report.findings.filter(activeSelection.matches)
                self.items[index].stage = .processing
                self.items[index].phase = .writing
                self.items[index].statusText = "Cleaning from the inspected original…"
                self.statusMessage = "\(activeSelection.actionTitle) \(prepared + 1) of \(work.count) videos…"
                do {
                    guard identity.stillMatches(sourceURL) else {
                        throw CleanWorkflowError.sourceChanged
                    }
                    let result = try await VideoCleanPipeline.clean(
                        sourceURL: sourceURL,
                        selection: activeSelection,
                        inspectedDescriptor: descriptor,
                        inspectedReport: report)
                    try Task.checkCancellation()
                    guard self.processingID == runID else {
                        self.cleanup(result.outputURL)
                        return
                    }
                    guard identity.stillMatches(sourceURL) else {
                        self.cleanup(result.outputURL)
                        throw CleanWorkflowError.sourceChanged
                    }
                    guard let final = self.items.firstIndex(where: { $0.id == id }) else {
                        self.cleanup(result.outputURL)
                        continue
                    }
                    let outputIdentity = try CleanSourceIdentity.capture(at: result.outputURL)
                    let receiptOutcome: CleanReceiptOutcome = result.remainingFindings.isEmpty
                        ? (result.verification == .unchanged ? .unchanged : .verified)
                        : .partial
                    self.items[final].outputDescriptor = result.outputDescriptor
                    self.items[final].detectedFindings = result.inputFindings
                    self.items[final].findings = result.inputFindings.filter(activeSelection.matches)
                    self.items[final].remainingFindings = result.remainingFindings
                    self.items[final].verification = result.verification
                    self.items[final].outputURL = result.outputURL
                    self.items[final].outputFileSize = outputIdentity.fileSize
                    self.items[final].receipt = CleanReceipt(
                        sourceIdentity: identity,
                        outputIdentity: outputIdentity,
                        selectionRevision: self.items[final].plan?.selectionRevision ?? self.selectionRevision,
                        selectionTitle: activeSelection.title,
                        outcome: receiptOutcome,
                        removed: self.items[final].findings.map(\.displayName),
                        preserved: [],
                        remaining: result.remainingFindings.map(\.displayName),
                        unsupported: [],
                        checks: [
                            CleanVerificationCheck(title: "Source identity",
                                                   detail: "The source did not change during cleanup.",
                                                   outcome: .passed),
                            CleanVerificationCheck(title: "Selected metadata",
                                                   detail: result.remainingFindings.isEmpty
                                                       ? "Selected metadata was re-inspected in the output."
                                                       : "Some selected metadata remains in the output.",
                                                   outcome: result.remainingFindings.isEmpty ? .passed : .failed),
                            CleanVerificationCheck(title: "Encoded media identity",
                                                   detail: "Exact media-sample identity is not checked by the current passthrough path.",
                                                   outcome: .notChecked),
                        ],
                        limitations: [
                            "Metadata inspection combines AVFoundation fields with a bounded container scan.",
                            "Exact encoded track/sample identity is not yet verified.",
                        ])
                    self.items[final].phase = .verifying
                    self.items[final].stage = receiptOutcome.isOrdinarySaveAllowed
                        ? .completed : .failed
                    self.items[final].statusText = result.remainingFindings.isEmpty
                        ? result.verification.label
                        : "Some selected metadata remains; ordinary save is blocked"
                    self.items[final].errorText = nil
                    if self.items[final].id == self.selectedItemID,
                       let outputSize = self.items[final].outputFileSize {
                        self.sizeEstimateItemID = self.items[final].id
                        self.sizeEstimate = MediaSizeEstimate(
                            sourceBytes: max(self.items[final].sourceFileSize, descriptor.fileSize),
                            estimatedBytes: outputSize,
                            basis: .actualOutput,
                            detail: "Measured prepared output from the verified Clean operation.")
                        self.sizeEstimateError = nil
                        self.isEstimatingSize = false
                    }
                    if self.items[final].isSaveReady { prepared += 1 }
                } catch is CancellationError {
                    if let current = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[current].stage = .cancelled
                        self.items[current].statusText = "Cancelled; original is unchanged"
                    }
                    break
                } catch {
                    if let current = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[current].stage = .failed
                        self.items[current].errorText = error.localizedDescription
                        self.items[current].statusText = "Could not clean this video"
                    }
                }
            }
            let wasCancelled = Task.isCancelled
            guard self.processingID == runID else { return }
            self.isCleaning = false
            self.isProcessing = false
            self.processingTask = nil
            self.processingID = nil
            self.statusMessage = wasCancelled
                ? "Cancelled; every original is unchanged."
                : "Prepared \(prepared) of \(work.count) video cop\(work.count == 1 ? "y" : "ies") for saving."
            if !wasCancelled { self.startPendingInspections() }
        }
    }

    private static func makePlan(identity: CleanSourceIdentity,
                                 report: VideoMetadataReport,
                                 selection: VideoCleanSelection,
                                 revision: UInt64) -> CleanPlanSummary {
        let selected = report.findings.filter(selection.matches)
        return CleanPlanSummary(
            sourceIdentity: identity,
            selectionRevision: revision,
            selectionTitle: selection.title,
            detectedEntryCount: report.findings.count,
            selectedEntryCount: selected.count,
            unsupportedReasons: [],
            warnings: report.containerScanWasBounded
                ? ["Raw container inspection is currently bounded."] : [])
    }

    private static func reviewStatus(for findings: [VideoMetadataFinding],
                                     selection: VideoCleanSelection) -> String {
        if selection.isEmpty { return "No groups selected — ready for review" }
        if findings.isEmpty { return "No matching metadata — unchanged copy available" }
        return "\(findings.count) selected metadata item\(findings.count == 1 ? "" : "s") — ready for review"
    }

    /// Runs the same inspect-first video Clean export in a temporary location
    /// and reports its actual bytes. The temporary file is deleted by the
    /// pipeline after the measurement; no user output is created by changing a
    /// scope control.
    func refreshSizeEstimate() {
        sizeEstimateTask?.cancel()
        sizeEstimateGeneration &+= 1
        let generation = sizeEstimateGeneration

        guard let item = selectedItem,
              let identity = item.sourceIdentity,
              let descriptor = item.descriptor,
              let report = item.inspectionReport,
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
        if let outputSize = item.outputFileSize, item.receipt != nil {
            sizeEstimate = MediaSizeEstimate(
                sourceBytes: max(item.sourceFileSize, descriptor.fileSize),
                estimatedBytes: outputSize,
                basis: .actualOutput,
                detail: "Measured prepared output from the verified Clean operation.")
            isEstimatingSize = false
            return
        }

        sizeEstimate = nil
        isEstimatingSize = true
        let itemID = item.id
        let sourceURL = item.sourceURL
        let selectedSelection = item.selection
        sizeEstimateTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                try Task.checkCancellation()
                guard identity.stillMatches(sourceURL) else {
                    throw CleanWorkflowError.sourceChanged
                }
                let estimate = try await VideoCleanPipeline.estimateSize(
                    sourceURL: sourceURL,
                    selection: selectedSelection,
                    inspectedDescriptor: descriptor,
                    inspectedReport: report)
                try Task.checkCancellation()
                guard identity.stillMatches(sourceURL) else {
                    throw CleanWorkflowError.sourceChanged
                }
                guard let self,
                      self.sizeEstimateGeneration == generation,
                      self.selectedItemID == itemID else { return }
                self.sizeEstimate = estimate
                self.sizeEstimateError = nil
                self.isEstimatingSize = false
            } catch is CancellationError {
                // A newer selection or scope owns the next measurement.
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

    private func discardPreparedOutput(at index: Int) {
        cleanup(items[index].outputURL)
        items[index].outputURL = nil
        items[index].outputDescriptor = nil
        items[index].outputFileSize = nil
        items[index].savedTo = nil
        items[index].remainingFindings = []
        items[index].verification = nil
        items[index].receipt = nil
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
