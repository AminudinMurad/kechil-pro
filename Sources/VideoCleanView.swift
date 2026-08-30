import CoreMedia
import SwiftUI

struct VideoCleanView: View {
    @ObservedObject var model: VideoCleanModel
    @State private var evidenceExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            VideoCleanScopePicker(selection: Binding(
                get: { model.selection },
                set: { model.selectSelection($0) }),
                isDisabled: model.isProcessing)
            Divider()
            Group {
                if model.items.isEmpty {
                    MediaEmptyState(media: .video, tool: .clean,
                                    detail: "MOV, MP4 and M4V · originals are never overwritten",
                                    choose: model.chooseFiles,
                                    pasteURL: { model.add(urls: [$0]) })
                } else {
                    HSplitView {
                        list.frame(minWidth: 320, idealWidth: 350)
                        inspector.frame(minWidth: 330)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var list: some View {
        VStack(spacing: 0) {
            summary
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.items) { item in
                        VideoCleanRow(item: item, selected: model.selectedItemID == item.id,
                                      select: { model.selectedItemID = item.id },
                                      remove: { model.remove(item: item) })
                    }
                }
                .padding(12)
            }
            .kechilScrollbars()
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
        HStack(spacing: 12) {
            metric("Videos", "\(model.items.count)")
            metric("With metadata", "\(model.items.filter { !$0.detectedFindings.isEmpty || !$0.findings.isEmpty }.count)")
            metric("Duration", Self.duration(totalDuration))
            metric("With audio", "\(model.items.filter { $0.descriptor?.hasAudio == true }.count)")
            metric("Cleaned", "\(model.completedCount)")
            Spacer()
        }
        .padding(12)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 14, weight: .bold)).monospacedDigit()
            Text(title).font(.system(size: 8.5)).foregroundStyle(.secondary).lineLimit(1)
        }
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
                    statusCard(item)
                    findings(item)
                    if item.isSaveReady {
                        Button("Save Clean Copy…") { model.save(item: item) }
                            .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
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
        if case .partial = item.verification { warning = true } else { warning = item.errorText != nil }
        return VStack(alignment: .leading, spacing: 4) {
            Label(item.errorText ?? item.statusText ?? item.stage.label,
                  systemImage: warning ? "exclamationmark.triangle.fill" :
                    (item.stage == .completed || item.stage == .saved ? "checkmark.shield.fill" : "clock"))
                .font(.system(size: 10.5, weight: .semibold))
            if item.verification == .containerOnlyFramesUnverified {
                Text("The container was rewritten without re-encoding. Kechil verified playback, timing, dimensions, tracks and supported metadata; encoded-frame identity was not cryptographically compared.")
                    .font(.system(size: 9.8)).foregroundStyle(.secondary)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill((warning ? Color.orange : Color.green).opacity(0.10)))
    }

    @ViewBuilder
    private func findings(_ item: VideoQueueItem) -> some View {
        let detected = item.detectedFindings.isEmpty ? item.findings : item.detectedFindings
        let evidenceFindings = detected.filter(isEvidenceCandidate)

        if !evidenceFindings.isEmpty {
            evidenceCard(evidenceFindings)
        }

        if item.findings.isEmpty && item.stage == .completed {
            Text(item.selection.noMatchMessage())
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        } else if !item.findings.isEmpty {
            Text("DETECTED AND REMOVED").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)
            ForEach(item.findings) { finding in
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
        if finding.category == .provenance { return true }
        let text = ([finding.identifier, finding.displayName, finding.valueSummary] +
            finding.evidence.map(\.value)).joined(separator: " ").lowercased()
        return ["openai", "sora", "generative", "ai ", "gpt-", "c2pa", "provenance"]
            .contains { text.contains($0) }
    }

    private func evidenceCard(_ findings: [VideoMetadataFinding]) -> some View {
        let isAI = findings.contains { finding in
            let text = ([finding.identifier, finding.displayName, finding.valueSummary] +
                finding.evidence.map(\.value)).joined(separator: " ").lowercased()
            return ["openai", "sora", "generative", "ai ", "gpt-", "c2pa", "provenance"]
                .contains { text.contains($0) }
        }
        let accent = isAI ? VizPalette.critical : Color.orange
        let title = isAI ? "AI SOURCE SIGNALS" : "SOURCE EVIDENCE"
        let sourceName = sourceSignalName(for: findings, isAI: isAI)
        let evidence = boundedEvidence(from: findings)

        return VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: isAI ? "sparkles" : "doc.text.magnifyingglass")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(accent)
            Text(isAI ? "Readable AI provenance was found in the original file."
                      : "Readable metadata evidence was found in the original file.")
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
        let text = findings.flatMap { finding in
            [finding.identifier, finding.displayName, finding.valueSummary] +
                finding.evidence.map(\.value)
        }.joined(separator: " ").lowercased()
        if text.contains("sora") { return "OpenAI (Sora)" }
        if text.contains("openai") { return "OpenAI" }
        if text.contains("gpt-image") { return "GPT image generation" }
        return isAI ? "Generative provenance" : "Metadata carrier"
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
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let poster = item.poster { Image(nsImage: poster).resizable().aspectRatio(contentMode: .fill) }
                else { Image(systemName: "video").foregroundStyle(.tertiary) }
            }
            .frame(width: 70, height: 44).clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName).font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(item.statusText ?? item.stage.label).font(.system(size: 9.5)).foregroundStyle(.secondary)
                if let descriptor = item.descriptor {
                    let seconds = descriptor.duration.map(CMTimeGetSeconds) ?? 0
                    Text("\(descriptor.videoCodec ?? "Video") · \(descriptor.displayWidth ?? 0) × \(descriptor.displayHeight ?? 0) · \(Self.duration(seconds))")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
            if item.stage == .analysing || item.stage == .processing { ProgressView().controlSize(.small) }
            Button(action: remove) { Image(systemName: "xmark") }.buttonStyle(.borderless)
                .foregroundStyle(.tertiary).help("Remove video")
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor),
                              lineWidth: selected ? 2 : 1)))
        .contentShape(Rectangle()).onTapGesture(perform: select)
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
            if inputMode == .paste, let pasteURL {
                pasteForm(submit: pasteURL)
            } else {
                uploadContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: inputMode == .paste ? .top : .center)
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
                cancelFetch()
                inputMode = .upload
            }
            modeButton("Paste URL", selected: inputMode == .paste) {
                inputMode = .paste
                pasteError = nil
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
                .background(RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? Color(nsColor: .textBackgroundColor) : .clear))
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 8) {
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
}
