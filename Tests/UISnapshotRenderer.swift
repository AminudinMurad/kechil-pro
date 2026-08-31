import AppKit
import CoreMedia
import Foundation
import SwiftUI

/// Visual-regression renderer for the six empty dashboard routes and Settings.
/// It hosts the real SwiftUI views in an off-screen NSWindow and snapshots only
/// those views, so it never needs macOS Screen Recording permission.
@main
@MainActor
struct UISnapshotRenderer {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            fputs("usage: ui-snapshot-renderer OUTPUT_DIRECTORY APP_ICON\n", stderr)
            exit(2)
        }

        let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)

        _ = NSApplication.shared
        if let icon = NSImage(contentsOfFile: arguments[2]) {
            NSApp.applicationIconImage = icon
        }
        try verifyFilterModelBehaviour()
        for route in ToolRoute.all {
            let view = ContentView(initialRoute: route)
            try render(view, size: CGSize(width: 940, height: 900),
                       to: outputDirectory.appendingPathComponent(
                        route.id.replacingOccurrences(of: ".", with: "-") + ".png"))
        }
        try render(ContentView(initialRoute: .cleanImages),
                   size: DashboardMetrics.minimumContentSize,
                   to: outputDirectory.appendingPathComponent("clean-image-compact.png"))
        try render(ContentView(initialRoute: .optimizeImages),
                   size: DashboardMetrics.minimumContentSize,
                   to: outputDirectory.appendingPathComponent("optimize-image-compact.png"))

        try render(TransformToolView(model: makeCustomCropModel()),
                   size: CGSize(width: 940, height: 900),
                   to: outputDirectory.appendingPathComponent("optimize-image-custom-crop.png"))

        try render(TransformToolView(model: makeCustomCropModel(policy: .fillTarget, resizeMode: .width)),
                   size: CGSize(width: 940, height: 900),
                   to: outputDirectory.appendingPathComponent("optimize-image-crop-fill-target.png"))
        try render(TransformToolView(model: makeCustomCropModel(policy: .fillTarget)),
                   size: CGSize(width: 750, height: 520),
                   to: outputDirectory.appendingPathComponent("optimize-image-crop-fill-compact.png"))
        try render(TransformToolView(model: makeCustomCropModel(policy: .fillTarget),
                                    initiallyShowsOriginal: true),
                   size: CGSize(width: 940, height: 900),
                   to: outputDirectory.appendingPathComponent("optimize-image-crop-original.png"))

        try renderBatchActionSnapshots(to: outputDirectory)

        try render(VideoOptimizeView(model: makeVideoTrimModel()),
                   size: CGSize(width: 940, height: 900),
                   to: outputDirectory.appendingPathComponent("optimize-video-trim.png"))

        let targetSizeVideo = makeVideoTrimModel()
        targetSizeVideo.settings.sizeMode = .targetSize
        targetSizeVideo.settings.targetMegabytes = 8
        try render(VideoOptimizeView(model: targetSizeVideo),
                   size: CGSize(width: 940, height: 900),
                   to: outputDirectory.appendingPathComponent("optimize-video-target-size.png"))

        // The dashboard itself is 940 pt wide, but the 190 pt sidebar leaves
        // approximately this width for Optimize > Videos at the minimum height.
        // Keep a compact regression image so the inline trim editor cannot crowd
        // the queue off screen on the smallest supported window.
        try render(VideoOptimizeView(model: makeVideoTrimModel()),
                   size: CGSize(width: 750, height: 520),
                   to: outputDirectory.appendingPathComponent("optimize-video-trim-compact.png"))

        let settings = SettingsPanel(settings: .shared, sizer: .shared)
        try renderFitting(settings,
                          to: outputDirectory.appendingPathComponent("settings.png"))

        try render(ScrollbarRegressionView(),
                   size: CGSize(width: 320, height: 700),
                   to: outputDirectory.appendingPathComponent("scrollbar.png"),
                   verifyCompactScrollers: true)

        try render(GPSScopeRegressionView(model: makeGPSScopeModel()),
                   size: CGSize(width: 940, height: 700),
                   to: outputDirectory.appendingPathComponent("gps-scope.png"),
                   verifyCompactScrollers: true)

        try render(InspectorPanel(model: makeGPSScopeModel()),
                   size: CGSize(width: 280, height: 700),
                   to: outputDirectory.appendingPathComponent("inspector-sections.png"),
                   verifyCompactScrollers: true)

        try render(InspectorPanel(model: makeAIDetectionModel()),
                   size: CGSize(width: 280, height: 700),
                   to: outputDirectory.appendingPathComponent("inspector-ai-critical.png"),
                   verifyCompactScrollers: true)

        try render(CleanImageReviewRegressionView(model: makeImageReviewModel()),
                   size: CGSize(width: 940, height: 650),
                   to: outputDirectory.appendingPathComponent("clean-image-review.png"),
                   verifyCompactScrollers: true)

        try render(CleanImageReviewRegressionView(model: makeImageReviewModel(),
                                                  initiallyExpandedFindings: true),
                   size: CGSize(width: 940, height: 900),
                   to: outputDirectory.appendingPathComponent("clean-image-findings-expanded.png"),
                   verifyCompactScrollers: true)

        try render(VideoCleanView(model: makeVideoEvidenceModel()),
                   size: CGSize(width: 940, height: 650),
                   to: outputDirectory.appendingPathComponent("video-clean-evidence.png"),
                   verifyCompactScrollers: false)

        try render(VideoCleanView(model: makeVideoEvidenceModel(),
                                  initiallyExpandedFindings: true),
                   size: CGSize(width: 940, height: 900),
                   to: outputDirectory.appendingPathComponent("video-clean-findings-expanded.png"),
                   verifyCompactScrollers: false)

        try render(MediaEmptyState(
            media: .video,
            tool: .clean,
            detail: "MOV, MP4 and M4V · originals are never overwritten",
            choose: {},
            pasteURL: { _ in }),
                   size: CGSize(width: 940, height: 520),
                   to: outputDirectory.appendingPathComponent("video-upload-file.png"))

        try render(MediaEmptyState(
            media: .video,
            tool: .clean,
            detail: "MOV, MP4 and M4V · originals are never overwritten",
            choose: {},
            pasteURL: { _ in },
            startsWithPasteURL: true),
                   size: CGSize(width: 940, height: 520),
                   to: outputDirectory.appendingPathComponent("video-paste-url.png"))

        try render(MediaSizeEstimateCardsSnapshot(),
                   size: CGSize(width: 430, height: 820),
                   to: outputDirectory.appendingPathComponent("media-size-estimates.png"))

        print("Rendered UI snapshots to \(outputDirectory.path)")
    }

    private static func renderBatchActionSnapshots(to directory: URL) throws {
        let imageReady = makeCustomCropModel(policy: .fillTarget)
        for index in imageReady.items.indices {
            // Presentation-only prepared results. Never saved or processed by this renderer.
            imageReady.items[index].outputData = Data([0])
            imageReady.items[index].outputSize = 180_000
            imageReady.items[index].outputFormat = .webp
            imageReady.items[index].width = 1100
            imageReady.items[index].height = 700
            imageReady.items[index].quality = 82
        }
        let watermark = TransformModel(watermarkMode: true)
        watermark.items = imageReady.items
        watermark.selectedItemID = watermark.items.first?.id
        watermark.watermarkPreview = sampleImage(size: CGSize(width: 660, height: 420))

        let cleanReady = makeGPSScopeModel()
        cleanReady.items[0].stage = .completed
        cleanReady.items[0].thumbnail = sampleImage(size: CGSize(width: 660, height: 420))
        let videoReady = makeVideoTrimModel()
        videoReady.items[0].stage = .completed
        videoReady.items[0].outputURL = URL(fileURLWithPath: "/tmp/qa-presentation-only.mp4")
        videoReady.items[0].outputDescriptor = videoReady.items[0].descriptor
        let videoCleanReady = makeVideoEvidenceModel()
        videoCleanReady.items[0].stage = .completed
        videoCleanReady.items[0].outputURL = URL(fileURLWithPath: "/tmp/qa-presentation-only-clean.mov")
        videoCleanReady.items[0].verification = .containerOnlyFramesUnverified
        let videoWatermark = VideoWatermarkModel()
        videoWatermark.items = videoReady.items
        videoWatermark.selectedItemID = videoWatermark.items.first?.id

        for route in ToolRoute.all {
            try render(ContentView(initialRoute: route,
                                   imageCleanModel: cleanReady, imageOptimizeModel: imageReady,
                                   imageWatermarkModel: watermark, videoCleanModel: videoCleanReady,
                                   videoOptimizeModel: videoReady, videoWatermarkModel: videoWatermark),
                       size: DashboardMetrics.minimumContentSize,
                       to: directory.appendingPathComponent("batch-save-\(route.id).png"))
        }
        watermark.watermarkKind = .logo
        videoWatermark.kind = .logo
        try render(ContentView(initialRoute: .watermarkImages, imageWatermarkModel: watermark),
                   size: CGSize(width: 940, height: 1000),
                   to: directory.appendingPathComponent("batch-logo-defaults-image.png"))
        try render(ContentView(initialRoute: .watermarkVideos, videoWatermarkModel: videoWatermark),
                   size: CGSize(width: 940, height: 1000),
                   to: directory.appendingPathComponent("batch-logo-defaults-video.png"))
        imageReady.isProcessing = true
        try render(ContentView(initialRoute: .optimizeImages, imageOptimizeModel: imageReady),
                   size: DashboardMetrics.minimumContentSize,
                   to: directory.appendingPathComponent("batch-save-processing.png"))

        try render(ContentView(initialRoute: .cleanImages, imageCleanModel: makeImageReviewModel()),
                   size: DashboardMetrics.minimumContentSize,
                   to: directory.appendingPathComponent("batch-clean-images-review.png"))
        try render(ContentView(initialRoute: .cleanVideos, videoCleanModel: makeVideoEvidenceModel()),
                   size: DashboardMetrics.minimumContentSize,
                   to: directory.appendingPathComponent("batch-clean-videos-review.png"))

        try render(BatchActionStatesSnapshot().frame(width: 340, height: 880),
                   size: CGSize(width: 340, height: 880),
                   to: directory.appendingPathComponent("batch-actions-dark.png"),
                   appearance: NSAppearance(named: .darkAqua))
    }

    private static func verifyFilterModelBehaviour() throws {
        let imageModel = makeImageReviewModel()
        let imageID = imageModel.items[0].id
        imageModel.selectFilter(.ai)
        try require(imageModel.visibleItems.map(\.id) == [imageID] &&
                    imageModel.selectedItemID == imageID,
                    "Image filter does not retain its visible selection")
        imageModel.selectFilter(.gps)
        try require(imageModel.visibleItems.isEmpty && imageModel.selectedItemID == nil,
                    "Image filtered-empty state does not clear a hidden selection")
        imageModel.selectFilter(.ai)
        let imageCount = imageModel.count(of: .ai)
        imageModel.selectPreset(.gps)
        try require(imageModel.count(of: .ai) == imageCount,
                    "Image scope selection rewrote original findings counts")
        imageModel.remove(item: imageModel.items[0])
        try require(imageModel.activeFilter == nil && imageModel.visibleItems.isEmpty,
                    "Image filter survived removal of its last matching row")

        let videoModel = makeVideoEvidenceModel()
        let videoID = videoModel.items[0].id
        try require(videoModel.count(of: .contentCredentials) == 1 &&
                    videoModel.count(of: .generativeAI) == 1,
                    "Overlapping video findings were not both counted once")
        videoModel.selectFilter(.location)
        try require(videoModel.visibleItems.map(\.id) == [videoID] &&
                    videoModel.selectedItemID == videoID,
                    "Video findings filter does not retain its visible selection")
        videoModel.selectFilter(.descriptiveMetadata)
        try require(videoModel.visibleItems.isEmpty && videoModel.selectedItemID == nil &&
                    videoModel.selectedItem == nil,
                    "Video filtered-empty state does not clear a hidden selection")
        videoModel.selectFilter(.location)
        let originalCounts = videoModel.categoryCounts
        videoModel.selectSelection(.contentCredentials)
        videoModel.items[0].findings = [] // model a cleaned copy; source findings remain cached
        try require(videoModel.categoryCounts == originalCounts,
                    "Video scope or cleanup state rewrote original findings counts")
        videoModel.remove(item: videoModel.items[0])
        try require(videoModel.activeFilter == nil && videoModel.visibleItems.isEmpty,
                    "Video filter survived removal of its last matching row")
        print("Verified image and video findings filtering model behaviour")
    }

    private static func require(_ condition: @autoclosure () -> Bool,
                                _ message: String) throws {
        guard condition() else { throw SnapshotError(message) }
    }

    private static func makeGPSScopeModel() -> ScrubModel {
        let model = ScrubModel()
        let location = ProvenanceFinding(
            kind: .location,
            title: "GPS coordinates present",
            detail: "Latitude=3.133758333333333, Longitude=101.5359283333333",
            protocolName: "ImageIO metadata",
            confidence: .stated)
        let sourceReport = ProvenanceReport(
            format: .jpeg,
            carriers: ["JPEG APP1 (EXIF)"],
            findings: [location],
            stillPresent: [],
            limitations: [],
            coverage: .containerComplete)
        let outputReport = ProvenanceReport(
            format: .jpeg,
            carriers: [],
            findings: [location],
            stillPresent: [],
            limitations: [],
            coverage: .containerComplete)

        var item = ScrubItem(
            sourceURL: URL(fileURLWithPath: "/tmp/IMG_3494.JPG"),
            originalSize: 4_186_075,
            preset: .exif)
        item.cleanedData = Data([0])
        item.cleanedSize = 4_140_000
        item.removed = ["EXIF / camera and capture data"]
        item.format = .jpeg
        item.provenance = sourceReport
        item.outputProvenance = outputReport
        model.items = [item]
        model.selectedItemID = item.id
        return model
    }

    private static func makeAIDetectionModel() -> ScrubModel {
        let model = ScrubModel()
        model.selectPreset(.aiMetadata)
        let generated = ProvenanceFinding(
            kind: .generativeAI,
            title: "AI generator detected: OpenAI image generation",
            detail: "gpt-image",
            protocolName: "C2PA in PNG caBX",
            confidence: .declared)
        let report = ProvenanceReport(
            format: .png,
            carriers: ["PNG caBX (C2PA / JUMBF)", "JUMBF label: c2pa"],
            findings: [generated],
            stillPresent: [],
            limitations: [],
            coverage: .containerComplete)

        var item = ScrubItem(
            sourceURL: URL(fileURLWithPath: "/tmp/openai-generated.png"),
            originalSize: 2_480_000,
            preset: .aiMetadata)
        item.format = .png
        item.provenance = report
        model.items = [item]
        model.selectedItemID = item.id
        return model
    }

    private static func makeVideoEvidenceModel() -> VideoCleanModel {
        let model = VideoCleanModel()
        let finding = VideoMetadataFinding(
            scope: .file,
            category: .provenance,
            identifier: "c2pa",
            displayName: "Content credentials",
            valueSummary: "Synthetic unsigned C2PA test declaration",
            evidence: [
                VideoMetadataEvidence(label: "Claim", value: "OpenAI generative provenance test",
                                       source: "C2PA in MOV uuid"),
                VideoMetadataEvidence(label: "Generative ID",
                                       value: "openai-test-genid-4f61d8b7-531e-4f19-9ea6-bf4191696e13",
                                       source: "C2PA assertion"),
                VideoMetadataEvidence(label: "Payload",
                                       value: "{\"claim_generator\":\"OpenAI Sora\",\"digitalSourceType\":\"trainedAlgorithmicMedia\"}",
                                       source: "embedded metadata"),
            ],
            removable: true)
        let location = VideoMetadataFinding(
            scope: .file, category: .location,
            identifier: "com.apple.quicktime.location.ISO6709",
            displayName: "Location", valueSummary: "+03.1390+101.6869/",
            removable: true)
        let xmp = VideoMetadataFinding(
            scope: .file, category: .unknown, identifier: "xmp",
            displayName: "XMP packet", valueSummary: "Adobe XMP creator metadata",
            removable: true)
        let technical = VideoMetadataFinding(
            scope: .track(1), category: .technical, identifier: "codec",
            displayName: "Video codec", valueSummary: "H.264", removable: false)
        let detected = [finding, location, xmp, technical]
        var item = VideoQueueItem(sourceURL: URL(fileURLWithPath: "/tmp/Kechil-OpenAI-Generative-ID-5s.mov"))
        let identity = CleanSourceIdentity(
            standardizedPath: item.sourceURL.path, fileSize: 6_200_000,
            modificationNanoseconds: nil, resourceIdentifier: nil)
        item.stage = .ready
        item.statusText = "3 selected metadata items — ready for review"
        item.sourceIdentity = identity
        item.detectedFindings = detected
        item.inspectionReport = VideoMetadataReport(findings: detected, inspectedFormats: ["QuickTime"],
                                                   hasTimedMetadata: false, containerScanWasBounded: true)
        item.findings = detected.filter(\.removable)
        item.descriptor = MediaAssetDescriptor(
            sourceURL: item.sourceURL, kind: .video, fileSize: 6_200_000,
            contentTypeIdentifier: "com.apple.quicktime-movie", displayWidth: 1920,
            displayHeight: 1080, duration: CMTime(seconds: 10, preferredTimescale: 600),
            frameRate: 30, videoCodec: "H.264", audioCodec: "AAC",
            hasAudio: true, isHDR: false, preferredTransform: nil)
        item.selection = .all
        item.plan = CleanPlanSummary(
            sourceIdentity: identity, selectionRevision: 0,
            selectionTitle: VideoCleanSelection.all.title,
            detectedEntryCount: detected.count, selectedEntryCount: 3,
            unsupportedReasons: [], warnings: ["Raw container inspection is currently bounded."])
        model.items = [item]
        model.selectedItemID = item.id
        return model
    }

    private static func makeImageReviewModel() -> ScrubModel {
        let model = makeAIDetectionModel()
        guard var item = model.items.first else { return model }
        let identity = CleanSourceIdentity(
            standardizedPath: item.sourceURL.path, fileSize: Int64(item.originalSize),
            modificationNanoseconds: nil, resourceIdentifier: nil)
        item.stage = .ready
        item.statusText = "Ready for review"
        item.sourceIdentity = identity
        item.plan = CleanPlanSummary(
            sourceIdentity: identity, selectionRevision: 0,
            selectionTitle: item.preset.title,
            detectedEntryCount: item.provenance.carriers.count + item.provenance.findings.count,
            selectedEntryCount: 1, unsupportedReasons: [], warnings: [])
        item.thumbnail = sampleImage(size: CGSize(width: 640, height: 420))
        model.items = [item]
        model.selectedItemID = item.id
        return model
    }

    private static func makeCustomCropModel(policy: ImageCropUpscalePolicy = .keepNative,
                                            resizeMode: ResizeMode = .percent) -> TransformModel {
        let model = TransformModel()
        let preview = sampleImage(size: CGSize(width: 720, height: 480))
        var item = TransformItem(sourceURL: URL(fileURLWithPath: "/tmp/Kechil-landscape.jpg"),
                                 originalSize: 4_800_000)
        // Keep one queued source below the requested crop target so the snapshot
        // exercises the batch impact summary and the crop-only enlargement control.
        item.sourceWidth = 900
        item.sourceHeight = 600
        item.sourceThumbnail = preview
        item.thumbnail = preview
        var large = TransformItem(sourceURL: URL(fileURLWithPath: "/tmp/Kechil-large.jpg"),
                                  originalSize: 6_200_000)
        large.sourceWidth = 2400
        large.sourceHeight = 1600
        large.sourceThumbnail = preview
        large.thumbnail = preview
        var portrait = TransformItem(sourceURL: URL(fileURLWithPath: "/tmp/Kechil-portrait.jpg"),
                                     originalSize: 2_200_000)
        portrait.sourceWidth = 600
        portrait.sourceHeight = 900
        portrait.sourceThumbnail = sampleImage(size: CGSize(width: 480, height: 720))
        portrait.thumbnail = portrait.sourceThumbnail
        model.items = [item, large, portrait]
        model.selectedItemID = item.id
        model.cropAspect = .custom
        model.cropUpscalePolicy = policy
        model.cropWidth = 1100
        model.cropHeight = 700
        model.cropFocusX = 0.64
        model.cropFocusY = 0.42
        model.resizeMode = resizeMode
        model.resizeValue = resizeMode == .percent ? 100 : 1100
        model.allowsUpscaling = false
        return model
    }

    private static func makeVideoTrimModel() -> VideoOptimizeModel {
        let model = VideoOptimizeModel()
        var item = VideoQueueItem(sourceURL: URL(fileURLWithPath: "/tmp/Kechil-demo.mp4"))
        item.descriptor = MediaAssetDescriptor(
            sourceURL: item.sourceURL, kind: .video, fileSize: 18_000_000,
            contentTypeIdentifier: "public.mpeg-4", displayWidth: 1920,
            displayHeight: 1080, duration: CMTime(seconds: 65.24, preferredTimescale: 600),
            frameRate: 30, videoCodec: "H.264", audioCodec: "AAC",
            hasAudio: true, isHDR: false, preferredTransform: nil)
        item.poster = sampleImage(size: CGSize(width: 720, height: 405))
        item.stage = .ready
        item.statusText = "Ready to optimize"
        model.items = [item]
        model.selectedItemID = item.id
        model.settings.trimStartSeconds = 8.2
        model.settings.trimEndSeconds = 52.6
        model.previewSeconds = 24.4
        return model
    }

    private static func sampleImage(size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.06, green: 0.12, blue: 0.24, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.95, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: size.width * 0.10, y: size.height * 0.18,
                                        width: size.width * 0.34, height: size.height * 0.58),
                     xRadius: 24, yRadius: 24).fill()
        NSColor(calibratedRed: 0.25, green: 0.78, blue: 0.42, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: size.width * 0.56, y: size.height * 0.23,
                                   width: size.height * 0.50, height: size.height * 0.50)).fill()
        image.unlockFocus()
        return image
    }

    private static func render<Content: View>(
        _ content: Content,
        size: CGSize,
        to outputURL: URL,
        forceVisibleScrollers: Bool = false,
        verifyCompactScrollers: Bool = false,
        appearance: NSAppearance? = nil
    ) throws {
        let hostingView = NSHostingView(
            rootView: content.background(Color(nsColor: .windowBackgroundColor)))
        hostingView.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        // ContentView's WindowAccessor restores the user's last dashboard size on
        // its first run-loop turn. Apply the requested regression size after that
        // restore so the PNG dimensions are the test case, not local preferences.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        window.setContentSize(size)
        hostingView.frame = CGRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.10))
        hostingView.layoutSubtreeIfNeeded()

        if forceVisibleScrollers {
            showScrollers(in: hostingView)
            window.layoutIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
        }
        if verifyCompactScrollers {
            try assertCompactScrollers(in: hostingView,
                                       snapshot: outputURL.lastPathComponent)
        }

        let bounds = hostingView.bounds
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw SnapshotError("Could not allocate bitmap for \(outputURL.lastPathComponent)")
        }
        hostingView.cacheDisplay(in: bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError("Could not encode \(outputURL.lastPathComponent)")
        }
        try data.write(to: outputURL, options: .atomic)
        window.close()
    }

    private static func showScrollers(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.autohidesScrollers = false
            scrollView.verticalScroller?.isHidden = false
            scrollView.verticalScroller?.alphaValue = 1
            scrollView.horizontalScroller?.isHidden = false
            scrollView.horizontalScroller?.alphaValue = 1
            scrollView.verticalScroller?.needsDisplay = true
            scrollView.horizontalScroller?.needsDisplay = true
        }
        view.subviews.forEach(showScrollers)
    }

    private static func assertCompactScrollers(in view: NSView,
                                               snapshot: String) throws {
        let scrollViews = descendants(of: view).compactMap { $0 as? NSScrollView }
        let active = scrollViews.filter { scrollView in
            guard scrollView.hasVerticalScroller,
                  let document = scrollView.documentView else { return false }
            return document.frame.height > scrollView.contentSize.height + 1
        }
        guard !active.isEmpty else {
            throw SnapshotError("No active vertical scroller in \(snapshot)")
        }
        for scrollView in active {
            guard let scroller = scrollView.verticalScroller as? KechilScroller else {
                throw SnapshotError(
                    "\(snapshot) uses \(String(describing: type(of: scrollView.verticalScroller))) instead of KechilScroller")
            }
            guard scrollView.scrollerStyle == .legacy,
                  !scrollView.autohidesScrollers,
                  !scroller.isHidden,
                  scroller.alphaValue >= 0.99 else {
                throw SnapshotError("\(snapshot) scrollbar is not persistently visible")
            }
            guard scroller.frame.width >= 11 else {
                throw SnapshotError(
                    "\(snapshot) scrollbar is only \(scroller.frame.width)pt wide")
            }
            let slot = scroller.rect(for: .knobSlot)
            let knob = scroller.rect(for: .knob)
            guard slot.height > 0 else {
                throw SnapshotError("\(snapshot) has an empty scrollbar track")
            }
            let expected = max(KechilScrollbarGeometry.minimumThumbLength,
                               slot.height * KechilScrollbarGeometry.thumbFraction)
            guard abs(knob.height - expected) < 1 else {
                throw SnapshotError(
                    "\(snapshot) thumb is \(knob.height)pt; expected \(expected)pt")
            }
            print("Verified \(snapshot): KechilScroller \(knob.height)pt / \(slot.height)pt")
        }
    }

    private static func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private static func renderFitting<Content: View>(
        _ content: Content, to outputURL: URL
    ) throws {
        let measuringView = NSHostingView(rootView: content)
        measuringView.layoutSubtreeIfNeeded()
        let fitting = measuringView.fittingSize
        guard fitting.width > 0, fitting.height > 0 else {
            throw SnapshotError("Could not measure \(outputURL.lastPathComponent)")
        }
        try render(content,
                   size: CGSize(width: ceil(fitting.width), height: ceil(fitting.height)),
                   to: outputURL)
    }
}

