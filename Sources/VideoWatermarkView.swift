import AppKit
import CoreMedia
import SwiftUI

struct VideoWatermarkView: View {
    @ObservedObject var model: VideoWatermarkModel
    @State private var showsWatermark = true

    var body: some View {
        Group {
            if model.items.isEmpty {
                MediaEmptyState(media: .video, tool: .watermark,
                                detail: "Preview a static text or logo mark, then export a new video",
                                choose: model.chooseFiles,
                                pasteURL: { model.add(urls: [$0]) })
            } else {
                HSplitView {
                    controls.frame(minWidth: 265, idealWidth: 295, maxWidth: 330)
                    workspace.frame(minWidth: 450)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.kind) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.text) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.logoData) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.opacity) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.rotation) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.scalePercent) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.position) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.tiled) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.textColor) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.marginPercent) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.tileGapPercent) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.shadowEnabled) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.shadowOpacity) { _ in model.refreshPreviewOverlay() }
        .onChange(of: model.selectedItemID) { _ in model.refreshSizeEstimate() }
        .onChange(of: model.sizeEstimateSettingsKey) { _ in
            model.refreshSizeEstimate()
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            settingsControls
            Divider()
            ToolApplyActions(operation: "Watermark", canProcessAll: model.canApply,
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
                Label("Watermark settings", systemImage: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                Text("A static visible mark is rendered into every video frame. The original is never overwritten.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)

                section("SOURCE") {
                    Picker("Kind", selection: $model.kind) {
                        ForEach(WatermarkKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    if model.kind == .text {
                        TextField("Watermark text", text: $model.text)
                        ColorPicker("Text colour", selection: textColorBinding,
                                    supportsOpacity: true).font(.system(size: 11))
                        Toggle("Text shadow", isOn: $model.shadowEnabled)
                            .font(.system(size: 11))
                        if model.shadowEnabled {
                            slider("Shadow", value: $model.shadowOpacity, range: 0...1,
                                   valueText: { "\(Int(($0 * 100).rounded()))%" })
                        }
                    } else {
                        HStack {
                            Text(model.logoName ?? "No logo selected")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Choose…", action: model.chooseLogo).controlSize(.small)
                        }
                        if model.logoData == nil {
                            Label("Choose a logo before applying", systemImage: "exclamationmark.circle")
                                .font(.system(size: 9.5)).foregroundStyle(.orange)
                        }
                    }
                }

                section("APPEARANCE") {
                    slider("Opacity", value: $model.opacity, range: 0.05...1,
                           valueText: { "\(Int(($0 * 100).rounded()))%" })
                    slider("Rotation", value: $model.rotation, range: -90...90,
                           valueText: { "\(Int($0.rounded()))°" }, step: 1)
                    slider("Scale", value: $model.scalePercent, range: 1...40,
                           valueText: { "\(Int($0.rounded()))%" }, step: 1)
                }

                section("PLACEMENT") {
                    WatermarkAnchorPicker(selection: $model.position)
                    slider("Safe margin", value: $model.marginPercent, range: 0...10,
                           valueText: { "\(String(format: "%.1f", $0))%" })
                    Toggle("Repeat as a tiled pattern", isOn: $model.tiled)
                        .font(.system(size: 11))
                    if model.tiled {
                        slider("Tile gap", value: $model.tileGapPercent, range: 0...20,
                               valueText: { "\(Int($0.rounded()))%" }, step: 1)
                    }
                }

                section("OUTPUT") {
                    Picker("Codec", selection: $model.codec) {
                        ForEach(VideoCodecChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Audio", selection: $model.audioPolicy) {
                        ForEach(VideoAudioPolicy.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Container", selection: $model.container) {
                        ForEach(VideoContainerChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    slider("Quality", value: $model.quality, range: 0.35...1,
                           valueText: { "\(Int(($0 * 100).rounded()))%" })
                    Text("Watermarking requires re-encoding. Kechil removes supported container metadata and verifies the exported copy.")
                        .font(.system(size: 9.5)).foregroundStyle(.secondary)
                }

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
                        VideoWatermarkRow(item: item, selected: model.isSelected(item),
                            select: { model.select(item, modifiers: NSEvent.modifierFlags) }, save: { model.save(item: item) },
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
            HStack {
                Picker("Preview", selection: $showsWatermark) {
                    Text("Original").tag(false)
                    Text("Watermarked").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 210)
                Spacer()
                if model.isPreviewRendering { ProgressView().controlSize(.small) }
                Label("Full duration", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.black)
                    if let player = model.player {
                        VideoPreviewSurface(player: player)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .allowsHitTesting(false)
                    } else if let poster = model.selectedItem?.poster {
                        Image(nsImage: poster).resizable().aspectRatio(contentMode: .fit)
                    }
                    if showsWatermark, let overlay = model.previewOverlay {
                        Image(nsImage: overlay).resizable().aspectRatio(contentMode: .fit)
                            .allowsHitTesting(false)
                    }
                    if showsWatermark, let error = model.previewError {
                        Text(error).font(.system(size: 10.5)).foregroundStyle(.white)
                            .padding(8).background(.black.opacity(0.65)).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    if showsWatermark {
                        Color.clear.contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                                model.position = WatermarkPosition.nearest(to: value.location,
                                                                           in: proxy.size)
                            })
                            .help("Drag to snap the watermark to one of nine positions")
                    }
                }
            }
            .frame(maxWidth: .infinity).frame(height: 245)
            playbackControls
            HStack {
                Text(model.selectedItem?.displayName ?? "Select a video")
                    .font(.system(size: 10.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("Preview overlay and export share one renderer")
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
            if model.selectedItem?.descriptor?.isHDR == true {
                Label("HDR export is blocked until colour-space preservation is verified",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5)).foregroundStyle(.orange)
            }
            MediaSizeEstimateCard(
                title: "Watermarked output estimate",
                estimate: model.sizeEstimateItemID == model.selectedItem?.id
                    ? model.sizeEstimate : nil,
                isEstimating: model.sizeEstimateItemID == model.selectedItem?.id &&
                    model.isEstimatingSize,
                error: model.sizeEstimateItemID == model.selectedItem?.id
                    ? model.sizeEstimateError : nil)
        }
        .padding(12)
    }

    private var playbackControls: some View {
        let duration = sourceDuration ?? 0
        return HStack(spacing: 8) {
            Button(action: model.togglePlayback) { Image(systemName: "playpause.fill") }
                .buttonStyle(.borderless).help("Play or pause preview")
            Text(Self.duration(model.previewSeconds)).monospacedDigit()
            Slider(value: $model.previewSeconds, in: 0...max(0.01, duration),
                   onEditingChanged: { editing in if !editing { model.seekPreview() } })
            Text(Self.duration(duration)).monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .controlSize(.regular)
        .font(.system(size: 11, design: .monospaced))
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

    private var sourceDuration: Double? {
        guard let time = model.selectedItem?.descriptor?.duration else { return nil }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)
            content()
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .textBackgroundColor)))
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
                        valueText: @escaping (Double) -> String, step: Double = 0.01) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(label); Spacer(); Text(valueText(value.wrappedValue)).foregroundStyle(.secondary) }
                .font(.system(size: 10.5))
            Slider(value: quantized(value, step: step), in: range)
        }
    }

    private func quantized(_ value: Binding<Double>, step: Double) -> Binding<Double> {
        Binding(get: { value.wrappedValue }, set: { proposed in
            value.wrappedValue = (proposed / step).rounded() * step
        })
    }

    private static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var textColorBinding: Binding<Color> {
        Binding(get: {
            Color(red: model.textColor.red, green: model.textColor.green,
                  blue: model.textColor.blue, opacity: model.textColor.alpha)
        }, set: { colour in
            guard let converted = NSColor(colour).usingColorSpace(.sRGB) else { return }
            model.textColor = RGBAColor(red: converted.redComponent,
                green: converted.greenComponent, blue: converted.blueComponent,
                alpha: converted.alphaComponent)
        })
    }
}

private struct VideoWatermarkRow: View {
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
                if let progress = item.progress, item.stage == .processing {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(maxWidth: 150)
                } else if let output = item.outputDescriptor {
                    Text("\(output.displayWidth ?? 0) × \(output.displayHeight ?? 0) · \(output.videoCodec ?? "Video")")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                } else if let descriptor = item.descriptor {
                    Text("Original: \(descriptor.displayWidth ?? 0) × \(descriptor.displayHeight ?? 0) · \(descriptor.videoCodec ?? "Video")")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
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
}
