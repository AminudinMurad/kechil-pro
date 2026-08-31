import AppKit
import CoreMedia
import SwiftUI

struct VideoCleanView: View {
    @ObservedObject var model: VideoCleanModel
    var initiallyExpandedFindings = false
    @State private var evidenceExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            VideoCleanScopePicker(selection: Binding(
                get: { model.selection },
                set: { model.selectSelection($0) }),
                isDisabled: model.isCleaning)
            if !model.items.isEmpty {
                Divider()
                CleanReviewBar(media: .video,
                               readyCount: model.readyForReviewCount,
                               plannedChangeCount: model.plannedChangeCount,
                               preparedCount: model.completedCount,
                               isInspecting: model.isProcessing && !model.isCleaning,
                               isCleaning: model.isCleaning,
                               clean: model.cleanAll,
                               cancel: model.cancel)
            }
            Divider()
            Group {
                if model.items.isEmpty {
                    MediaEmptyState(media: .video, tool: .clean,
                                    detail: "MOV, MP4 and M4V · originals are never overwritten",
                                    choose: model.chooseFiles,
                                    pasteURL: { model.add(urls: [$0]) })
                } else {
                    GeometryReader { geometry in
                        HSplitView {
                            list.frame(minWidth: 320, idealWidth: 350)
                                .frame(height: geometry.size.height)
                            inspector.frame(minWidth: 330)
                                .frame(height: geometry.size.height)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.selectedItemID) { _ in
            model.refreshSizeEstimate()
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            BatchOutputHeader(queuedCount: model.items.count, readyCount: model.completedCount,
                              isProcessing: model.isProcessing, save: model.saveAll,
                              selectedName: model.selectedItemID == nil ? nil : model.selectedItem?.displayName,
                              selectedCount: model.selectedItemCount,
                              selectedReadyCount: model.selectedSaveCount,
                              canSaveSelected: model.canSaveSelected, saveSelected: model.saveSelected)
            Divider()
            summary
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.visibleItems) { item in
                        VideoCleanRow(item: item, selected: model.isSelected(item),
                                      select: { model.select(item, modifiers: NSEvent.modifierFlags) },
                                      save: { model.save(item: item) },
                                      remove: { model.remove(item: item) })
                    }
                    if model.visibleItems.isEmpty, let filter = model.activeFilter {
                        VStack(spacing: 6) {
                            Text("No videos carrying \(filter.title)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Button("Show all") { model.selectFilter(nil) }
                                .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }
                .padding(12)
            }
            .kechilScrollbars()
            Divider()
            CleanBatchFooter(readyCount: model.readyForReviewCount,
                             plannedChangeCount: model.plannedChangeCount,
                             preparedCount: model.completedCount,
                             isProcessing: model.isProcessing,
                             clean: model.cleanAll, cancel: model.cancel,
                             canCleanSelected: model.canCleanSelected,
                             selectedHasChanges: model.selectedHasChanges,
                             selectedCount: model.selectedItemCount,
                             cleanSelected: model.cleanSelected)
            if let status = model.statusMessage {
                Divider()
                HStack(spacing: 8) {
                    if model.isProcessing { ProgressView().controlSize(.small) }
                    Text(status).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Spacer()
                    if model.isProcessing { Button("Cancel", action: model.cancel).controlSize(.small) }
                }
                .padding(10)
            }
        }
    }

    private var summary: some View {
        CleanBatchSummary(metrics: videoMetrics,
                          activeFilterTitle: model.activeFilter?.title,
                          initiallyExpanded: initiallyExpandedFindings,
                          clearFilter: { model.selectFilter(nil) }) {
            VStack(alignment: .leading, spacing: 9) {
                if !videoCategories.isEmpty {
                    CleanCategoryChart(categories: videoCategories, unitName: "video")
                }
                videoCallouts
                if !videoCategories.isEmpty {
                    CleanFilterChips(totalCount: model.items.count,
                                     unitName: "video",
                                     categories: videoCategories,
                                     activeID: model.activeFilter?.rawValue) { id in
                        model.selectFilter(id.flatMap(VideoFindingFilter.init(rawValue:)))
                    }
                }
                Text("Total duration \(Self.duration(totalDuration)) · Audio in \(model.audioCount) \(model.audioCount == 1 ? "video" : "videos")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var videoMetrics: [CleanBatchMetric] {
        [
            CleanBatchMetric(model.items.count == 1 ? "video" : "videos",
                             "\(model.items.count)", valueFirst: true),
            CleanBatchMetric("Metadata", "\(model.withMetadataCount)"),
            CleanBatchMetric("Location", "\(model.locationLeakCount)",
                             tone: model.locationLeakCount > 0 ? .critical : .neutral,
                             symbolName: model.locationLeakCount > 0 ? "location.fill" : nil),
            CleanBatchMetric("AI", "\(model.aiGeneratedCount)",
                             tone: model.aiGeneratedCount > 0 ? .serious : .neutral,
                             symbolName: model.aiGeneratedCount > 0 ? "sparkles" : nil),
            CleanBatchMetric("Ready", "\(model.completedCount)"),
        ]
    }

    private var videoCategories: [CleanFindingCategory] {
        model.presentFilters.map { filter in
            CleanFindingCategory(id: filter.rawValue,
                                 title: filter.title,
                                 symbolName: filter.symbolName,
                                 count: model.count(of: filter),
                                 color: color(for: filter),
                                 help: filter.help)
        }
    }

    private func color(for filter: VideoFindingFilter) -> Color {
        switch filter.tone {
        case .critical: return VizPalette.critical
        case .serious: return VizPalette.serious
        case .neutral: return filter == .technical ? .secondary : VizPalette.series
        }
    }

    private var videoCallouts: some View {
        VStack(alignment: .leading, spacing: 3) {
            if model.locationLeakCount > 0 {
                Label("\(model.locationLeakCount) \(model.locationLeakCount == 1 ? "video carries" : "videos carry") location metadata.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(VizPalette.critical)
            }
            if model.aiGeneratedCount > 0 {
                Label("\(model.aiGeneratedCount) \(model.aiGeneratedCount == 1 ? "video declares or identifies" : "videos declare or identify") Generative AI.",
                      systemImage: "sparkles")
                    .foregroundStyle(VizPalette.serious)
            }
            if model.count(of: .contentCredentials) > 0 {
                Text("Content Credentials describe provenance; credentials alone are not proof of AI generation.")
                    .foregroundStyle(.secondary)
            }
            if model.count(of: .technical) > 0 {
                Text("Technical findings describe the media and are not presented as removable metadata.")
                    .foregroundStyle(.secondary)
            }
            Text("Invisible in-frame or in-pixel watermarks such as SynthID are not metadata and are not removed.")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10.5, weight: .medium))
    }

    private var totalDuration: Double {
        model.items.reduce(0) { total, item in
            total + (item.descriptor?.duration.map(CMTimeGetSeconds) ?? 0)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let item = model.selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        if let poster = item.poster {
                            Image(nsImage: poster).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "video").font(.system(size: 34)).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 190)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.055)))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text(item.displayName).font(.system(size: 13, weight: .semibold))
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                    if let descriptor = item.descriptor { descriptorFacts(descriptor) }
                    MediaSizeEstimateCard(
                        title: "Clean output estimate",
                        estimate: model.sizeEstimateItemID == item.id ? model.sizeEstimate : nil,
                        isEstimating: model.sizeEstimateItemID == item.id && model.isEstimatingSize,
                        error: model.sizeEstimateItemID == item.id ? model.sizeEstimateError : nil)
                    statusCard(item)
                    if item.stage == .ready, let plan = item.plan {
                        reviewPlanCard(plan, selection: item.selection)
                    }
                    findings(item)
                    if item.isSaveReady {
                        Button(item.saveActionTitle) {
                            model.save(item: item)
                        }
                            .buttonStyle(KechilSaveButtonStyle())
                            .controlSize(.regular)
                    } else if let saved = item.savedTo {
                        Label("Saved as \(saved.lastPathComponent)", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10.5)).foregroundStyle(.green)
                    }
                }
                .padding(14)
            }
            .kechilScrollbars()
        } else {
            Text("Select a video to inspect it.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func descriptorFacts(_ descriptor: MediaAssetDescriptor) -> some View {
        let seconds = descriptor.duration.map { CMTimeGetSeconds($0) } ?? 0
        return Text(["\(descriptor.displayWidth ?? 0) × \(descriptor.displayHeight ?? 0)",
                     descriptor.videoCodec ?? "Unknown codec",
                     Self.duration(seconds), descriptor.hasAudio ? "Audio" : "No audio"]
            .joined(separator: " · "))
            .font(.system(size: 10.5)).foregroundStyle(.secondary)
    }

    private func statusCard(_ item: VideoQueueItem) -> some View {
        let warning: Bool
        if case .partial = item.verification { warning = true }
        else { warning = item.errorText != nil || item.verification == .containerOnlyFramesUnverified }
        let unchanged = item.verification == .unchanged
        let reviewing = item.stage == .ready || item.stage == .analysing ||
            item.stage == .queued || item.stage == .cancelling
        let accent: Color = reviewing ? .accentColor
            : unchanged ? .secondary : warning ? .orange : .green
        return VStack(alignment: .leading, spacing: 4) {
            Label(item.errorText ?? item.statusText ?? item.stage.cleanLabel,
                  systemImage: reviewing ? "doc.text.magnifyingglass" :
                    unchanged ? "doc.on.doc" : warning ? "exclamationmark.triangle.fill" :
                    (item.stage == .completed || item.stage == .saved ? "checkmark.shield.fill" : "clock"))
                .font(.system(size: 10.5, weight: .semibold))
            if item.verification == .unchanged {
                Text("No cleanup was applied. The source was copied without remuxing or re-encoding. Metadata detection covers exposed fields and a limited container scan.")
                    .font(.system(size: 9.8)).foregroundStyle(.secondary)
            } else if item.verification == .containerOnlyFramesUnverified {
                Text("Passthrough export was used. Kechil checked that the output opens, its duration and display dimensions match, and audio is still present when expected. Selected metadata was rechecked using exposed fields and a limited container scan; exact track and encoded-media identity were not verified.")
                    .font(.system(size: 9.8)).foregroundStyle(.secondary)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(accent.opacity(0.10)))
    }

    private func reviewPlanCard(_ plan: CleanPlanSummary,
                                selection: VideoCleanSelection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("PLANNED CLEANUP", systemImage: "list.bullet.clipboard")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Color.accentColor)
            Text(selection.title)
                .font(.system(size: 11, weight: .semibold))
            Text(plan.hasRequestedChanges
                 ? "\(plan.selectedEntryCount) inspected metadata item\(plan.selectedEntryCount == 1 ? "" : "s") match. No output exists yet; choose Clean Selected to create and verify one."
                 : "No inspected metadata matches this selection. Clean Selected will only prepare an explicitly labelled unchanged copy.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder
    private func findings(_ item: VideoQueueItem) -> some View {
        let detected = item.detectedFindings.isEmpty ? item.findings : item.detectedFindings
        let evidenceFindings = detected.filter(isEvidenceCandidate)
        let noLongerDetected = VideoCleanEvidence.noLongerDetected(
            item.findings, remaining: item.remainingFindings)

        if !evidenceFindings.isEmpty {
            evidenceCard(evidenceFindings)
        }

        if item.findings.isEmpty && item.stage == .completed {
            Text(item.selection.noMatchMessage())
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        } else if item.findings.isEmpty && item.stage == .ready {
            Text(item.selection.isEmpty
                 ? "No groups are selected. Review the source, then prepare an unchanged copy if needed."
                 : "No selected metadata was found. No cleanup will run; an unchanged copy can be prepared explicitly.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        } else if item.receipt != nil, !noLongerDetected.isEmpty {
            Text("NO LONGER DETECTED").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)
            ForEach(noLongerDetected) { finding in
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Text(finding.displayName).font(.system(size: 10.5, weight: .medium)); Spacer(); Text(finding.scope.label).font(.system(size: 9)).foregroundStyle(.tertiary) }
                    Text(finding.valueSummary).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        if !item.remainingFindings.isEmpty {
            Text("STILL PRESENT").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.orange)
            ForEach(item.remainingFindings) { finding in
                Text(finding.displayName).font(.system(size: 10.5))
            }
        }
    }

    private func isEvidenceCandidate(_ finding: VideoMetadataFinding) -> Bool {
        guard !finding.evidence.isEmpty else { return false }
        return VideoCleanEvidence.isProvenance(finding) || VideoCleanEvidence.declaresAISource(finding)
    }

    private func evidenceCard(_ findings: [VideoMetadataFinding]) -> some View {
        let isAI = findings.contains(where: VideoCleanEvidence.declaresAISource)
        let accent = isAI ? VizPalette.critical : Color.orange
        let title = isAI ? "AI SOURCE DECLARATION" : "PROVENANCE EVIDENCE"
        let sourceName = sourceSignalName(for: findings, isAI: isAI)
        let evidence = boundedEvidence(from: findings)

        return VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: isAI ? "sparkles" : "doc.text.magnifyingglass")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(accent)
            Text(isAI ? "Metadata declares an AI source. This declaration has not been independently validated."
                      : "Content Credentials or provenance metadata was detected. This alone does not show AI generation.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(sourceName)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Capsule().fill(accent.opacity(0.12)))
                .foregroundStyle(accent)

            DisclosureGroup(isExpanded: $evidenceExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(evidence) { entry in
                        HStack(alignment: .top, spacing: 7) {
                            Circle().fill(accent).frame(width: 4, height: 4).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.value)
                                    .font(.system(size: 9.3, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(entry.label) · \(entry.source)")
                                    .font(.system(size: 8.7))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Evidence")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(accent.opacity(0.45), lineWidth: 1))
    }

    private func sourceSignalName(for findings: [VideoMetadataFinding], isAI: Bool) -> String {
        guard isAI else { return "Provenance present · not validated" }
        let text = findings.flatMap { finding in
            [finding.identifier, finding.displayName, finding.valueSummary] +
                finding.evidence.map(\.value)
        }.joined(separator: " ").lowercased()
        if text.contains("sora") { return "OpenAI (Sora)" }
        if text.contains("openai") { return "OpenAI" }
        if text.contains("gpt-image") { return "GPT image generation" }
        return "Declared AI source · not validated"
    }

    private func boundedEvidence(from findings: [VideoMetadataFinding]) -> [VideoMetadataEvidence] {
        var seen = Set<String>()
        var output: [VideoMetadataEvidence] = []
        for finding in findings {
            let entries = finding.evidence.isEmpty
                ? [VideoMetadataEvidence(id: UUID(), label: "Value",
                                         value: finding.valueSummary, source: finding.scope.label)]
                : finding.evidence
            for entry in entries {
                let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, seen.insert(value).inserted else { continue }
                output.append(entry)
                if output.count == 8 { return output }
            }
        }
        return output
    }

    private static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct VideoCleanRow: View {
    let item: VideoQueueItem
    let selected: Bool
    let select: () -> Void
    let save: () -> Void
    let remove: () -> Void

    var body: some View {
        // This deliberately follows the Image Clean row's visual hierarchy. Video
        // posters keep their 16:9 shape, while the larger type and padding make
        // titles, review state and technical facts equally quick to scan.
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(item.statusText ?? item.stage.cleanLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let descriptor = item.descriptor {
                    let seconds = descriptor.duration.map(CMTimeGetSeconds) ?? 0
                    Text("\(descriptor.videoCodec ?? "Video") · \(descriptor.displayWidth ?? 0) × \(descriptor.displayHeight ?? 0) · \(Self.duration(seconds))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if item.stage == .analysing || item.stage == .processing || item.stage == .cancelling {
                    ProgressView().controlSize(.small)
                } else if item.savedTo != nil {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                } else if item.isSaveReady {
                    Button(item.verification == .unchanged ? "Save Copy…" : "Save…", action: save)
                        .buttonStyle(KechilSaveButtonStyle())
                        .controlSize(.regular)
                }
                Button(action: remove) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.tertiary)
                    .help("Remove video")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor),
                                  lineWidth: selected ? 2 : 1))
        )
        .contentShape(Rectangle()).onTapGesture(perform: select)
    }

    private var thumbnail: some View {
        Group {
            if let poster = item.poster {
                Image(nsImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "video")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 88, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary, lineWidth: 1))
    }

    private static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct MediaEmptyState: View {
    let media: MediaKind
    let tool: KechilTool
    let detail: String
    let choose: () -> Void
    var pasteURL: ((URL) -> Void)? = nil
    @State private var inputMode: InputMode = .upload
    @State private var pastedValue = ""
    @State private var pasteError: String?
    @State private var isReadingClipboard = false
    @State private var isFetching = false
    @State private var fetchTask: Task<Void, Never>?

    private enum InputMode {
        case upload
        case paste
    }

    init(media: MediaKind, tool: KechilTool, detail: String,
         choose: @escaping () -> Void,
         pasteURL: ((URL) -> Void)? = nil,
         startsWithPasteURL: Bool = false) {
        self.media = media
        self.tool = tool
        self.detail = detail
        self.choose = choose
        self.pasteURL = pasteURL
        _inputMode = State(initialValue: startsWithPasteURL ? .paste : .upload)
    }

    var body: some View {
        VStack(spacing: 10) {
            if pasteURL != nil {
                inputModePicker
            }
            if let pasteURL {
                // Keep both lightweight input surfaces mounted. Replacing the whole
                // subtree made AppKit rebuild the text field and drop-zone controls
                // on every tab click. Both modes occupy the same centred drop-zone
                // position, so switching never leaves the URL form stranded at the
                // top of an otherwise empty workspace.
                ZStack(alignment: .top) {
                    uploadContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .center)
                        .opacity(inputMode == .upload ? 1 : 0)
                        .allowsHitTesting(inputMode == .upload)
                        .disabled(inputMode != .upload)
                        .accessibilityHidden(inputMode != .upload)

                    pasteForm(submit: pasteURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .center)
                        .opacity(inputMode == .paste ? 1 : 0)
                        .allowsHitTesting(inputMode == .paste)
                        .disabled(inputMode != .paste)
                        .accessibilityHidden(inputMode != .paste)
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
            } else {
                uploadContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .center)
            }
        }
        // The shared mode selector is always pinned to this top edge. Only the
        // content below it changes, so switching modes cannot shift the control.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5])).foregroundStyle(.quaternary)))
        .padding(18)
        .onDisappear { fetchTask?.cancel() }
    }

    private var inputModePicker: some View {
        HStack(spacing: 0) {
            modeButton("Upload file", selected: inputMode == .upload) {
                switchInputMode(to: .upload)
            }
            modeButton("Paste URL", selected: inputMode == .paste) {
                switchInputMode(to: .paste)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 1))
        .frame(maxWidth: 600)
    }

    private func modeButton(_ title: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                // A plain SwiftUI button otherwise hit-tests only its rendered text
                // in some AppKit layouts. Make every visible half of the segmented
                // control a concrete target, including the empty space around text.
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? Color(nsColor: .textBackgroundColor) : .clear))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var uploadContent: some View {
        VStack(spacing: 10) {
            Image(systemName: media == .image ? "photo.badge.plus" : "video.badge.plus")
                .font(.system(size: 39, weight: .light)).foregroundStyle(.tertiary)
            Text("Drop \(media.title.lowercased()) or a folder here")
                .font(.system(size: 14, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Processing and saving stay on this Mac.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            Button(media.chooseLabel, action: choose).padding(.top, 3)
        }
    }

    private func pasteForm(submit: @escaping (URL) -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "link.circle")
                .font(.system(size: 39, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Paste a direct \(media.singularTitle) URL")
                .font(.system(size: 14, weight: .medium))

            HStack(spacing: 8) {
                ClipboardURLField(
                    placeholder: media == .video ? "Paste one direct video URL…" :
                        "Paste one direct image URL…",
                    text: $pastedValue,
                    isReadingClipboard: isReadingClipboard,
                    paste: pasteFromClipboard,
                    submit: { submitPastedURL(submit) })
                    .disabled(isFetching)
                Button {
                    submitPastedURL(submit)
                } label: {
                    HStack(spacing: 6) {
                        if isFetching { ProgressView().controlSize(.small) }
                        Text(pasteActionTitle)
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isFetching || pastedValue.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty)
            }
            if let pasteError {
                Label(pasteError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isFetching {
                HStack(spacing: 8) {
                    Text("Downloading \(media.singularTitle) to this Mac…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Button("Stop") { cancelFetch() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10, weight: .medium))
                }
            } else {
                Text(pasteHelperText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Processing and saving stay on this Mac.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 680)
    }

    private var pasteActionTitle: String {
        "Fetch \(media.singularTitle)"
    }

    private var pasteHelperText: String {
        if media == .video {
            return "One direct video URL per run. Webpages and cloud-drive previews are not supported."
        }
        return "One direct image URL per run. Webpages and cloud-drive previews are not supported."
    }

    private func pasteFromClipboard() {
        guard !isReadingClipboard else { return }
        isReadingClipboard = true
        pasteError = nil
        Task {
            let clipboard = await PasteURLService.clipboardTextAsync()
            isReadingClipboard = false
            guard inputMode == .paste else { return }
            guard !clipboard.isEmpty else {
                pasteError = "The clipboard does not contain a URL or path."
                return
            }
            pastedValue = clipboard
        }
    }

    private func submitPastedURL(_ submit: @escaping (URL) -> Void) {
        if let message = PasteURLService.validationMessage(for: pastedValue, media: media) {
            pasteError = message
            return
        }
        guard let source = PasteURLService.source(from: pastedValue) else { return }
        pasteError = nil
        switch source {
        case .local(let url):
            submit(url)
        case .remote(let url):
            isFetching = true
            fetchTask = Task {
                do {
                    let localURL = try await DirectMediaDownloadService.fetch(url, media: media)
                    try Task.checkCancellation()
                    guard inputMode == .paste else {
                        try? FileManager.default.removeItem(at: localURL)
                        return
                    }
                    submit(localURL)
                } catch is CancellationError {
                    // The user stopped the fetch or switched back to Upload.
                } catch {
                    if inputMode == .paste { pasteError = error.localizedDescription }
                }
                isFetching = false
                fetchTask = nil
            }
        }
    }

    private func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
        isFetching = false
    }

    private func switchInputMode(to mode: InputMode) {
        guard inputMode != mode else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if mode == .upload {
                cancelFetch()
            } else {
                pasteError = nil
            }
            inputMode = mode
        }
    }
}
