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
                    controls.frame(minWidth: 260, idealWidth: 280, maxWidth: 310)
                    workspace.frame(minWidth: 450)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Label("Video settings", systemImage: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                Text("The preview shows the selected crop and frame. Export always creates a new file.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)

                section("TRIM") {
                    if let duration = sourceDuration {
                        VideoTrimRangeControl(duration: duration,
                                              startSeconds: $model.settings.trimStartSeconds,
                                              endSeconds: $model.settings.trimEndSeconds,
                                              playheadSeconds: $model.previewSeconds,
                                              refreshPreview: model.refreshPreview)
                    } else {
                        Label("Reading the source duration…", systemImage: "clock")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }

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

                Button(action: model.applyAll) {
                    Label("Apply to All Videos", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isProcessing || model.selectedPlan == nil)
            }
            .padding(14)
        }
        .kechilScrollbars()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            queueHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.items) { item in
                        VideoOptimizeRow(item: item, selected: model.selectedItemID == item.id,
                                         select: { model.select(item) },
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

    private var preview: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.92))
                if let poster = model.selectedItem?.poster {
                    Image(nsImage: poster).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "video").font(.system(size: 34)).foregroundStyle(.white.opacity(0.4))
                }
                MediaCropGuide(aspect: model.settings.cropPreset.ratio.map { CGFloat($0) },
                               sourceAspect: model.selectedItem?.poster.map { $0.size.width / $0.size.height },
                               focusX: model.settings.cropFocusX,
                               focusY: model.settings.cropFocusY)
            }
            .frame(maxWidth: .infinity).frame(height: 225)
            if let duration = sourceDuration {
                HStack(spacing: 8) {
                    Text(Self.duration(model.previewSeconds)).monospacedDigit()
                    Slider(value: $model.previewSeconds, in: 0...max(0.01, duration),
                           onEditingChanged: { editing in if !editing { model.refreshPreview() } })
                    Text(Self.duration(duration)).monospacedDigit()
                }
                .font(.system(size: 9.5)).foregroundStyle(.secondary)
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
        .padding(12)
    }

    private var queueHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Video queue").font(.system(size: 12.5, weight: .semibold))
                Text("\(model.items.count) queued · \(model.completedCount) ready to save")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
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
            Text(label).font(.system(size: 11))
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
                .multilineTextAlignment(.trailing).frame(width: 64)
            Text(suffix).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
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
                }
                if let progress = item.progress, item.stage == .processing {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(maxWidth: 150)
                }
            }
            Spacer(minLength: 4)
            if item.isSaveReady { Button("Save…", action: save).controlSize(.small) }
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