private struct ScrollbarRegressionView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<40, id: \.self) { index in
                    HStack {
                        Text("Scrollbar test row \(index + 1)")
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
        }
        .kechilScrollbars()
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct GPSScopeRegressionView: View {
    @ObservedObject var model: ScrubModel

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeader(model: model)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Remove EXIF selected")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Original-file categories must still report GPS.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                InspectorPanel(model: model)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct CleanImageReviewRegressionView: View {
    @ObservedObject var model: ScrubModel
    var initiallyExpandedFindings = false

    var body: some View {
        VStack(spacing: 0) {
            CleanPresetPicker(selection: Binding(
                get: { model.preset },
                set: { model.selectPreset($0) }),
                media: .image,
                isDisabled: model.isCleaning)
            Divider()
            CleanReviewBar(media: .image,
                           readyCount: model.readyForReviewCount,
                           plannedChangeCount: model.plannedChangeCount,
                           preparedCount: model.cleanedCount,
                           isInspecting: model.isInspecting,
                           isCleaning: model.isCleaning,
                           clean: {}, cancel: {})
            Divider()
            DashboardHeader(model: model, initiallyExpanded: initiallyExpandedFindings)
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Inspected queue")
                        .font(.system(size: 13, weight: .semibold))
                    Label("openai-generated.png", systemImage: "photo")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("Inspection only · no output exists yet")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14)
                .frame(minWidth: 320, idealWidth: 350,
                       maxHeight: .infinity, alignment: .topLeading)
                InspectorPanel(model: model)
                    .frame(minWidth: 330)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct BatchActionStatesSnapshot: View {
    var body: some View {
        VStack(spacing: 0) {
            BatchOutputHeader(queuedCount: 3, readyCount: 3, isProcessing: false, save: {},
                              selectedName: "long-selected-image-name-for-truncation.png",
                              selectedCount: 3, selectedReadyCount: 3, canSaveSelected: true)
            Divider()
            BatchOutputHeader(queuedCount: 3, readyCount: 0, isProcessing: false, save: {})
            Divider()
            BatchOutputHeader(queuedCount: 3, readyCount: 1, isProcessing: true, save: {})
            Divider()
            CleanBatchFooter(readyCount: 3, plannedChangeCount: 2, preparedCount: 0,
                             isProcessing: false, clean: {}, cancel: {}, canCleanSelected: true,
                             selectedCount: 3)
            Divider()
            CleanBatchFooter(readyCount: 3, plannedChangeCount: 0, preparedCount: 0,
                             isProcessing: false, clean: {}, cancel: {},
                             canCleanSelected: true, selectedHasChanges: false, selectedCount: 3)
            Divider()
            CleanBatchFooter(readyCount: 0, plannedChangeCount: 0, preparedCount: 3,
                             isProcessing: false, clean: {}, cancel: {})
            Divider()
            CleanBatchFooter(readyCount: 2, plannedChangeCount: 1, preparedCount: 1,
                             isProcessing: true, clean: {}, cancel: {})
            Spacer(minLength: 0)
        }
    }
}

private struct MediaSizeEstimateCardsSnapshot: View {
    private let clean = MediaSizeEstimate(
        sourceBytes: 5_000_000,
        estimatedBytes: 4_123_456,
        basis: .exactClean,
        detail: "The selected Clean scope was measured through the same byte-preserving path.")
    private let image = MediaSizeEstimate(
        sourceBytes: 5_000_000,
        estimatedBytes: 1_932_847,
        basis: .fullImageEncode,
        detail: "The selected image was fully encoded with the current format and quality.")
    private let optimize = MediaSizeEstimate(
        sourceBytes: 5_000_000,
        estimatedBytes: 1_286_410,
        basis: .fullImageOptimizeEncode,
        detail: "The selected image was fully encoded with the current Optimize crop, resize, format and quality settings.")
    private let video = MediaSizeEstimate(
        sourceBytes: 80_000_000,
        estimatedBytes: 42_810_000,
        basis: .realVideoSample,
        detail: "A real 3.0 s sample was encoded with the current video settings and projected to the full duration.")
    private let actual = MediaSizeEstimate(
        sourceBytes: 5_000_000,
        estimatedBytes: 1_932_847,
        basis: .actualOutput,
        detail: "The prepared output has now been measured; this is the byte count that will be saved.")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Live output estimates")
                    .font(.system(size: 18, weight: .semibold))
                Text("Each card explains whether the number is exact, sampled, or already prepared.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                MediaSizeEstimateCard(title: "Clean output estimate",
                                      estimate: clean,
                                      isEstimating: false,
                                      error: nil)
                MediaSizeEstimateCard(title: "Watermarked image estimate",
                                      estimate: image,
                                      isEstimating: false,
                                      error: nil)
                MediaSizeEstimateCard(title: "Optimized image estimate",
                                      estimate: optimize,
                                      isEstimating: false,
                                      error: nil)
                MediaSizeEstimateCard(title: "Watermarked video estimate",
                                      estimate: video,
                                      isEstimating: false,
                                      error: nil)
                MediaSizeEstimateCard(title: "Prepared output",
                                      estimate: actual,
                                      isEstimating: false,
                                      error: nil)
                MediaSizeEstimateCard(title: "Remeasuring after a setting change",
                                      estimate: nil,
                                      isEstimating: true,
                                      error: nil)
            }
            .padding(16)
        }
        .kechilScrollbars()
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SnapshotError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
