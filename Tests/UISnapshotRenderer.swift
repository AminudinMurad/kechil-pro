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
        for route in ToolRoute.all {
            let view = ContentView(initialRoute: route)
            try render(view, size: CGSize(width: 940, height: 900),
                       to: outputDirectory.appendingPathComponent(
                        route.id.replacingOccurrences(of: ".", with: "-") + ".png"),
                       verifyCompactScrollers: route == .watermarkImages)
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

        try render(VideoOptimizeView(model: makeVideoTrimModel()),
                   size: CGSize(width: 940, height: 900),
                   to: outputDirectory.appendingPathComponent("optimize-video-trim.png"))

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

        try render(VideoCleanView(model: makeVideoEvidenceModel()),
                   size: CGSize(width: 940, height: 900),
                   to: outputDirectory.appendingPathComponent("video-clean-evidence.png"),
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

        print("Rendered UI snapshots to \(outputDirectory.path)")
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
        var item = VideoQueueItem(sourceURL: URL(fileURLWithPath: "/tmp/Kechil-OpenAI-Generative-ID-5s.mov"))
        item.stage = .completed
        item.statusText = "Container cleaned; frames not re-encoded"
        item.detectedFindings = [finding]
        item.findings = [finding]
        item.selection = .all
        model.items = [item]
        model.selectedItemID = item.id
        return model
    }

    private static func makeCustomCropModel() -> TransformModel {
        let model = TransformModel()
        let preview = sampleImage(size: CGSize(width: 720, height: 480))
        var item = TransformItem(sourceURL: URL(fileURLWithPath: "/tmp/Kechil-landscape.jpg"),
                                 originalSize: 4_800_000)
        item.sourceWidth = 2400
        item.sourceHeight = 1600
        item.width = 1100
        item.height = 700
        item.sourceThumbnail = preview
        item.thumbnail = preview
        model.items = [item]
        model.selectedItemID = item.id
        model.cropAspect = .custom
        model.cropWidth = 1100
        model.cropHeight = 700
        model.cropFocusX = 0.64
        model.cropFocusY = 0.42
        model.resizeMode = .width
        model.resizeValue = 1100
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
        verifyCompactScrollers: Bool = false
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

private struct SnapshotError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
