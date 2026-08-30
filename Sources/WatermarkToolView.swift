import AppKit
import SwiftUI

struct WatermarkToolView: View {
    @ObservedObject var model: TransformModel
    @State private var previewMode = WatermarkPreviewMode.watermarked

    var body: some View {
        HSplitView {
            controls.frame(minWidth: 265, idealWidth: 305, maxWidth: 345)
            previewAndQueue.frame(minWidth: 470)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.watermarkText) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkKind) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkLogoData) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkOpacity) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkRotation) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkScalePercent) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkPosition) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkTiled) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkTextColor) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkMarginPercent) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkTileGapPercent) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkShadowEnabled) { _ in model.refreshWatermarkPreview() }
        .onChange(of: model.watermarkShadowOpacity) { _ in model.refreshWatermarkPreview() }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Watermark settings", systemImage: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                Text("Watermarks re-render pixels. Metadata is removed from every output before saving.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                section("Presets") {
                    if model.watermarkPresetNames.isEmpty {
                        Text("Save the current watermark settings as a reusable preset.")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    } else {
                        Picker("Preset", selection: $model.selectedWatermarkPreset) {
                            Text("Choose a preset").tag("")
                            ForEach(model.watermarkPresetNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .onChange(of: model.selectedWatermarkPreset) { name in
                            if !name.isEmpty { model.applyWatermarkPreset(named: name) }
                        }
                    }
                    HStack {
                        Button("Save Current…") { model.saveWatermarkPreset() }
                        if !model.selectedWatermarkPreset.isEmpty {
                            Button(role: .destructive) { model.deleteSelectedWatermarkPreset() } label: {
                                Image(systemName: "trash")
                            }
                            .help("Delete selected preset")
                        }
                    }
                }

                section("Watermark") {
                    Picker("Kind", selection: $model.watermarkKind) {
                        ForEach(WatermarkKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                    }
                    .pickerStyle(.segmented)

                    if model.watermarkKind == .text {
                        TextField("Watermark text", text: $model.watermarkText)
                        ColorPicker("Text colour", selection: textColorBinding,
                                    supportsOpacity: true)
                            .font(.system(size: 11.5))
                        Toggle("Text shadow", isOn: $model.watermarkShadowEnabled)
                            .font(.system(size: 11.5))
                        if model.watermarkShadowEnabled {
                            slider("Shadow", value: $model.watermarkShadowOpacity, range: 0...1,
                                   valueText: { "\(Int(($0 * 100).rounded()))%" })
                        }
                    } else {
                        HStack {
                            Text(model.watermarkLogoName ?? "No logo selected")
                                .font(.system(size: 11.5))
                                .foregroundStyle(model.watermarkLogoData == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Choose…") { model.chooseWatermarkLogo() }
                                .controlSize(.small)
                        }
                    }

                    slider("Opacity", value: $model.watermarkOpacity, range: 0.05...1,
                           valueText: { "\(Int(($0 * 100).rounded()))%" })
                    slider("Rotation", value: $model.watermarkRotation, range: -90...90,
                           valueText: { "\(Int($0.rounded()))°" }, step: 1)
                    slider("Scale", value: $model.watermarkScalePercent, range: 1...40,
                           valueText: { "\(Int($0.rounded()))% of image" }, step: 1)

                    WatermarkAnchorPicker(selection: $model.watermarkPosition)
                    slider("Safe margin", value: $model.watermarkMarginPercent, range: 0...10,
                           valueText: { "\(String(format: "%.1f", $0))%" })
                    Toggle("Repeat as a tiled pattern", isOn: $model.watermarkTiled)
                        .font(.system(size: 11.5))
                    if model.watermarkTiled {
                        slider("Tile gap", value: $model.watermarkTileGapPercent, range: 0...20,
                               valueText: { "\(Int($0.rounded()))%" }, step: 1)
                    }
                }

                section("Output") {
                    Picker("Format", selection: $model.outputFormat) {
                        ForEach(ImageOutputFormat.allCases) { format in Text(format.rawValue).tag(format) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    if model.outputFormat == .webp {
                        Toggle("Lossless WebP", isOn: $model.webPLossless)
                            .font(.system(size: 11.5))
                    }
                    if model.outputFormat.qualityAffectsSize &&
                        !(model.outputFormat == .webp && model.webPLossless) {
                        slider("Quality floor", value: $model.qualityFloor, range: 0...100,
                               valueText: { "\(Int($0.rounded()))" }, step: 1)
                        slider("Quality ceiling", value: $model.qualityCeiling, range: 0...100,
                               valueText: { "\(Int($0.rounded()))" }, step: 1)
                    }
                    HStack {
                        Text("Target KB").font(.system(size: 11.5))
                        Spacer()
                        TextField("Off", value: $model.targetKilobytes,
                                  format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 68)
                    }
                }

                Button {
                    model.reprocessAll()
                } label: {
                    Label("Apply Watermark to All", systemImage: "seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.items.isEmpty || model.isProcessing ||
                          (model.watermarkKind == .logo && model.watermarkLogoData == nil))

                Text("Settings apply to new images immediately. Use Apply Watermark to All to re-render this queue.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .kechilScrollbars()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var previewAndQueue: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watermarked output").font(.system(size: 13, weight: .semibold))
                    Text("\(model.items.count) queued · \(model.completedCount) ready")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isProcessing { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()

            if model.items.isEmpty {
                MediaEmptyState(media: .image, tool: .watermark,
                                detail: "Choose text or a logo, then export a new image",
                                choose: model.chooseFiles,
                                pasteURL: { model.add(urls: [$0]) })
            } else {
                watermarkPreview
                Divider()
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.items) { item in
                            WatermarkItemRow(item: item, selected: model.selectedItemID == item.id,
                                             onSelect: { model.select(item) },
                                             onSave: { model.save(item: item) },
                                             onRemove: { model.remove(item: item) })
                        }
                    }
                    .padding(14)
                }
                .kechilScrollbars()
            }

            if let status = model.statusMessage {
                Divider()
                Text(status).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var watermarkPreview: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Preview", selection: $previewMode) {
                    ForEach(WatermarkPreviewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 210)
                Spacer()
                if model.isWatermarkPreviewRendering { ProgressView().controlSize(.small) }
                Button("Reset Placement") { model.watermarkPosition = .bottomRight }
                    .controlSize(.small)
            }
            GeometryReader { proxy in
                ZStack {
                    CheckerboardBackground()
                    Group {
                        if previewMode == .original, let image = model.selectedItem?.sourceThumbnail {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        } else if previewMode == .watermarked, let image = model.watermarkPreview {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        } else if let error = model.watermarkPreviewError {
                            VStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                Text(error).font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(8)
                }
                .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                    model.watermarkPosition = WatermarkPosition.nearest(to: value.location,
                                                                        in: proxy.size)
                })
            }
            .frame(maxWidth: .infinity).frame(height: 235)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
            HStack {
                Text(model.selectedItem?.displayName ?? "Select an image")
                    .font(.system(size: 10.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("Preview uses the same overlay renderer as export")
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .textBackgroundColor)))
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
                        valueText: @escaping (Double) -> String, step: Double = 0.01) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 11.5))
                Spacer()
                Text(valueText(value.wrappedValue)).font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private var textColorBinding: Binding<Color> {
        Binding(get: {
            Color(red: model.watermarkTextColor.red,
                  green: model.watermarkTextColor.green,
                  blue: model.watermarkTextColor.blue,
                  opacity: model.watermarkTextColor.alpha)
        }, set: { colour in
            guard let converted = NSColor(colour).usingColorSpace(.sRGB) else { return }
            model.watermarkTextColor = RGBAColor(red: converted.redComponent,
                green: converted.greenComponent, blue: converted.blueComponent,
                alpha: converted.alphaComponent)
        })
    }
}

private struct WatermarkItemRow: View {
    let item: TransformItem
    let selected: Bool
    let onSelect: () -> Void
    let onSave: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let image = item.thumbnail {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else { Image(systemName: "photo").foregroundStyle(.tertiary) }
            }
            .frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayName).font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                if let conflict = item.statusText {
                    Label(conflict, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5)).foregroundStyle(VizPalette.serious).lineLimit(2)
                } else if item.errorText == nil, item.outputData != nil || item.savedTo != nil {
                    Label("Watermark applied and metadata removed", systemImage: "checkmark.shield")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if item.savedTo != nil {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
                } else if item.outputData != nil { Button("Save…", action: onSave).controlSize(.small) }
                Button(action: onRemove) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor),
                              lineWidth: selected ? 2 : 1)))
        .contentShape(Rectangle()).onTapGesture(perform: onSelect)
    }

    private var detail: String {
        if let error = item.errorText { return "Could not apply watermark: \(error)" }
        guard let output = item.outputSize, let width = item.width, let height = item.height else {
            return "Waiting to process · \(Fmt.bytes(item.originalSize))"
        }
        var parts = ["\(Fmt.bytes(item.originalSize)) → \(Fmt.bytes(output))", "\(width) × \(height)"]
        if let quality = item.quality { parts.append("q\(quality)") }
        return parts.joined(separator: " · ")
    }
}

