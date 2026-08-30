import SwiftUI

struct TransformToolView: View {
    @ObservedObject var model: TransformModel
    @State private var showsOriginal = false
    @State private var resizeUsesSourceDefault = true

    var body: some View {
        HSplitView {
            controls
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
            queue
                .frame(minWidth: 470)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // The preview is intentionally live, while queue outputs remain committed
        // only by Apply to All. A single settings key keeps all controls in sync,
        // including text fields and slider drags.
        .onChange(of: previewSettingsKey) { _ in
            model.refreshOptimizePreview()
        }
        .onChange(of: model.cropAspect) { aspect in
            guard aspect == .custom else { return }
            seedCustomCropFromSource()
        }
        .onChange(of: model.resizeMode) { mode in
            guard mode != .none else { return }
            resizeUsesSourceDefault = true
            seedResizeValue(for: mode)
        }
        .onChange(of: cropGeometryKey) { _ in
            if model.cropAspect == .custom { seedCustomCropFromSource() }
            if resizeUsesSourceDefault, model.resizeMode != .none {
                seedResizeValue(for: model.resizeMode)
            }
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Image settings", systemImage: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))

            Text("Crop, resize, convert and optimize image files locally. Switch to Videos above for trim, crop and target-size compression.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                settingSection("Crop") {
                    Picker("Aspect", selection: $model.cropAspect) {
                        ForEach(CropAspect.allCases) { aspect in
                            Text(aspect.rawValue).tag(aspect)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    if model.cropAspect != .original {
                        if model.cropAspect == .custom {
                            HStack(spacing: 8) {
                                cropDimensionField("Width", value: $model.cropWidth)
                                Text("×").font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                cropDimensionField("Height", value: $model.cropHeight)
                            }
                            Text(customCropHelp)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        sliderRow("Focus X", value: $model.cropFocusX, range: 0...1,
                                  format: { $0 == 0 ? "Left" : $0 == 1 ? "Right" : "Centre" })
                        sliderRow("Focus Y", value: $model.cropFocusY, range: 0...1,
                                  format: { $0 == 0 ? "Bottom" : $0 == 1 ? "Top" : "Centre" })
                    }
                }

                settingSection("Resize") {
                    Picker("Resize", selection: $model.resizeMode) {
                        ForEach(ResizeMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    if model.resizeMode != .none {
                        HStack {
                            Text(resizeValueLabel).font(.system(size: 11.5))
                            Spacer()
                            TextField("Value", value: resizeValueBinding,
                                      format: .number.precision(.fractionLength(0)))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 68)
                        }
                        Toggle("Do not upscale", isOn: $model.dontUpscale)
                            .font(.system(size: 11.5))
                    }
                }

                settingSection("Output") {
                    Picker("Format", selection: $model.outputFormat) {
                        ForEach(ImageOutputFormat.allCases) { format in Text(format.rawValue).tag(format) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    if model.outputFormat == .webp {
                        Toggle("Lossless WebP", isOn: $model.webPLossless)
                            .font(.system(size: 11.5))
                        if !model.webPLossless {
                            sliderRow("Method", value: $model.webPMethod, range: 0...6,
                                      format: { "\(Int($0.rounded()))" }, step: 1)
                        }
                    }

                    if model.outputFormat.qualityAffectsSize &&
                        !(model.outputFormat == .webp && model.webPLossless) {
                        sliderRow("Quality floor", value: $model.qualityFloor, range: 0...100,
                                  format: { "\(Int($0.rounded()))" }, step: 1)
                        sliderRow("Quality ceiling", value: $model.qualityCeiling, range: 0...100,
                                  format: { "\(Int($0.rounded()))" }, step: 1)
                    }

                    HStack {
                        Text("Target KB").font(.system(size: 11.5))
                        Spacer()
                        TextField("Off", value: $model.targetKilobytes,
                                  format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 68)
                    }
                    Text("Set to 0 to keep the quality result without a byte target.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }

                Button {
                    model.reprocessAll()
                } label: {
                    Label("Apply to All", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.items.isEmpty || model.isProcessing)

                Text("Preview updates as settings change. Use Apply to All to commit the current settings to the queue.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .kechilScrollbars()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var queue: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch output")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(model.items.count) queued · \(model.completedCount) ready")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isProcessing {
                    ProgressView().controlSize(.small)
                    Text("Processing…").font(.system(size: 11.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()

            if model.items.isEmpty {
                MediaEmptyState(media: .image, tool: .optimize,
                                detail: "WebP is the default · crop, resize, convert and optimize",
                                choose: model.chooseFiles,
                                pasteURL: { model.add(urls: [$0]) })
            } else {
                optimizePreview
                Divider()
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.items) { item in
                            TransformItemRow(item: item,
                                             selected: model.selectedItemID == item.id,
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
                Text(status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var optimizePreview: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Preview", selection: $showsOriginal) {
                    Text("Original").tag(true)
                    Text(model.cropAspect == .original ? "Optimized" : "Crop guide").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 210)
                Spacer()
                Text(model.cropAspect != .original ? "Crop guide" : "Preview")
                    .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.92))
                if let item = model.selectedItem,
                   let image = previewImage(for: item) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                } else {
                    Image(systemName: "photo").font(.system(size: 34)).foregroundStyle(.white.opacity(0.4))
                }
                if model.cropAspect != .original,
                   let item = model.selectedItem,
                   let sourceAspect = sourceAspect(for: item) {
                    MediaCropGuide(aspect: model.cropAspect.ratio,
                                   sourceAspect: sourceAspect,
                                   cropPixelSize: customCropSize,
                                   sourcePixelSize: sourcePixelSize(for: item),
                                   focusX: model.cropFocusX,
                                   focusY: model.cropFocusY)
                }
                if !showsOriginal, model.cropAspect == .original,
                   let item = model.selectedItem,
                   model.optimizePreviewItemID == item.id,
                   model.isOptimizePreviewRendering {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .frame(maxWidth: .infinity).frame(height: 220)
            HStack {
                Text(model.selectedItem?.displayName ?? "Select an image")
                    .font(.system(size: 10.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let item = model.selectedItem {
                    let width = model.optimizePreviewItemID == item.id
                        ? model.optimizePreviewWidth ?? item.width
                        : item.width
                    let height = model.optimizePreviewItemID == item.id
                        ? model.optimizePreviewHeight ?? item.height
                        : item.height
                    let format = model.optimizePreviewItemID == item.id
                        ? model.optimizePreviewFormat?.rawValue ?? item.outputFormat?.rawValue
                        : item.outputFormat?.rawValue
                    if let width, let height {
                        Text("\(width) × \(height) · \(format ?? "Output")")
                            .font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
    }

    private var previewSettingsKey: String {
        [
            model.cropAspect.rawValue,
            String(model.cropFocusX), String(model.cropFocusY),
            String(model.cropWidth), String(model.cropHeight),
            model.resizeMode.rawValue, String(model.resizeValue),
            String(model.dontUpscale), model.outputFormat.rawValue,
            String(model.qualityFloor), String(model.qualityCeiling),
            String(model.targetKilobytes), String(model.webPLossless),
            String(model.webPMethod),
        ].joined(separator: "|")
    }

    private var cropGeometryKey: String {
        let item = model.selectedItem
        return [
            item?.id.uuidString ?? "none",
            String(item?.sourceWidth ?? item?.width ?? 0),
            String(item?.sourceHeight ?? item?.height ?? 0),
            model.cropAspect.rawValue,
            String(model.cropWidth), String(model.cropHeight),
        ].joined(separator: "|")
    }

    private var resizeValueBinding: Binding<Double> {
        Binding(get: { model.resizeValue }, set: { value in
            resizeUsesSourceDefault = false
            model.resizeValue = value
        })
    }

    private func optimizedImage(for item: TransformItem) -> NSImage? {
        if model.optimizePreviewItemID == item.id, let preview = model.optimizePreview {
            return preview
        }
        return item.thumbnail ?? item.sourceThumbnail
    }

    private func previewImage(for item: TransformItem) -> NSImage? {
        // Crop editing is performed against the complete source image. The guide makes
        // the retained region obvious without hiding the pixels that will be discarded.
        if !showsOriginal, model.cropAspect != .original {
            return item.sourceThumbnail ?? optimizedImage(for: item)
        }
        return showsOriginal ? item.sourceThumbnail : optimizedImage(for: item)
    }

    private func sourceAspect(for item: TransformItem) -> CGFloat? {
        if let size = sourcePixelSize(for: item), size.height > 0 {
            return size.width / size.height
        }
        guard let image = item.sourceThumbnail, image.size.width > 0, image.size.height > 0 else {
            guard let width = item.width, let height = item.height, height > 0 else { return nil }
            return CGFloat(width) / CGFloat(height)
        }
        return image.size.width / image.size.height
    }

    private func sourcePixelSize(for item: TransformItem) -> CGSize? {
        guard let width = item.sourceWidth ?? item.width,
              let height = item.sourceHeight ?? item.height,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private var customCropSize: CGSize? {
        guard model.cropAspect == .custom, model.cropWidth > 0, model.cropHeight > 0 else {
            return nil
        }
        return CGSize(width: model.cropWidth, height: model.cropHeight)
    }

    private var retainedCropSize: CGSize? {
        guard let item = model.selectedItem, let source = sourcePixelSize(for: item) else {
            return nil
        }
        return ImageCropGeometry.cropSize(source: source,
                                          aspect: model.cropAspect.ratio,
                                          customSize: customCropSize)
    }

    private var customCropHelp: String {
        if let source = model.selectedItem.flatMap(sourcePixelSize),
           let retained = retainedCropSize {
            return "Independent pixels · retained area \(Int(retained.width)) × \(Int(retained.height)) of \(Int(source.width)) × \(Int(source.height))"
        }
        return "Width and height are independent. Oversized values are clamped per source."
    }

    private func seedCustomCropFromSource() {
        guard let retained = retainedCropSize else { return }
        if model.cropWidth <= 0 { model.cropWidth = Double(retained.width) }
        if model.cropHeight <= 0 { model.cropHeight = Double(retained.height) }
    }

    private func seedResizeValue(for mode: ResizeMode) {
        guard let size = retainedCropSize else {
            if mode == .percent { model.resizeValue = 100 }
            return
        }
        switch mode {
        case .none: break
        case .longEdge: model.resizeValue = Double(max(size.width, size.height).rounded())
        case .width: model.resizeValue = Double(size.width.rounded())
        case .height: model.resizeValue = Double(size.height.rounded())
        case .percent: model.resizeValue = 100
        }
    }

    private func cropDimensionField(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField(label, value: value,
                          format: .number.precision(.fractionLength(0)))
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 62)
                Text("px").font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
        }
    }

    private var resizeValueLabel: String {
        switch model.resizeMode {
        case .longEdge: return "Long edge (px)"
        case .width: return "Width (px)"
        case .height: return "Height (px)"
        case .percent: return "Scale (%)"
        case .none: return ""
        }
    }

    private func settingSection<Content: View>(_ title: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .textBackgroundColor)))
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
                           format: @escaping (Double) -> String, step: Double = 0.01) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 11.5))
                Spacer()
                Text(format(value.wrappedValue)).font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Slider(value: quantized(value, step: step), in: range)
        }
    }

    private func quantized(_ value: Binding<Double>, step: Double) -> Binding<Double> {
        Binding(get: { value.wrappedValue }, set: { proposed in
            value.wrappedValue = (proposed / step).rounded() * step
        })
    }
}

private struct TransformItemRow: View {
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
                } else {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let conflict = item.statusText {
                    Label(conflict, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(VizPalette.serious)
                        .lineLimit(2)
                } else if item.errorText == nil, item.outputData != nil || item.savedTo != nil {
                    Label("Re-encoded and metadata removed", systemImage: "checkmark.shield")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if item.savedTo != nil {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                } else if item.outputData != nil {
                    Button("Save…", action: onSave).controlSize(.small)
                }
                Button(action: onRemove) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor),
                              lineWidth: selected ? 2 : 1)))
        .contentShape(Rectangle()).onTapGesture(perform: onSelect)
    }

    private var detail: String {
        if let error = item.errorText { return "Could not process: \(error)" }
        guard let outputSize = item.outputSize, let width = item.width, let height = item.height else {
            return "Waiting to process · \(Fmt.bytes(item.originalSize))"
        }
        var parts = ["\(Fmt.bytes(item.originalSize)) → \(Fmt.bytes(outputSize))", "\(width) × \(height)"]
        if let quality = item.quality { parts.append("q\(quality)") }
        if item.iterations > 1 { parts.append("\(item.iterations) attempts") }
        return parts.joined(separator: " · ")
    }
}
