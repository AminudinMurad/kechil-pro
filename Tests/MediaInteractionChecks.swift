import AppKit
import AVFoundation
import Foundation
import ImageIO
import SwiftUI

/// Real encoded outputs, the batch model, a hosted control view, and AVPlayer.
/// Fixtures are synthetic and originals are compared byte-for-byte after processing.
@main
@MainActor
enum MediaInteractionChecks {
    static var assertions = 0

    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("Usage: media-interaction-checks OUTPUT_DIRECTORY VIDEO_FIXTURE")
        }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sizes = [(1000, 600), (600, 1000), (2000, 1200)]
        var originals: [URL: Data] = [:]
        for (index, size) in sizes.enumerated() {
            let url = directory.appendingPathComponent("source-\(index).png")
            let data = try fixture(width: size.0, height: size.1)
            try data.write(to: url)
            originals[url] = data
            for policy in ImageCropUpscalePolicy.allCases {
                for allowsResize in [false, true] {
                    var settings = cropSettings(policy: policy)
                    settings.resizeMode = .percent
                    settings.resizeValue = 200
                    settings.allowsUpscaling = allowsResize
                    let result = try TransformPipeline.process(data, settings: settings)
                    let cropWidth = policy == .fillTarget ? 1400 : min(1400, size.0)
                    let multiplier = allowsResize ? 2 : 1
                    let label = "source \(index), \(policy), resize-upscale \(allowsResize), actual \(result.width)×\(result.height)"
                    expect(result.width == cropWidth * multiplier && result.height == 375 * multiplier,
                           "independent crop/resize policies: \(label)")
                    let decoded = try decode(result.data)
                    expect(decoded.width == result.width && decoded.height == result.height,
                           "encoded dimensions agree with reported dimensions: \(label)")
                    try result.data.write(to: directory.appendingPathComponent(
                        "output-\(index)-\(policy == .fillTarget ? "fill" : "native")-\(allowsResize).png"))
                }
            }
        }

        let landscapeURL = directory.appendingPathComponent("source-0.png")
        let landscape = originals[landscapeURL]!
        var settings = cropSettings(policy: .fillTarget)
        let result = try TransformPipeline.process(landscape, settings: settings)
        let raster = try pixels(result.data)
        var redX: [Int] = [], redY: [Int] = []
        for y in 0..<raster.height {
            for x in 0..<raster.width {
                let offset = (y * raster.width + x) * 4
                if raster.bytes[offset] > 200 && raster.bytes[offset + 1] < 80 {
                    redX.append(x); redY.append(y)
                }
            }
        }
        let redWidth = (redX.max() ?? 0) - (redX.min() ?? 0) + 1
        let redHeight = (redY.max() ?? 0) - (redY.min() ?? 0) + 1
        expect(redWidth > 75 && abs(redWidth - redHeight) <= 2,
               "circle remains round after enlargement, including fractional crop origin")
        expect(stride(from: 3, to: raster.bytes.count, by: 4).allSatisfy { raster.bytes[$0] >= 250 },
               "enlarged crop has no transparent edges or padding")
        for format in [ImageOutputFormat.jpeg, .webp] {
            settings.outputFormat = format
            let encoded = try TransformPipeline.process(landscape, settings: settings)
            let image = try decode(encoded.data)
            expect(image.width == 1400 && image.height == 375, "exact crop survives \(format.rawValue) encoding")
            try encoded.data.write(to: directory.appendingPathComponent("fill-target.\(format.fileExtension)"))
        }
        let rotated = try fixture(width: 1000, height: 600, orientation: 6)
        settings.outputFormat = .png
        let oriented = try TransformPipeline.process(rotated, settings: settings)
        expect(oriented.sourceWidth == 600 && oriented.sourceHeight == 1000,
               "EXIF rotation is applied before deciding whether to enlarge")
        expect(oriented.width == 1400 && oriented.height == 375, "rotated source reaches exact crop target")
        for mode in [ResizeMode.width, .height, .longEdge] {
            for allowed in [false, true] {
                var resized = cropSettings(policy: .fillTarget)
                resized.resizeMode = mode
                resized.resizeValue = mode == .height ? 800 : 1600
                resized.allowsUpscaling = allowed
                let output = try TransformPipeline.process(landscape, settings: resized)
                let expectedWidth = !allowed ? 1400 : (mode == .height ? 2987 : 1600)
                let expectedHeight = !allowed ? 375 : (mode == .height ? 800 : 429)
                expect(output.width == expectedWidth && output.height == expectedHeight,
                       "\(mode.rawValue) resize after crop, enlargement \(allowed): \(output.width)×\(output.height)")
            }
        }
        for focus in [0.0, 1.0] {
            var edge = cropSettings(policy: .fillTarget)
            edge.cropFocusX = focus
            edge.cropFocusY = focus
            let output = try TransformPipeline.process(rotated, settings: edge)
            expect(output.width == 1400 && output.height == 375, "edge focus \(focus) keeps exact dimensions")
            let edgePixels = try pixels(output.data)
            expect(stride(from: 3, to: edgePixels.bytes.count, by: 4).allSatisfy { edgePixels.bytes[$0] >= 250 },
                   "edge focus \(focus) stays inside scaled source coverage")
        }
        settings.cropAspect = .original
        let noCrop = try TransformPipeline.process(landscape, settings: settings)
        expect(noCrop.width == 1000 && noCrop.height == 600, "No crop ignores a saved crop enlargement setting")

        let model = TransformModel()
        model.outputFormat = .png
        model.add(urls: originals.keys.sorted { $0.path < $1.path })
        try await wait("initial mixed batch") { model.items.count == 3 && !model.isProcessing && model.completedCount == 3 }
        expect(model.selectedItemCount == 1 && model.selectedItemID == model.items[0].id &&
               model.items[0].sourceWidth == 1000 && model.items[0].sourceHeight == 600,
               "image queue starts with one selected item and records its original dimensions")
        model.select(model.items[1], modifiers: [.command])
        expect(model.selectedItemCount == 2 && model.selectedItemID == model.items[1].id,
               "Command-click selects multiple image outputs while keeping the last preview primary")
        model.select(model.items[2], modifiers: [.command, .shift])
        expect(model.selectedItemCount == 3 && model.selectedSaveCount == 3,
               "multi-selected image outputs are all eligible for Save Selected")
        model.selectedItemID = model.items[0].id
        model.cropAspect = .custom
        model.cropWidth = 1400
        model.cropHeight = 375
        expect(model.knownCropSourceCount == 3 && model.knownSmallerCropCount == 2,
               "batch counts use original source dimensions across mixed aspect ratios")
        model.cropUpscalePolicy = .fillTarget
        expect(model.batchCropImpactSummary.contains("2 of 3"), "batch summary explains the affected image count")
        expect(model.cropPrediction(for: model.items[0])?.contains("enlarge 1.40×") == true,
               "row prediction exposes enlargement without claiming an output exists")

        // Host the real view so selection-triggered onChange behavior is exercised.
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 940, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: TransformToolView(model: model))
        window.orderFront(nil)
        await settle()
        model.locksCustomCropAspect = true
        await settle()
        let linkedTarget = model.customCropTargetSize
        model.resizeMode = .width
        await settle()
        model.resizeValue = 1600
        model.allowsUpscaling = false
        await settle()
        model.select(model.items[1])
        await settle()
        expect(model.customCropTargetSize == linkedTarget, "selecting portrait keeps the linked batch target fixed")
        expect(model.resizeValue == 1600, "selecting a small image does not shrink the shared resize target")
        model.setCropDimension(isWidth: false, value: 600)
        expect(model.cropWidth == 1000, "editing a linked dimension retains the originally captured ratio")
        model.locksCustomCropAspect = false
        model.resizeMode = .none
        model.cropWidth = 1400
        model.cropHeight = 375
        await settle()
        let queueBytes = model.items.map(\.outputData)
        model.refreshOptimizePreview()
        try await wait("fill-target preview") {
            !model.isOptimizePreviewRendering && model.optimizePreviewWidth == 1400 && model.optimizePreviewHeight == 375
        }
        expect(model.items.map(\.outputData) == queueBytes, "live preview leaves committed queue output untouched")
        model.cropUpscalePolicy = .keepNative
        try await wait("native preview") {
            !model.isOptimizePreviewRendering && model.optimizePreviewWidth == 600 && model.optimizePreviewHeight == 375
        }
        expect(model.items.map(\.outputData) == queueBytes, "policy toggle does not silently apply to the batch")
        window.orderOut(nil)
        window.contentView = nil

        model.cropUpscalePolicy = .fillTarget
        model.cropWidth = 1400
        model.reprocessAll()
        model.cropWidth = 1600 // A running batch owns the snapshot taken by Apply.
        try await wait("apply mixed batch") { !model.isProcessing }
        expect(model.items.allSatisfy { $0.width == 1400 && $0.height == 375 },
               "Apply to All uses one immutable settings snapshot for every source")
        expect(model.items.allSatisfy { $0.errorText == nil }, "all mixed-size images export successfully")
        let beforeSelected = model.items.map(\.outputData)
        model.selectedItemID = model.items[0].id
        expect(model.canProcessSelected && model.canSaveSelected, "image Optimize Selected and Save Selected are available for highlighted output")
        model.cropWidth = 800
        model.reprocessSelected()
        expect(model.isProcessing && !model.canProcessSelected && !model.canSaveSelected,
               "selected image processing synchronously disables processing and saving")
        model.selectedItemID = model.items[1].id
        try await wait("optimize selected image") { !model.isProcessing }
        expect(model.items[0].width == 800 && model.items[0].height == 375,
               "Optimize Selected uses the new settings on the captured highlighted image")
        expect(Array(model.items.dropFirst().map(\.outputData)) == Array(beforeSelected.dropFirst()),
               "Optimize Selected preserves every other image output byte-for-byte even when highlight changes")
        model.selectedItemID = nil
        expect(!model.canProcessSelected && !model.canSaveSelected, "no image highlight means no Selected action")
        model.reprocessSelected()
        expect(!model.isProcessing, "Selected without a highlight never falls back to All")
        for (url, data) in originals {
            try expect(Data(contentsOf: url) == data, "original unchanged: \(url.lastPathComponent)")
        }
        let brokenURL = directory.appendingPathComponent("broken.png")
        try Data("invalid image fixture".utf8).write(to: brokenURL)
        model.add(urls: [brokenURL])
        try await wait("failed input isolated") { model.items.count == 4 && !model.isProcessing }
        expect(model.items.last?.errorText != nil && model.items.last?.outputData == nil,
               "invalid image fails without becoming a saveable output")
        expect(model.completedCount == 3 && model.knownCropSourceCount == 3,
               "invalid input does not erase successful outputs or invent source dimensions")
        model.selectedItemID = model.items.last?.id
        expect(!model.canSaveSelected, "failed image cannot be saved through Save Selected")
        model.clear()

        let video = VideoOptimizeModel()
        video.add(urls: [URL(fileURLWithPath: CommandLine.arguments[2])])
        try await wait("video ready") { video.selectedItem?.descriptor != nil && video.player?.currentItem?.status == .readyToPlay }
        video.toggleMute()
        expect(video.isMuted && video.player?.isMuted == true, "mute control reaches the real player")
        video.togglePlayback()
        try await wait("video advances") { video.previewSeconds > 0.25 }
        expect(video.previewSeconds > 0.25, "play advances the real player and preview time")
        video.togglePlayback()
        await settle()
        let paused = video.player!.currentTime().seconds
        try await Task.sleep(nanoseconds: 400_000_000)
        expect(abs(video.player!.currentTime().seconds - paused) < 0.08, "pause holds the playhead")
        video.setPreviewPosition(2.5)
        try await wait("video seek") { abs(video.player!.currentTime().seconds - 2.5) < 0.12 }
        expect(abs(video.player!.currentTime().seconds - 2.5) < 0.12, "scrub seeks the real player")
        video.skipPreview(by: -1)
        try await wait("video skip") { abs(video.player!.currentTime().seconds - 1.5) < 0.12 }
        expect(abs(video.player!.currentTime().seconds - 1.5) < 0.12, "skip changes the real player position")
        video.toggleMute()
        expect(!video.isMuted && video.player?.isMuted == false, "unmute restores the player setting")
        video.clear()
        expect(video.player == nil, "clearing the queue releases the video player")
        try await checkSelectedActions(directory: directory, imageURLs: originals.keys.sorted { $0.path < $1.path })
        print("ALL MEDIA INTERACTION CHECKS PASSED (\(assertions) assertions)")
    }

    static func checkSelectedActions(directory: URL, imageURLs: [URL]) async throws {
        let imageWatermark = TransformModel(watermarkMode: true)
        let videoWatermark = VideoWatermarkModel()
        expect(imageWatermark.watermarkOpacity == 0.45 && videoWatermark.opacity == 0.45,
               "text watermark opacity remains unchanged")
        imageWatermark.watermarkKind = .logo
        videoWatermark.kind = .logo
        expect(imageWatermark.watermarkOpacity == 0.90 && imageWatermark.watermarkRotation == 0 &&
               imageWatermark.watermarkScalePercent == 40 && imageWatermark.watermarkPosition == .centre &&
               imageWatermark.watermarkMarginPercent == 2.5, "image logo has the requested five defaults")
        expect(videoWatermark.opacity == 0.90 && videoWatermark.rotation == 0 &&
               videoWatermark.scalePercent == 40 && videoWatermark.position == .centre &&
               videoWatermark.marginPercent == 2.5, "video logo has the requested five defaults")
        imageWatermark.watermarkScalePercent = 25
        videoWatermark.scalePercent = 25
        imageWatermark.watermarkKind = .text
        videoWatermark.kind = .text
        expect(imageWatermark.watermarkScalePercent == 8 && videoWatermark.scalePercent == 8,
               "switching to text restores its own appearance")
        imageWatermark.watermarkKind = .logo
        videoWatermark.kind = .logo
        expect(imageWatermark.watermarkScalePercent == 25 && videoWatermark.scalePercent == 25,
               "switching back to logo preserves session edits")
        imageWatermark.watermarkKind = .text
        imageWatermark.outputFormat = .png
        imageWatermark.add(urls: Array(imageURLs.prefix(2)))
        try await wait("image watermark imports") { imageWatermark.items.count == 2 && !imageWatermark.isProcessing && imageWatermark.completedCount == 2 }
        try await wait("image watermark size estimate") {
            !imageWatermark.isWatermarkSizeEstimating &&
                imageWatermark.watermarkSizeEstimate != nil
        }
        let initialImageWatermarkEstimate = imageWatermark.watermarkSizeEstimate
        expect(initialImageWatermarkEstimate?.estimatedBytes ?? 0 > 0 &&
               (initialImageWatermarkEstimate?.basis == .actualOutput ||
                initialImageWatermarkEstimate?.basis == .fullImageEncode),
               "image Watermark exposes bytes from a real encoded output")
        let imageWatermarkWindow = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: 940, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false)
        imageWatermarkWindow.isReleasedWhenClosed = false
        imageWatermarkWindow.contentView = NSHostingView(rootView: WatermarkToolView(model: imageWatermark))
        imageWatermarkWindow.orderFront(nil)
        await settle()
        imageWatermark.outputFormat = .jpeg
        imageWatermark.qualityFloor = 45
        imageWatermark.qualityCeiling = 45
        try await wait("image watermark live size change") {
            !imageWatermark.isWatermarkSizeEstimating &&
                imageWatermark.watermarkSizeEstimate?.basis == .fullImageEncode &&
                imageWatermark.watermarkSizeEstimate?.estimatedBytes != initialImageWatermarkEstimate?.estimatedBytes
        }
        expect(imageWatermark.watermarkSizeEstimate?.estimatedBytes != initialImageWatermarkEstimate?.estimatedBytes,
               "image Watermark remeasures when output settings change")
        imageWatermarkWindow.orderOut(nil)
        imageWatermarkWindow.contentView = nil
        let imageBefore = imageWatermark.items.map(\.outputData)
        imageWatermark.selectedItemID = imageWatermark.items[0].id
        imageWatermark.watermarkText = "Selected only"
        imageWatermark.reprocessSelected()
        imageWatermark.selectedItemID = imageWatermark.items[1].id
        try await wait("image watermark selected") { !imageWatermark.isProcessing }
        expect(imageWatermark.items[0].outputData != imageBefore[0] && imageWatermark.items[0].errorText == nil,
               "Watermark Selected changes the intended image")
        expect(imageWatermark.items[1].outputData == imageBefore[1], "Watermark Selected preserves other image outputs")
        imageWatermark.watermarkKind = .logo
        expect(!imageWatermark.canProcessAll && !imageWatermark.canProcessSelected, "image logo processing is unavailable without a chosen logo")
        imageWatermark.clear()

        let cleanImage = ScrubModel()
        cleanImage.add(urls: Array(imageURLs.prefix(2)))
        try await wait("image clean inspections") { cleanImage.items.count == 2 && !cleanImage.isProcessing && cleanImage.readyForReviewCount == 2 }
        cleanImage.selectedItemID = cleanImage.items[0].id
        cleanImage.refreshSizeEstimate()
        try await wait("image Clean size estimate") {
            !cleanImage.isEstimatingSize && cleanImage.sizeEstimate != nil
        }
        let expectedCleanImageSize = Int64(try MetadataStripper.strip(
            Data(contentsOf: imageURLs[0]), preset: .allMetadata).data.count)
        expect(cleanImage.sizeEstimate?.basis == .exactClean &&
               cleanImage.sizeEstimate?.estimatedBytes == expectedCleanImageSize,
               "image Clean measures the exact bytes produced by its cleaner")
        cleanImage.selectPreset(.gps)
        try await wait("image Clean scope size change") {
            !cleanImage.isEstimatingSize &&
                cleanImage.sizeEstimate?.detail.contains("gps") == true
        }
        expect(cleanImage.sizeEstimate?.basis == .exactClean,
               "image Clean remeasures when the preset changes")
        cleanImage.selectPreset(.allMetadata)
        cleanImage.selectedItemID = nil
        expect(!cleanImage.canCleanSelected && !cleanImage.canSaveSelected, "image Clean needs an explicit highlighted file")
        cleanImage.selectedItemID = cleanImage.items[0].id
        expect(cleanImage.canCleanSelected && !cleanImage.canSaveSelected, "reviewed image may be cleaned but not yet saved")
        cleanImage.cleanSelected()
        cleanImage.selectedItemID = cleanImage.items[1].id
        try await wait("clean selected image") { !cleanImage.isProcessing }
        expect(cleanImage.items[0].isSaveReady && cleanImage.items[1].stage == .ready && !cleanImage.items[1].isSaveReady,
               "Clean Selected prepares only the captured image, leaving the other at review")
        expect(!cleanImage.canSaveSelected, "Save Selected follows highlighted image readiness, not total ready count")
        cleanImage.selectedItemID = cleanImage.items[0].id
        expect(cleanImage.canSaveSelected && !cleanImage.canCleanSelected, "prepared image can be saved without being cleaned again")
        cleanImage.cleanAll()
        try await wait("clean all remaining images") { !cleanImage.isProcessing }
        expect(cleanImage.items.allSatisfy(\.isSaveReady), "Clean All prepares all remaining reviewed images")
        cleanImage.clear()

        let videoSource = URL(fileURLWithPath: CommandLine.arguments[2])
        let videoOriginal = try Data(contentsOf: videoSource)
        let secondVideo = directory.appendingPathComponent("selected-second.mov")
        try videoOriginal.write(to: secondVideo)
        let videoURLs = [videoSource, secondVideo]
        let cleanVideo = VideoCleanModel()
        cleanVideo.add(urls: videoURLs)
        try await wait("video clean inspections") { cleanVideo.items.count == 2 && !cleanVideo.isProcessing && cleanVideo.readyForReviewCount == 2 }
        cleanVideo.refreshSizeEstimate()
        try await wait("video Clean size estimate") {
            !cleanVideo.isEstimatingSize && cleanVideo.sizeEstimate != nil
        }
        expect(cleanVideo.sizeEstimate?.basis == .exactClean &&
               (cleanVideo.sizeEstimate?.estimatedBytes ?? 0) > 0,
               "video Clean exposes bytes from its exact passthrough path")
        cleanVideo.selectSelection([])
        try await wait("video Clean unmatched scope size") {
            !cleanVideo.isEstimatingSize &&
                cleanVideo.sizeEstimate?.estimatedBytes == Int64(videoOriginal.count)
        }
        expect(cleanVideo.sizeEstimate?.basis == .exactClean &&
               cleanVideo.sizeEstimate?.estimatedBytes == Int64(videoOriginal.count),
               "video Clean updates to the exact unchanged-copy size when scope has no match")
        cleanVideo.selectSelection(.all)
        cleanVideo.selectedItemID = nil
        expect(!cleanVideo.canCleanSelected && !cleanVideo.canSaveSelected, "video Clean does not use preview fallback for Selected actions")
        cleanVideo.selectedItemID = cleanVideo.items[0].id
        expect(cleanVideo.canCleanSelected && !cleanVideo.canSaveSelected, "reviewed video may be cleaned but not yet saved")
        cleanVideo.cleanSelected()
        expect(cleanVideo.isProcessing && !cleanVideo.canCleanSelected, "video Clean Selected rejects a second operation while busy")
        cleanVideo.selectedItemID = cleanVideo.items[1].id
        try await wait("clean selected video") { !cleanVideo.isProcessing }
        expect(cleanVideo.items[0].isSaveReady && cleanVideo.items[1].stage == .ready && !cleanVideo.items[1].isSaveReady,
               "Clean Selected prepares only the captured video")
        cleanVideo.selectedItemID = cleanVideo.items[0].id
        expect(cleanVideo.canSaveSelected, "prepared video is available to Save Selected")
        let cleanFirst = cleanVideo.items[0].outputURL
        cleanVideo.cleanAll()
        try await wait("clean all remaining videos") { !cleanVideo.isProcessing }
        expect(cleanVideo.items.allSatisfy(\.isSaveReady) && cleanVideo.items[0].outputURL == cleanFirst,
               "Clean All prepares remaining videos without replacing an already prepared output")
        cleanVideo.clear()

        let optimizeVideo = VideoOptimizeModel()
        optimizeVideo.add(urls: videoURLs)
        try await wait("video optimize inspections") { optimizeVideo.items.count == 2 && optimizeVideo.items.allSatisfy { $0.descriptor != nil && $0.stage != .analysing } }
        optimizeVideo.selectedItemID = optimizeVideo.items[0].id
        optimizeVideo.select(optimizeVideo.items[1], modifiers: [.command])
        expect(optimizeVideo.selectedItemCount == 2 && optimizeVideo.canApplySelected,
               "Command-click selects multiple video outputs for one Selected operation")
        optimizeVideo.selectedItemID = nil
        expect(!optimizeVideo.canApplySelected && !optimizeVideo.canSaveSelected, "video Optimize Selected needs a highlight")
        optimizeVideo.settings.trimEndSeconds = 1
        optimizeVideo.selectedItemID = optimizeVideo.items[0].id
        optimizeVideo.applySelected()
        expect(optimizeVideo.isProcessing && !optimizeVideo.canApplySelected, "video Optimize Selected takes its busy lock synchronously")
        optimizeVideo.selectedItemID = optimizeVideo.items[1].id
        try await wait("optimize selected video") { !optimizeVideo.isProcessing }
        expect(optimizeVideo.items[0].isSaveReady && optimizeVideo.items[1].outputURL == nil,
               "Optimize Selected renders only the captured video")
        optimizeVideo.selectedItemID = optimizeVideo.items[0].id
        expect(optimizeVideo.canSaveSelected, "optimized selected video is saveable")
        optimizeVideo.applyAll()
        try await wait("optimize all videos") { !optimizeVideo.isProcessing }
        expect(optimizeVideo.items.allSatisfy(\.isSaveReady), "Optimize All still renders the whole video queue")
        let otherVideoURL = optimizeVideo.items[1].outputURL!
        let otherVideoBytes = try Data(contentsOf: otherVideoURL)
        optimizeVideo.settings.trimEndSeconds = 0.6
        optimizeVideo.applySelected()
        try await wait("reoptimize selected video") { !optimizeVideo.isProcessing }
        try expect(optimizeVideo.items[1].outputURL == otherVideoURL && Data(contentsOf: otherVideoURL) == otherVideoBytes,
                   "reprocessing selected video preserves every other prepared output and its bytes")
        optimizeVideo.clear()

        videoWatermark.kind = .text
        let videoWatermarkWindow = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: 940, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false)
        videoWatermarkWindow.isReleasedWhenClosed = false
        videoWatermarkWindow.contentView = NSHostingView(rootView: VideoWatermarkView(model: videoWatermark))
        videoWatermarkWindow.orderFront(nil)
        await settle()
        videoWatermark.add(urls: videoURLs)
        try await wait("video watermark inspections") { videoWatermark.items.count == 2 && videoWatermark.items.allSatisfy { $0.descriptor != nil && $0.stage != .analysing } }
        try await wait("video watermark size estimate") {
            !videoWatermark.isEstimatingSize && videoWatermark.sizeEstimate != nil
        }
        let initialVideoWatermarkEstimate = videoWatermark.sizeEstimate?.estimatedBytes
        expect(videoWatermark.sizeEstimate?.basis == .realVideoSample &&
               (initialVideoWatermarkEstimate ?? 0) > 0,
               "video Watermark measures a real encoded sample")
        videoWatermark.quality = 0.40
        try await wait("video watermark live size change") {
            !videoWatermark.isEstimatingSize &&
                videoWatermark.sizeEstimate?.basis == .realVideoSample &&
                videoWatermark.sizeEstimate?.estimatedBytes != initialVideoWatermarkEstimate
        }
        expect(videoWatermark.sizeEstimate?.estimatedBytes != initialVideoWatermarkEstimate,
               "video Watermark remeasures when quality changes")
        videoWatermarkWindow.orderOut(nil)
        videoWatermarkWindow.contentView = nil
        videoWatermark.selectedItemID = nil
        expect(!videoWatermark.canApplySelected && !videoWatermark.canSaveSelected, "video Watermark Selected needs a highlight")
        videoWatermark.selectedItemID = videoWatermark.items[0].id
        videoWatermark.applySelected()
        expect(videoWatermark.isProcessing && !videoWatermark.canApplySelected, "video Watermark Selected takes its busy lock synchronously")
        videoWatermark.selectedItemID = videoWatermark.items[1].id
        try await wait("watermark selected video") { !videoWatermark.isProcessing }
        expect(videoWatermark.items[0].isSaveReady && videoWatermark.items[1].outputURL == nil,
               "Watermark Selected renders only the captured video")
        videoWatermark.selectedItemID = videoWatermark.items[0].id
        expect(videoWatermark.canSaveSelected, "watermarked selected video is saveable")
        videoWatermark.kind = .logo
        expect(!videoWatermark.canApply && !videoWatermark.canApplySelected, "video logo processing is unavailable without a chosen logo")
        videoWatermark.clear()
        for url in videoURLs {
            try expect(Data(contentsOf: url) == videoOriginal, "original video is unchanged after all selected/all operations")
        }
    }

    static func cropSettings(policy: ImageCropUpscalePolicy) -> TransformSettingsSnapshot {
        var settings = TransformSettingsSnapshot()
        settings.cropAspect = .custom
        settings.cropWidth = 1400
        settings.cropHeight = 375
        settings.cropUpscalePolicy = policy
        settings.outputFormat = .png
        return settings
    }

    static func fixture(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.red.cgColor)
        context.fillEllipse(in: CGRect(x: width / 2 - 30, y: height / 2 - 30, width: 60, height: 60))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!,
            [kCGImagePropertyOrientation: orientation] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CheckError("fixture encoding failed") }
        return data as Data
    }

    static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CheckError("output cannot decode") }
        return image
    }

    static func pixels(_ data: Data) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let image = try decode(data)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (bytes, image.width, image.height)
    }

    static func settle() async { try? await Task.sleep(nanoseconds: 250_000_000) }

    static func wait(_ label: String, condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw CheckError("Timed out: \(label)")
    }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ label: String) rethrows {
        guard try condition() else { fatalError("FAIL: \(label)") }
        assertions += 1
        FileHandle.standardOutput.write(Data("PASS: \(label)\n".utf8))
    }

    struct CheckError: Error { let message: String; init(_ message: String) { self.message = message } }
}
