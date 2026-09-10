import AppKit
import SwiftUI

struct TransformToolView: View {
    @ObservedObject var model: TransformModel
    @State private var showsOriginal = false
    @State private var resizeUsesSourceDefault = true
    @State private var resizeDefaultSeeded = false

    init(model: TransformModel, initiallyShowsOriginal: Bool = false) {
        self.model = model
        _showsOriginal = State(initialValue: initiallyShowsOriginal)
    }

    var body: some View {
        Group {
            if model.items.isEmpty {
                MediaEmptyState(media: .image, tool: .optimize,
                                detail: "WebP is the default · crop, resize, convert and optimize",
                                choose: model.chooseFiles,
                                pasteURL: { model.add(urls: [$0]) })
            } else {
                HSplitView {
                    controls
                        .frame(minWidth: OptimizeWorkspaceLayout.settingsMinimumWidth,
                               idealWidth: OptimizeWorkspaceLayout.settingsIdealWidth,
                               maxWidth: OptimizeWorkspaceLayout.settingsMaximumWidth)
                    queue
                        .frame(minWidth: OptimizeWorkspaceLayout.outputMinimumWidth)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Reopening a route with existing settings must not reseed its target.
            if model.resizeMode != .none, retainedCropSize != nil { resizeDefaultSeeded = true }
        }
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
            resizeDefaultSeeded = false
            seedResizeValue(for: mode)
        }
        .onChange(of: cropGeometryKey) { _ in
            if model.cropAspect == .custom { seedCustomCropFromSource() }
            if resizeUsesSourceDefault, model.resizeMode != .none {
                seedResizeValue(for: model.resizeMode)
            }
            if !model.allowsUpscaling { clampResizeValueToCroppedSource() }
        }
        .onChange(of: model.allowsUpscaling) { allowsUpscaling in
            if !allowsUpscaling { clampResizeValueToCroppedSource() }
        }
        .onChange(of: model.selectedItemID) { _ in
            seedMissingDimensions()
            model.refreshOptimizePreview()
        }
        .onChange(of: model.knownCropSourceCount) { _ in
            seedMissingDimensions()
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            settingsControls
            Divider()
            ToolApplyActions(operation: "Optimize", canProcessAll: model.canProcessAll,
                             canProcessSelected: model.canProcessSelected,
                             processAll: model.reprocessAll, processSelected: model.reprocessSelected,
                             selectedCount: model.selectedItemCount)
                .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var settingsControls: some View {
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
                                cropDimensionField(.width)
                                Text("×").font(Font.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    // Align with the numeric controls, not the full
                                    // Width/Height stacks that include their labels.
                                    .alignmentGuide(VerticalAlignment.center) { dimensions in
                                        dimensions[VerticalAlignment.center] - 12
                                    }
                                cropDimensionField(.height)
                            }
                            Toggle("Link target ratio", isOn: $model.locksCustomCropAspect)
                                .font(.system(size: 11.5))
                                .help("Uses the selected image ratio when enabled, then keeps that ratio for the whole batch.")
                                .accessibilityHint("The linked ratio stays fixed when you select another image.")
                            Toggle("Enlarge smaller images to fill target", isOn: cropUpscaleBinding)
                                .font(.system(size: 11.5))
                                .help("Smaller sources are enlarged uniformly until they cover the custom crop, then cropped to the exact target.")
                                .accessibilityHint("When enabled, smaller queued images are enlarged uniformly to cover the custom crop before cropping.")
                            Text(customCropHelp)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(cropUpscaleHelp)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(model.batchCropImpactSummary)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
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
                        if model.resizeMode == .dimensions {
                            HStack(spacing: 8) {
                                resizeDimensionField(.width)
                                Text("×").font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .alignmentGuide(VerticalAlignment.center) { dimensions in
                                        dimensions[VerticalAlignment.center] - 12
                                    }
                                resizeDimensionField(.height)
                            }
                            Toggle("Lock aspect ratio", isOn: resizeAspectBinding)
                                .font(.system(size: 11.5))
                                .help("When locked, changing either dimension updates the other using the current cropped image ratio.")
                            Text(resizeAspectHelp)
                                .font(.system(size: 10))
                                .foregroundStyle(model.locksResizeAspect ? .secondary : .tertiary)
                        } else {
                            HStack {
                                Text(resizeValueLabel).font(.system(size: 11.5))
                                Spacer()
                                HStack(spacing: 4) {
                                    KechilNumericStepperField(label: "\(resizeValueLabel) (\(resizeValueUnit))",
                                                        value: resizeValueBinding,
                                                        step: 1,
                                                        lowerBound: 1,
                                                        upperBound: resizeInputMaximum)
                                        .frame(width: 82)
                                    Text(resizeValueUnit)
                                        .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Toggle("Allow upscaling after crop", isOn: $model.allowsUpscaling)
                            .font(.system(size: 11.5))
                            .help("Controls enlargement after cropping. When disabled, the export cannot exceed its cropped source pixels.")
                            .accessibilityHint("Controls resize enlargement after cropping. When disabled, output dimensions are capped at the cropped image dimensions.")
                        Text(upscalingHelp)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
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
                        KechilNumericStepperField(label: "Target kilobytes",
                                            value: $model.targetKilobytes,
                                            step: 10,
                                            lowerBound: 0)
                            .frame(width: 82)
                    }
                    Text("Set to 0 to keep the quality result without a byte target.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }


                Text("Preview updates as settings change. Optimize Selected processes the highlighted file; Optimize All processes the whole queue. Save outputs separately.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .kechilScrollbars()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var queue: some View {
        GeometryReader { geometry in
            let usesCompactPreview = geometry.size.height < 800
            VStack(spacing: 0) {
                BatchOutputHeader(queuedCount: model.items.count, readyCount: model.completedCount,
                                  isProcessing: model.isProcessing, save: model.saveAll,
                                  selectedName: model.selectedItemID == nil ? nil : model.selectedItem?.displayName,
                                  selectedCount: model.selectedItemCount,
                                  selectedReadyCount: model.selectedSaveCount,
                                  canSaveSelected: model.canSaveSelected, saveSelected: model.saveSelected)
                Divider()

                if model.items.isEmpty {
                    MediaEmptyState(media: .image, tool: .optimize,
                                    detail: "WebP is the default · crop, resize, convert and optimize",
                                    choose: model.chooseFiles,
                                    pasteURL: { model.add(urls: [$0]) })
                } else {
                    optimizePreview(compact: usesCompactPreview)
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.items) { item in
                                TransformItemRow(item: item,
                                                 cropPrediction: model.cropPrediction(for: item),
                                                 selected: model.isSelected(item),
                                                 onSelect: { model.select(item, modifiers: NSEvent.modifierFlags) },
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
    }

    private func optimizePreview(compact: Bool) -> some View {
        VStack(spacing: compact ? 5 : 8) {
            HStack {
                Picker("Preview", selection: $showsOriginal) {
                    Text("Original").tag(true)
                    Text(model.cropAspect == .original ? "Optimized" : "Crop guide").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: compact ? 190 : 210)
                Spacer()
                Text(showsOriginal ? "Original" : (model.cropAspect != .original ? "Crop guide" : "Preview"))
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
                if !showsOriginal, model.cropAspect != .original,
                   let item = model.selectedItem,
                   let sourceAspect = sourceAspect(for: item) {
                    MediaCropGuide(aspect: model.cropAspect.ratio,
                                   sourceAspect: sourceAspect,
                                   cropPixelSize: customCropSize,
                                   sourcePixelSize: sourcePixelSize(for: item),
                                   cropUpscalePolicy: model.cropUpscalePolicy,
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
            .frame(maxWidth: .infinity).frame(height: compact ? 160 : 220)
            HStack {
                Text(model.selectedItem?.displayName ?? "Select an image")
                    .font(.system(size: compact ? 9.5 : 10.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let item = model.selectedItem, let dimensions = dimensionSummary(for: item) {
                    Text(dimensions)
                        .font(.system(size: compact ? 8.8 : 9.5)).foregroundStyle(.secondary)
                }
            }
            if let selectedID = model.selectedItem?.id,
               model.optimizeSizeEstimateItemID == selectedID,
               model.optimizeSizeEstimate != nil || model.isOptimizeSizeEstimating ||
                    model.optimizeSizeEstimateError != nil {
                MediaSizeEstimateCard(
                    title: "Optimized output estimate",
                    estimate: model.optimizeSizeEstimate,
                    isEstimating: model.isOptimizeSizeEstimating,
                    error: model.optimizeSizeEstimateError,
                    compact: compact)
            }
            if let error = model.optimizePreviewError, !showsOriginal {
                Text("Preview unavailable: \(error)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(compact ? 8 : 12)
    }

    private var previewSettingsKey: String {
        [
            model.cropAspect.rawValue,
            String(model.cropFocusX), String(model.cropFocusY),
            String(model.cropWidth), String(model.cropHeight),
            model.cropUpscalePolicy.rawValue,
            model.resizeMode.rawValue, String(model.resizeValue),
            String(model.resizeWidth), String(model.resizeHeight),
            String(model.allowsUpscaling), model.outputFormat.rawValue,
            String(model.qualityFloor), String(model.qualityCeiling),
            String(model.targetKilobytes), String(model.webPLossless),
            String(model.webPMethod),
        ].joined(separator: "|")
    }

    private var cropGeometryKey: String {
        return [
            model.cropAspect.rawValue,
            String(model.cropWidth), String(model.cropHeight),
            model.cropUpscalePolicy.rawValue,
        ].joined(separator: "|")
    }

    private var resizeValueBinding: Binding<Double> {
        Binding(get: { model.resizeValue }, set: { value in
            resizeUsesSourceDefault = false
            model.resizeValue = boundedResizeValue(value)
        })
    }

    private var resizeAspectBinding: Binding<Bool> {
        Binding(get: { model.locksResizeAspect }, set: { locked in
            let ratio = retainedCropSize.flatMap { size in
                size.height > 0 ? Double(size.width / size.height) : nil
            }
            model.setResizeAspectLock(locked, sourceRatio: ratio)
        })
    }

    private enum CropDimension {
        case width
        case height

        var title: String {
            switch self {
            case .width: return "Width"
            case .height: return "Height"
            }
        }
    }

    private enum ResizeDimension {
        case width
        case height

        var title: String { self == .width ? "Width" : "Height" }
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
        guard let image = item.sourceThumbnail, image.size.width > 0, image.size.height > 0 else { return nil }
        return image.size.width / image.size.height
    }

    private func sourcePixelSize(for item: TransformItem) -> CGSize? {
        guard let width = item.sourceWidth,
              let height = item.sourceHeight,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private func dimensionSummary(for item: TransformItem) -> String? {
        guard let source = sourcePixelSize(for: item) else { return nil }
        if !showsOriginal,
           model.optimizePreviewItemID == item.id,
           let width = model.optimizePreviewWidth,
           let height = model.optimizePreviewHeight {
            let format = model.optimizePreviewFormat?.rawValue ?? "Output"
            return "Preview: \(width) × \(height) · \(format)"
        }
        return "Original: \(Int(source.width)) × \(Int(source.height))"
    }

    private var customCropSize: CGSize? {
        guard model.cropAspect == .custom, model.cropWidth > 0, model.cropHeight > 0 else {
            return nil
        }
        return CGSize(width: model.cropWidth, height: model.cropHeight)
    }

    private var cropUpscaleBinding: Binding<Bool> {
        Binding(get: { model.cropUpscalePolicy == .fillTarget },
                set: { model.cropUpscalePolicy = $0 ? .fillTarget : .keepNative })
    }

    private var retainedCropSize: CGSize? {
        guard let item = model.selectedItem, let source = sourcePixelSize(for: item) else {
            return nil
        }
        return ImageCropGeometry.cropSize(source: source,
                                          aspect: model.cropAspect.ratio,
                                          customSize: customCropSize,
                                          cropUpscalePolicy: model.cropUpscalePolicy)
    }

    private var customCropHelp: String {
        if model.locksCustomCropAspect {
            return "The linked target ratio stays fixed across the batch."
        }
        if let target = model.customCropTargetSize {
            return "Independent target pixels · \(Int(target.width)) × \(Int(target.height))"
        }
        return "Width and height are independent target pixels."
    }

    private var cropUpscaleHelp: String {
        guard let target = model.customCropTargetSize else {
            return "Enter a custom crop target to choose how smaller sources are handled."
        }
        switch model.cropUpscalePolicy {
        case .keepNative:
            return "Keeps native pixels. Smaller crops may be below \(Int(target.width)) × \(Int(target.height)) before Resize."
        case .fillTarget:
            return "Enlarges smaller images to cover \(Int(target.width)) × \(Int(target.height)), then crops exactly. No stretching; enlargement may look softer. Resize runs afterward."
        }
    }

    private var resizeInputMaximum: Double? {
        // Pixel targets belong to the batch. The pipeline caps each image separately.
        !model.allowsUpscaling && model.resizeMode == .percent ? 100 : nil
    }

    private var upscalingHelp: String {
        if model.allowsUpscaling {
            return "Resize may enlarge the cropped result beyond its current pixels."
        }
        return "Each image is capped at its own dimensions after crop. The batch target stays unchanged."
    }

    private func seedCustomCropFromSource() {
        guard let retained = retainedCropSize else { return }
        if model.cropWidth <= 0 { model.cropWidth = Double(retained.width) }
        if model.cropHeight <= 0 { model.cropHeight = Double(retained.height) }
    }

    private func seedMissingDimensions() {
        if model.cropAspect == .custom { seedCustomCropFromSource() }
        if !resizeDefaultSeeded, resizeUsesSourceDefault, model.resizeMode != .none {
            seedResizeValue(for: model.resizeMode)
        }
    }

    private func seedResizeValue(for mode: ResizeMode) {
        guard let size = retainedCropSize else {
            if mode == .percent { model.resizeValue = 100; resizeDefaultSeeded = true }
            return
        }
        resizeDefaultSeeded = true
        switch mode {
        case .none: break
        case .dimensions:
            model.seedResizeDimensions(width: Double(size.width),
                                       height: Double(size.height))
        case .longEdge: model.resizeValue = Double(max(size.width, size.height).rounded())
        case .width: model.resizeValue = Double(size.width.rounded())
        case .height: model.resizeValue = Double(size.height.rounded())
        case .percent: model.resizeValue = 100
        }
    }

    private func cropDimensionField(_ dimension: CropDimension) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(dimension.title).font(.system(size: 9.5)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                KechilNumericStepperField(label: "Crop \(dimension.title.lowercased())",
                                    value: cropDimensionBinding(for: dimension),
                                    step: 1,
                                    lowerBound: 1)
                    .frame(minWidth: 78)
                Text("px").font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
        }
    }

    private func resizeDimensionField(_ dimension: ResizeDimension) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(dimension.title).font(.system(size: 9.5)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                KechilNumericStepperField(label: "Resize \(dimension.title.lowercased())",
                    value: resizeDimensionBinding(for: dimension), step: 1, lowerBound: 1)
                    .frame(minWidth: 78)
                Text("px").font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
        }
    }

    private func resizeDimensionBinding(for dimension: ResizeDimension) -> Binding<Double> {
        Binding(get: {
            dimension == .width ? model.resizeWidth : model.resizeHeight
        }, set: { value in
            resizeUsesSourceDefault = false
            model.setResizeDimension(isWidth: dimension == .width, value: value)
        })
    }

    private var resizeAspectHelp: String {
        model.locksResizeAspect
            ? "Width and height stay proportional to the cropped image."
            : "Width and height are independent; a different ratio will reshape the image."
    }

    private func cropDimensionBinding(for dimension: CropDimension) -> Binding<Double> {
        Binding(get: {
            switch dimension {
            case .width: return model.cropWidth
            case .height: return model.cropHeight
            }
        }, set: { value in
            setCropDimension(dimension, to: value)
        })
    }

    private func setCropDimension(_ dimension: CropDimension, to proposedValue: Double) {
        model.setCropDimension(isWidth: dimension == .width, value: proposedValue)
    }

    private func boundedResizeValue(_ value: Double) -> Double {
        let rounded = max(1, value.isFinite ? value.rounded() : 1)
        guard let maximum = resizeInputMaximum else { return rounded }
        return min(rounded, maximum)
    }

    private func clampResizeValueToCroppedSource() {
        guard model.resizeMode != .none else { return }
        model.resizeValue = boundedResizeValue(model.resizeValue)
    }

    private var resizeValueLabel: String {
        switch model.resizeMode {
        case .dimensions: return "Dimensions"
        case .longEdge: return "Long edge"
        case .width: return "Width"
        case .height: return "Height"
        case .percent: return "Scale"
        case .none: return ""
        }
    }

    private var resizeValueUnit: String {
        model.resizeMode == .percent ? "%" : "px"
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
    var cropPrediction: String? = nil
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
                if let cropPrediction {
                    Text(cropPrediction)
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
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
                    Button("Save…", action: onSave)
                        .buttonStyle(KechilSaveButtonStyle())
                        .controlSize(.regular)
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
            if let sourceWidth = item.sourceWidth, let sourceHeight = item.sourceHeight {
                return "Original \(sourceWidth) × \(sourceHeight) · Waiting to process · \(Fmt.bytes(item.originalSize))"
            }
            return "Original dimensions pending · Waiting to process · \(Fmt.bytes(item.originalSize))"
        }
        var parts = ["\(Fmt.bytes(item.originalSize)) → \(Fmt.bytes(outputSize))", "\(width) × \(height)"]
        if let quality = item.quality { parts.append("q\(quality)") }
        if item.iterations > 1 { parts.append("\(item.iterations) attempts") }
        return parts.joined(separator: " · ")
    }
}
