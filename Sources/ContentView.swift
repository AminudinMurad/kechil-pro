import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var imageCleanModel = ScrubModel()
    @StateObject private var imageOptimizeModel = TransformModel()
    @StateObject private var imageWatermarkModel = TransformModel(watermarkMode: true)
    @StateObject private var videoCleanModel = VideoCleanModel()
    @StateObject private var videoOptimizeModel = VideoOptimizeModel()
    @StateObject private var videoWatermarkModel = VideoWatermarkModel()
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var sizer = DashboardSizer.shared
    @State private var route: ToolRoute
    @State private var isTargeted = false
    @State private var showingSettings: Bool
    @State private var showingPasteURL = false

    init(initialRoute: ToolRoute = .cleanImages, showingSettings: Bool = false,
         imageCleanModel: ScrubModel? = nil,
         imageOptimizeModel: TransformModel? = nil,
         imageWatermarkModel: TransformModel? = nil,
         videoCleanModel: VideoCleanModel? = nil,
         videoOptimizeModel: VideoOptimizeModel? = nil,
         videoWatermarkModel: VideoWatermarkModel? = nil) {
        _route = State(initialValue: initialRoute)
        _showingSettings = State(initialValue: showingSettings)
        _imageCleanModel = StateObject(wrappedValue: imageCleanModel ?? ScrubModel())
        _imageOptimizeModel = StateObject(wrappedValue: imageOptimizeModel ?? TransformModel())
        _imageWatermarkModel = StateObject(wrappedValue: imageWatermarkModel ?? TransformModel(watermarkMode: true))
        _videoCleanModel = StateObject(wrappedValue: videoCleanModel ?? VideoCleanModel())
        _videoOptimizeModel = StateObject(wrappedValue: videoOptimizeModel ?? VideoOptimizeModel())
        _videoWatermarkModel = StateObject(wrappedValue: videoWatermarkModel ?? VideoWatermarkModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 0) {
                ToolSidebar(selection: $route, count: routeCount)
                    .frame(width: 190)
                Divider()
                VStack(spacing: 0) {
                    workspaceHeader
                    Divider()
                    toolContent
                }
            }
        }
        .frame(minWidth: DashboardMetrics.minimumContentSize.width,
               minHeight: DashboardMetrics.minimumContentSize.height)
        // Zero-size probe: the only way to reach the real NSWindow from a SwiftUI
        // WindowGroup, which the size presets and frame persistence both need.
        .background(WindowAccessor { window in
            sizer.attach(to: window)
        })
        // Accepting the drop at the window level means users can drop anywhere,
        // not just onto the empty-state box.
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            load(providers: providers)
            return true
        }
        // Info.plist advertises the app as an alternate image/movie editor. Handle
        // those Finder/Open With events instead of launching to an empty dashboard.
        .onOpenURL(perform: openFromFinder)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showingPasteURL) {
            PasteURLPanel(isPresented: $showingPasteURL,
                          initialValue: "",
                          media: route.media) { url in
                add(urls: [url])
            }
        }
    }

    private var toolContent: some View {
        VStack(spacing: 0) {
            switch (route.tool, route.media) {
            case (.clean, .image):
                VStack(spacing: 0) {
                    CleanPresetPicker(selection: Binding(
                        get: { imageCleanModel.preset },
                        set: { imageCleanModel.selectPreset($0) }),
                        media: .image,
                        isDisabled: imageCleanModel.isCleaning)
                    if !imageCleanModel.items.isEmpty {
                        Divider()
                        CleanReviewBar(media: .image,
                                       readyCount: imageCleanModel.readyForReviewCount,
                                       plannedChangeCount: imageCleanModel.plannedChangeCount,
                                       preparedCount: imageCleanModel.cleanedCount,
                                       isInspecting: imageCleanModel.isInspecting,
                                       isCleaning: imageCleanModel.isCleaning,
                                       clean: imageCleanModel.cleanAll,
                                       cancel: imageCleanModel.cancel)
                    }
                    Divider()
                    if imageCleanModel.items.isEmpty {
                        MediaEmptyState(media: .image, tool: .clean,
                                        detail: "JPEG, PNG, WebP, HEIC and more · pixels stay untouched when possible",
                                        choose: imageCleanModel.chooseFiles,
                                        pasteURL: { imageCleanModel.add(urls: [$0]) })
                    } else {
                        HSplitView {
                            mainColumn.frame(minWidth: 320, idealWidth: 350)
                            InspectorPanel(model: imageCleanModel)
                                .frame(minWidth: 330)
                        }
                    }
                }
            case (.clean, .video):
                VideoCleanView(model: videoCleanModel)
            case (.optimize, .image):
                TransformToolView(model: imageOptimizeModel)
            case (.optimize, .video):
                VideoOptimizeView(model: videoOptimizeModel)
            case (.watermark, .image):
                WatermarkToolView(model: imageWatermarkModel)
            case (.watermark, .video):
                VideoWatermarkView(model: videoWatermarkModel)
            }

            if route == .cleanImages, let status = imageCleanModel.statusMessage {
                Divider()
                Text(status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Dashboard over a filtered, selectable list.
    private var mainColumn: some View {
        VStack(spacing: 0) {
            DashboardHeader(model: imageCleanModel)
            if imageCleanModel.isProcessing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(imageCleanModel.isCleaning ? "Cleaning…" : "Inspecting…")
                        .font(.system(size: 11.5))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(imageCleanModel.visibleItems) { item in
                        ItemRow(item: item,
                                isSelected: imageCleanModel.isSelected(item),
                                onSelect: { imageCleanModel.select(item, modifiers: NSEvent.modifierFlags) },
                                onSave: { imageCleanModel.save(item: item) },
                                onRemove: { imageCleanModel.remove(item: item) })
                    }
                    if imageCleanModel.visibleItems.isEmpty, let filter = imageCleanModel.activeFilter {
                        VStack(spacing: 6) {
                            Text("No images carrying \(filter.displayName)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Button("Show all") { imageCleanModel.selectFilter(nil) }
                                .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }
                .padding(14)
            }
            .kechilScrollbars()
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            CleanBatchFooter(readyCount: imageCleanModel.readyForReviewCount,
                             plannedChangeCount: imageCleanModel.plannedChangeCount,
                             preparedCount: imageCleanModel.cleanedCount,
                             isProcessing: imageCleanModel.isProcessing,
                             clean: imageCleanModel.cleanAll, cancel: imageCleanModel.cancel,
                             canCleanSelected: imageCleanModel.canCleanSelected,
                             selectedHasChanges: imageCleanModel.selectedHasChanges,
                             selectedCount: imageCleanModel.selectedItemCount,
                             cleanSelected: imageCleanModel.cleanSelected)
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: route.tool.symbol)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.tool.title).font(.system(size: 15, weight: .semibold))
                Text(route.tool.scopeDescription).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 330, alignment: .leading)
            Spacer()
            Picker("Media", selection: mediaBinding) {
                Label("Images", systemImage: "photo").tag(MediaKind.image)
                Label("Videos", systemImage: "video").tag(MediaKind.video)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 185)
            if routeCount(route) > 0 {
                Button("Clear", action: clearCurrent).controlSize(.small)
                BatchSaveButton(readyCount: readyCount, isProcessing: currentIsProcessing,
                                action: saveAllCurrent)
            }
            Button("Paste URL…") { showingPasteURL = true }
                .controlSize(.small)
            if readyCount > 0 {
                Button(route.media.addLabel, action: chooseCurrent)
                    .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button(route.media.addLabel, action: chooseCurrent)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var mediaBinding: Binding<MediaKind> {
        Binding(get: { route.media }, set: { route = ToolRoute(tool: route.tool, media: $0) })
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                BrandLockup()
                Spacer()
                settingsButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// App-wide preferences live behind one familiar gear. This includes dashboard
    /// sizing, which previously occupied a separate header control.
    private var settingsButton: some View {
        Button {
            showingSettings.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Settings")
        .accessibilityLabel("Settings")
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            SettingsPanel(settings: settings, sizer: sizer)
        }
    }

    // MARK: Drop handling

    private func load(providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var resolved: URL?
                if let data = item as? Data {
                    resolved = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    resolved = url
                }
                if let resolved {
                    lock.lock(); urls.append(resolved); lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            add(urls: urls)
        }
    }

    private func routeCount(_ candidate: ToolRoute) -> Int {
        switch (candidate.tool, candidate.media) {
        case (.clean, .image): return imageCleanModel.items.count
        case (.clean, .video): return videoCleanModel.items.count
        case (.optimize, .image): return imageOptimizeModel.items.count
        case (.optimize, .video): return videoOptimizeModel.items.count
        case (.watermark, .image): return imageWatermarkModel.items.count
        case (.watermark, .video): return videoWatermarkModel.items.count
        }
    }

    private var readyCount: Int {
        switch (route.tool, route.media) {
        case (.clean, .image): return imageCleanModel.cleanedCount
        case (.clean, .video): return videoCleanModel.completedCount
        case (.optimize, .image): return imageOptimizeModel.completedCount
        case (.optimize, .video): return videoOptimizeModel.completedCount
        case (.watermark, .image): return imageWatermarkModel.completedCount
        case (.watermark, .video): return videoWatermarkModel.completedCount
        }
    }

    private var currentIsProcessing: Bool {
        switch (route.tool, route.media) {
        case (.clean, .image): return imageCleanModel.isProcessing
        case (.clean, .video): return videoCleanModel.isProcessing
        case (.optimize, .image): return imageOptimizeModel.isProcessing
        case (.optimize, .video): return videoOptimizeModel.isProcessing
        case (.watermark, .image): return imageWatermarkModel.isProcessing
        case (.watermark, .video): return videoWatermarkModel.isProcessing
        }
    }

    private func chooseCurrent() {
        switch (route.tool, route.media) {
        case (.clean, .image): imageCleanModel.chooseFiles()
        case (.clean, .video): videoCleanModel.chooseFiles()
        case (.optimize, .image): imageOptimizeModel.chooseFiles()
        case (.optimize, .video): videoOptimizeModel.chooseFiles()
        case (.watermark, .image): imageWatermarkModel.chooseFiles()
        case (.watermark, .video): videoWatermarkModel.chooseFiles()
        }
    }

    private func clearCurrent() {
        switch (route.tool, route.media) {
        case (.clean, .image): imageCleanModel.clear()
        case (.clean, .video): videoCleanModel.clear()
        case (.optimize, .image): imageOptimizeModel.clear()
        case (.optimize, .video): videoOptimizeModel.clear()
        case (.watermark, .image): imageWatermarkModel.clear()
        case (.watermark, .video): videoWatermarkModel.clear()
        }
    }

    private func saveAllCurrent() {
        switch (route.tool, route.media) {
        case (.clean, .image): imageCleanModel.saveAll()
        case (.clean, .video): videoCleanModel.saveAll()
        case (.optimize, .image): imageOptimizeModel.saveAll()
        case (.optimize, .video): videoOptimizeModel.saveAll()
        case (.watermark, .image): imageWatermarkModel.saveAll()
        case (.watermark, .video): videoWatermarkModel.saveAll()
        }
    }

    private func add(urls: [URL]) {
        add(urls: urls, to: route)
    }

    private func add(urls: [URL], to destination: ToolRoute) {
        switch (destination.tool, destination.media) {
        case (.clean, .image): imageCleanModel.add(urls: urls)
        case (.clean, .video): videoCleanModel.add(urls: urls)
        case (.optimize, .image): imageOptimizeModel.add(urls: urls)
        case (.optimize, .video): videoOptimizeModel.add(urls: urls)
        case (.watermark, .image): imageWatermarkModel.add(urls: urls)
        case (.watermark, .video): videoWatermarkModel.add(urls: urls)
        }
    }

    private func openFromFinder(_ url: URL) {
        guard let kind = mediaKind(for: url) else { return }
        let destination = ToolRoute(tool: route.tool, media: kind)
        route = destination
        add(urls: [url], to: destination)
    }

    private func mediaKind(for url: URL) -> MediaKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
            return .video
        }
        return nil
    }
}

// MARK: - Row

private struct ItemRow: View {
    let item: ScrubItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onSave: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumb

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                tagFlow
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if item.savedTo != nil {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                } else if item.isSaveReady {
                    Button(item.isUnchangedCopy ? "Save Copy…" : "Save…", action: onSave)
                        .buttonStyle(KechilSaveButtonStyle(width: KechilActionMetrics.saveButtonWidth))
                        .controlSize(.regular)
                }
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor),
                                  lineWidth: isSelected ? 2 : 1))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var thumb: some View {
        Group {
            if let image = item.thumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary, lineWidth: 1))
    }

    private var subtitle: String {
        if item.stage == .queued || item.stage == .analysing || item.stage == .cancelling {
            return item.statusText ?? item.stage.cleanLabel
        }
        if item.errorText != nil { return "Could not process" }
        var parts = [item.format.rawValue]
        if let cleaned = item.cleanedSize {
            parts.append("\(Fmt.bytes(item.originalSize)) → \(Fmt.bytes(cleaned))")
        }
        parts.append(item.lossless ? "lossless — pixels untouched" : "re-encoded")
        return parts.joined(separator: "  ·  ")
    }

    /// A loaded photo can carry seven categories at once, which is more than fits beside
    /// a thumbnail and the row's buttons. The row is a summary — the inspector carries
    /// the full list — so the overflow collapses into a count rather than truncating
    /// seven pills to "GPS l…".
    private static let maxVisibleTags = 3

    /// Pills are driven by `MetadataCategory`, so a pill's colour matches that
    /// category's bar in the dashboard chart.
    private var tagFlow: some View {
        HStack(spacing: 5) {
            if item.stage == .queued || item.stage == .analysing || item.stage == .cancelling {
                Tag(text: item.stage.cleanLabel, color: Color.accentColor,
                    symbol: "doc.text.magnifyingglass")
            } else if item.stage == .ready {
                Tag(text: "Ready for review", color: Color.accentColor,
                    symbol: "list.bullet.clipboard")
            } else if let error = item.errorText {
                Tag(text: error, color: .orange, symbol: "exclamationmark.triangle.fill")
            } else if item.verificationState == .remaining {
                Tag(text: "Metadata still present", color: VizPalette.critical,
                    symbol: "xmark.shield.fill")
            } else if item.categories.isEmpty && item.provenance.carriers.isEmpty {
                Tag(text: "Nothing found", color: .green, symbol: "checkmark")
            } else if item.categories.isEmpty {
                Tag(text: "Metadata detected", color: VizPalette.serious,
                    symbol: "scope")
            } else {
                // Fixed category order, so GPS keeps the first slot whenever present and
                // is never the thing that gets collapsed away.
                let shown = item.categories.prefix(Self.maxVisibleTags)
                let hidden = item.categories.dropFirst(Self.maxVisibleTags)
                ForEach(shown) { category in
                    Tag(text: category.displayName,
                        color: VizPalette.color(for: category),
                        symbol: category.symbolName)
                }
                if !hidden.isEmpty {
                    Text("+\(hidden.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .help(hidden.map(\.displayName).joined(separator: ", "))
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct Tag: View {
    let text: String
    let color: Color
    let symbol: String

    var body: some View {
        // Icon plus label, never colour alone — the status hues in particular have to
        // stay readable for anyone who cannot separate them.
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.13)))
        .foregroundStyle(color)
        .lineLimit(1)
    }
}