private enum WatermarkPreviewMode: String, CaseIterable, Identifiable {
    case original = "Original"
    case watermarked = "Watermarked"
    var id: String { rawValue }
}

struct WatermarkAnchorPicker: View {
    @Binding var selection: WatermarkPosition
    private let rows: [[WatermarkPosition]] = [
        [.topLeft, .top, .topRight], [.left, .centre, .right],
        [.bottomLeft, .bottom, .bottomRight],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text("Placement").font(.system(size: 11)); Spacer(); Text(selection.rawValue).font(.system(size: 10)).foregroundStyle(.secondary) }
            VStack(spacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 3) {
                        ForEach(row) { position in
                            Button { selection = position } label: {
                                Image(systemName: selection == position ? "circle.inset.filled" : "circle")
                                    .font(.system(size: 8)).frame(maxWidth: .infinity, minHeight: 20)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selection == position ? Color.accentColor : Color.secondary)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(selection == position ? Color.accentColor.opacity(0.12) : Color.clear))
                            .help(position.rawValue)
                            .accessibilityLabel(position.rawValue)
                        }
                    }
                }
            }
        }
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            for row in 0...Int(ceil(size.height / cell)) {
                for column in 0...Int(ceil(size.width / cell)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                             width: cell, height: cell)),
                                 with: .color(Color.primary.opacity(0.045)))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

extension WatermarkPosition {
    static func nearest(to location: CGPoint, in size: CGSize) -> WatermarkPosition {
        // Dragging is intentionally a keyboard-friendly nine-zone snap instead of a
        // free-floating value that presets could not reproduce exactly.
        let x = min(max(location.x / max(1, size.width), 0), 1)
        let y = min(max(location.y / max(1, size.height), 0), 1)
        let column = x < 0.34 ? 0 : x > 0.66 ? 2 : 1
        let row = y < 0.34 ? 0 : y > 0.66 ? 2 : 1
        let grid: [[WatermarkPosition]] = [
            [.topLeft, .top, .topRight], [.left, .centre, .right],
            [.bottomLeft, .bottom, .bottomRight],
        ]
        return grid[row][column]
    }
}
