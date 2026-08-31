import AppKit
import CoreMedia
import SwiftUI

struct VideoOptimizeView: View {
    @ObservedObject var model: VideoOptimizeModel

    var body: some View {
        Group {
            if model.items.isEmpty {
                MediaEmptyState(media: .video, tool: .optimize,
                                detail: "Trim, crop, resize, compress and convert MOV, MP4 or M4V",
                                choose: model.chooseFiles,
                                pasteURL: { model.add(urls: [$0]) })
            } else {
                HSplitView {
                    controls.frame(minWidth: OptimizeWorkspaceLayout.settingsMinimumWidth,
                                   idealWidth: OptimizeWorkspaceLayout.settingsIdealWidth,
                                   maxWidth: OptimizeWorkspaceLayout.settingsMaximumWidth)
                    workspace.frame(minWidth: OptimizeWorkspaceLayout.outputMinimumWidth)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // The estimate is derived from the complete settings value. Explicitly
        // invalidate its card when any setting changes so target-size edits made
        // through the text field or its stepper are reflected immediately.
        .onChange(of: model.settings) { _ in
            model.refreshEstimate()
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            settingsControls
            Divider()
            ToolApplyActions(operation: "Optimize", canProcessAll: model.canApplyAll,
                             canProcessSelected: model.canApplySelected,
                             processAll: model.applyAll, processSelected: model.applySelected,
                             selectedCount: model.selectedItemCount)
                .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var settingsControls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Label("Video settings", systemImage: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                Text("Trim directly below the preview. Crop, resize and export always create a new file.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)

                section("CROP") {
                    Picker("Aspect", selection: $model.settings.cropPreset) {
                        ForEach(VideoCropPreset.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if model.settings.cropPreset != .original {
                        slider("Horizontal focus", value: $model.settings.cropFocusX,
                               range: 0...1, valueText: focusText)
                        slider("Vertical focus", value: $model.settings.cropFocusY,
                               range: 0...1, valueText: focusText)
                    }
                }

                section("FRAME") {
                    Picker("Resolution", selection: $model.settings.resolution) {
                        ForEach(VideoResolutionPreset.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Frame rate", selection: $model.settings.frameRate) {
                        ForEach(VideoFrameRateChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Do not upscale", isOn: $model.settings.noUpscale)
                        .font(.system(size: 11))
                }

                section("FILE SIZE") {
                    Picker("Mode", selection: $model.settings.sizeMode) {
                        ForEach(VideoSizeMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    if model.settings.sizeMode == .quality {
                        slider("Quality", value: $model.settings.quality, range: 0.1...1,
                               valueText: { "\(Int(($0 * 100).rounded()))%" })
                    } else {
                        numericField("Maximum", value: $model.settings.targetMegabytes, suffix: "MB")
                        Picker("Priority", selection: $model.settings.priority) {
                            ForEach(VideoQualityPriority.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Text("Kechil budgets bitrate from the trimmed duration. Smart may lower resolution to avoid severe blockiness; Keep resolution uses the requested frame size and accepts lower visual quality.")
                            .font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                }

                section("ENCODING") {
                    Picker("Codec", selection: $model.settings.codec) {
                        ForEach(VideoCodecChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Audio", selection: $model.settings.audioPolicy) {
                        ForEach(VideoAudioPolicy.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if model.settings.audioPolicy == .keep {
                        Picker("Audio rate", selection: $model.settings.audioBitrateKbps) {
                            ForEach([96, 128, 192, 256], id: \.self) { Text("\($0) kbps").tag($0) }
                        }
                    }
                    Picker("Container", selection: $model.settings.container) {
                        ForEach(VideoContainerChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                estimateCard

            }
            .padding(14)
        }
        .kechilScrollbars()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var workspace: some View {
        GeometryReader { geometry in
            let usesCompactPreview = geometry.size.height < 620
            VStack(spacing: 0) {
                // Reserve space for the output header and a usable queue at the
                // minimum window height. Trim remains reachable by scrolling here.
                ScrollView {
                    preview(compact: usesCompactPreview)
                }
                .kechilScrollbars()
                .frame(height: max(180, min(usesCompactPreview ? 440 : 520,
                                           geometry.size.height - 180)))
                Divider()
                queueHeader
                Divider()
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.items) { item in
                            VideoOptimizeRow(item: item, selected: model.isSelected(item),
                                             select: { model.select(item, modifiers: NSEvent.modifierFlags) },
                                             save: { model.save(item: item) },
                                             remove: { model.remove(item: item) })
                        }
                    }
                    .padding(12)
                }
                .kechilScrollbars()
                if let message = model.statusMessage {
                    Divider()
                    HStack(spacing: 8) {
                        if model.isProcessing { ProgressView().controlSize(.small) }
                        Text(message).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        Spacer()
                        if model.isProcessing { Button("Cancel", action: model.cancel).controlSize(.small) }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func preview(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            HStack(spacing: 7) {
                Label("Video preview", systemImage: "play.rectangle")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                if let duration = sourceDuration {
                    Text(Self.duration(duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.92))
                if let player = model.player {
                    VideoPreviewSurface(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .allowsHitTesting(false)
                } else if let poster = model.selectedItem?.poster {
                    Image(nsImage: poster).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "video").font(.system(size: 34)).foregroundStyle(.white.opacity(0.4))
                }
                MediaCropGuide(aspect: model.settings.cropPreset.ratio.map { CGFloat($0) },
                               sourceAspect: model.selectedItem?.poster.map { $0.size.width / $0.size.height },
                               focusX: model.settings.cropFocusX,
                               focusY: model.settings.cropFocusY)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 160 : 225)
            if let duration = sourceDuration {
                playbackControls(duration: duration)
                VideoTrimRangeControl(duration: duration,
                                      startSeconds: $model.settings.trimStartSeconds,
                                      endSeconds: $model.settings.trimEndSeconds,
                                      playheadSeconds: $model.previewSeconds,
                                      refreshPreview: model.refreshPreview)
            }
            if let item = model.selectedItem, let descriptor = item.descriptor {
                VStack(spacing: 3) {
                    Text("\(item.displayName) · \(descriptor.displayWidth ?? 0) × \(descriptor.displayHeight ?? 0) · \(descriptor.videoCodec ?? "Video")")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if descriptor.isHDR {
                        Label("HDR export is blocked until colour-space preservation is verified",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 9.5)).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(compact ? 10 : 12)
    }

    private func playbackControls(duration: Double) -> some View {
        HStack(spacing: 8) {
            Button { model.skipPreview(by: -5) } label: {
                Image(systemName: "gobackward.5")
            }
            .help("Go back 5 seconds")
            .accessibilityLabel("Go back 5 seconds")

            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 12)
            }
            .help(model.isPlaying ? "Pause preview" : "Play preview")
            .accessibilityLabel(model.isPlaying ? "Pause preview" : "Play preview")

            Button { model.skipPreview(by: 5) } label: {
                Image(systemName: "goforward.5")
            }
            .help("Go forward 5 seconds")
            .accessibilityLabel("Go forward 5 seconds")

            Text(Self.playbackTime(model.previewSeconds))
                .frame(width: 42, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { min(max(0, model.previewSeconds), duration) },
                    set: model.setPreviewPosition
                ),
                in: 0...max(0.01, duration),
                onEditingChanged: model.previewScrubbingChanged
            )
            .accessibilityLabel("Playback position")
            .accessibilityValue(Self.playbackTime(model.previewSeconds))

            Text(Self.playbackTime(duration))
                .frame(width: 42, alignment: .leading)

            Button(action: model.toggleMute) {
                Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 15)
            }
            .help(model.isMuted ? "Unmute preview" : "Mute preview")
            .accessibilityLabel(model.isMuted ? "Unmute preview" : "Mute preview")
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(minHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var queueHeader: some View {
        BatchOutputHeader(title: "Video queue", queuedCount: model.items.count,
                          readyCount: model.completedCount, isProcessing: model.isProcessing,
                          save: model.saveAll, selectedName: model.selectedItemID == nil ? nil : model.selectedItem?.displayName,
                          selectedCount: model.selectedItemCount,
                          selectedReadyCount: model.selectedSaveCount,
                          canSaveSelected: model.canSaveSelected, saveSelected: model.saveSelected)
    }

    @ViewBuilder
    private var estimateCard: some View {
        if let plan = model.selectedPlan {
            VStack(alignment: .leading, spacing: 4) {
                Text("ESTIMATED OUTPUT").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                Text("\(plan.width) × \(plan.height) · \(String(format: "%.0f", plan.frameRate)) fps")
                    .font(.system(size: 11, weight: .semibold))
                Text("About \(Self.megabytes(plan.estimatedBytes)) · \(Self.bitrate(plan.videoBitrate)) video")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                if plan.resolutionWasReducedForTarget {
                    Label("Smart reduced resolution to protect quality", systemImage: "info.circle")
                        .font(.system(size: 9.5)).foregroundStyle(.blue)
                }
                if plan.targetBytes != nil {
                    Text("Target size is an estimate; container overhead and source complexity can change the final size.")
                        .font(.system(size: 9.2)).foregroundStyle(.tertiary)
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .id(model.estimateRevision)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
        } else {
            Label("Choose a valid trim range and target size.", systemImage: "exclamationmark.triangle")
                .font(.system(size: 9.8)).foregroundStyle(.orange)
        }
    }

    private var sourceDuration: Double? {
        guard let time = model.selectedItem?.descriptor?.duration else { return nil }
        let value = CMTimeGetSeconds(time)
        return value.isFinite && value > 0 ? value : nil
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)
            content()
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .textBackgroundColor)))
    }

    private func numericField(_ label: String, value: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).fixedSize(horizontal: true, vertical: false)
            Spacer()
            KechilNumericStepperField(label: label, value: value, step: 1,
                                      lowerBound: 1, upperBound: 100_000)
                .frame(width: 104)
            Text(suffix).font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
        }
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
                        valueText: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(label); Spacer(); Text(valueText(value.wrappedValue)).foregroundStyle(.secondary) }
                .font(.system(size: 10.5))
            Slider(value: value, in: range)
        }
    }

    private func focusText(_ value: Double) -> String {
        if value < 0.34 { return "Start" }
        if value > 0.66 { return "End" }
        return "Centre"
    }

    private static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func playbackTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–:––" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    private static func bitrate(_ bits: Int) -> String {
        bits >= 1_000_000 ? String(format: "%.1f Mbps", Double(bits) / 1_000_000) : "\(bits / 1_000) kbps"
    }
}

private struct VideoOptimizeRow: View {
    let item: VideoQueueItem
    let selected: Bool
    let select: () -> Void
    let save: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let poster = item.poster { Image(nsImage: poster).resizable().aspectRatio(contentMode: .fill) }
                else { Image(systemName: "video").foregroundStyle(.tertiary) }
            }
            .frame(width: 72, height: 45).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName).font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(item.errorText ?? item.statusText ?? item.stage.label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(item.errorText == nil ? Color.secondary : Color.red)
                if let output = item.outputFileSize {
                    let outputFrame = item.outputDescriptor.map {
                        " · \($0.displayWidth ?? 0) × \($0.displayHeight ?? 0)"
                    } ?? ""
                    Text("\(Self.megabytes(item.sourceFileSize)) → \(Self.megabytes(output))\(outputFrame)")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                } else if let descriptor = item.descriptor {
                    Text("Original: \(descriptor.displayWidth ?? 0) × \(descriptor.displayHeight ?? 0) · \(descriptor.videoCodec ?? "Video")")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                if let progress = item.progress, item.stage == .processing {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(maxWidth: 150)
                }
            }
            Spacer(minLength: 4)
            if item.isSaveReady {
                Button("Save…", action: save)
                    .buttonStyle(KechilSaveButtonStyle(width: KechilActionMetrics.saveButtonWidth))
                    .controlSize(.regular)
            }
            Button(action: remove) { Image(systemName: "xmark") }
                .buttonStyle(.borderless).foregroundStyle(.tertiary).help("Remove video")
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor),
                              lineWidth: selected ? 2 : 1)))
        .contentShape(Rectangle()).onTapGesture(perform: select)
    }

    private static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }
}
