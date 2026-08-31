import AVFoundation
import Foundation

struct VideoCleanResult: Sendable {
    let outputURL: URL
    let outputDescriptor: MediaAssetDescriptor
    let inputFindings: [VideoMetadataFinding]
    let remainingFindings: [VideoMetadataFinding]
    let verification: VideoCleanVerification
}

enum VideoPipelineError: LocalizedError {
    case exportUnavailable
    case incompatibleContainer
    case exportFailed(String)
    case verificationFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .exportUnavailable: return "This video cannot be exported without changing its media tracks"
        case .incompatibleContainer: return "The source tracks are incompatible with the selected container"
        case .exportFailed(let detail): return "Video export failed: \(detail)"
        case .verificationFailed(let detail): return "The cleaned copy could not be verified: \(detail)"
        case .cancelled: return "Cancelled; the original is unchanged"
        }
    }
}

enum VideoTemporaryFiles {
    static func makeURL(suffix: String, extension ext: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pro.kechil.app", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return folder.appendingPathComponent("\(UUID().uuidString)-\(suffix).\(ext)")
    }
}

enum VideoCleanPipeline {
    static func clean(sourceURL: URL, preset: CleanPreset = .allMetadata) async throws -> VideoCleanResult {
        try await clean(sourceURL: sourceURL, scope: .preset(preset))
    }

    /// Multi-select video Clean entry point. The legacy `preset:` overload above
    /// remains available for integrations and older tests.
    static func clean(sourceURL: URL,
                      selection: VideoCleanSelection) async throws -> VideoCleanResult {
        try await clean(sourceURL: sourceURL, scope: .selection(selection),
                        inspectedDescriptor: nil, inspectedReport: nil)
    }

    /// Inspect-first entry point. The model passes the cached descriptor/report so
    /// an explicit Clean action does not immediately repeat both source probes.
    static func clean(sourceURL: URL,
                      selection: VideoCleanSelection,
                      inspectedDescriptor: MediaAssetDescriptor,
                      inspectedReport: VideoMetadataReport) async throws -> VideoCleanResult {
        try await clean(sourceURL: sourceURL, scope: .selection(selection),
                        inspectedDescriptor: inspectedDescriptor,
                        inspectedReport: inspectedReport)
    }

    /// Measures the exact bytes produced by the inspect-first Clean path without
    /// retaining or exposing a temporary output. A no-match scope is an exact
    /// byte-for-byte copy, while a matching scope runs the same passthrough
    /// exporter and then discards its temporary result.
    static func estimateSize(sourceURL: URL,
                             selection: VideoCleanSelection,
                             inspectedDescriptor: MediaAssetDescriptor,
                             inspectedReport: VideoMetadataReport) async throws -> MediaSizeEstimate {
        try Task.checkCancellation()
        let sourceBytes = max(inspectedDescriptor.fileSize,
                              Int64((try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        guard inspectedReport.removableFindings.contains(where: selection.matches) else {
            return MediaSizeEstimate(
                sourceBytes: sourceBytes,
                estimatedBytes: sourceBytes,
                basis: .exactClean,
                detail: "No fields matched the \(selection.title.lowercased()) scope; Clean will prepare an unchanged byte-for-byte copy.")
        }

        let result = try await clean(sourceURL: sourceURL, selection: selection,
                                     inspectedDescriptor: inspectedDescriptor,
                                     inspectedReport: inspectedReport)
        defer { try? FileManager.default.removeItem(at: result.outputURL) }
        try Task.checkCancellation()
        let outputBytes = Int64((try? result.outputURL.resourceValues(
            forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard outputBytes > 0 else {
            throw VideoPipelineError.verificationFailed("the temporary Clean output has no readable file size")
        }
        return MediaSizeEstimate(
            sourceBytes: sourceBytes,
            estimatedBytes: outputBytes,
            basis: .exactClean,
            detail: "Measured from the same passthrough Clean export; the temporary output is discarded after measurement.")
    }

    private static func clean(sourceURL: URL,
                              scope: VideoRemovalScope,
                              inspectedDescriptor: MediaAssetDescriptor? = nil,
                              inspectedReport: VideoMetadataReport? = nil) async throws -> VideoCleanResult {
        try Task.checkCancellation()
        let inputDescriptor: MediaAssetDescriptor
        if let inspectedDescriptor { inputDescriptor = inspectedDescriptor }
        else { inputDescriptor = try await MediaCapabilityProbe.inspectVideo(at: sourceURL) }
        let inputReport: VideoMetadataReport
        if let inspectedReport { inputReport = inspectedReport }
        else { inputReport = try await VideoMetadataProbe.inspect(url: sourceURL) }
        guard inputReport.removableFindings.contains(where: scope.matches) else {
            // Keep a separately owned, byte-exact copy so fetched media can still
            // be saved. An empty/no-match scope must never invoke a remux, which
            // may discard unselected container data even with passthrough.
            let outputURL = try VideoTemporaryFiles.makeURL(suffix: "unchanged",
                                                            extension: sourceURL.pathExtension)
            do {
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: sourceURL, to: outputURL)
                try Task.checkCancellation()
                return VideoCleanResult(outputURL: outputURL,
                                        outputDescriptor: inputDescriptor,
                                        inputFindings: inputReport.findings,
                                        remainingFindings: [], verification: .unchanged)
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
        }
        let asset = AVURLAsset(url: sourceURL)
        let exportPreset = AVAssetExportPresetPassthrough
        guard await AVAssetExportSession.compatibility(ofExportPreset: exportPreset,
                                                        with: asset,
                                                        outputFileType: outputFileType(for: sourceURL))
        else { throw VideoPipelineError.incompatibleContainer }
        guard let session = AVAssetExportSession(asset: asset, presetName: exportPreset) else {
            throw VideoPipelineError.exportUnavailable
        }
        let ext = sourceURL.pathExtension.lowercased() == "mov" ? "mov" : "mp4"
        let outputURL = try VideoTemporaryFiles.makeURL(suffix: "clean", extension: ext)
        try? FileManager.default.removeItem(at: outputURL)
        if scope.removesAll {
            session.metadata = []
            session.metadataItemFilter = .forSharing()
        } else {
            // Export sessions copy source metadata unless an explicit metadata
            // array is supplied. Keep every item outside the selected privacy
            // scope; track/timed metadata is filtered by the same identifier/value
            // contract when the exporter exposes it through the source asset.
            session.metadata = try await metadataToKeep(asset: asset,
                                                        scope: scope)
            session.metadataItemFilter = nil
        }

        do {
            try await export(session, to: outputURL, as: outputFileType(for: sourceURL))
        } catch is CancellationError {
            session.cancelExport()
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoPipelineError.cancelled
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        try Task.checkCancellation()

        // AVAssetExportSession's metadata array does not always expose a C2PA
        // UUID carrier. For broad, Content Credentials and legacy AI scopes,
        // neutralize that box after export while preserving its size and every
        // media-data offset. Location/date-only scopes intentionally leave
        // provenance untouched.
        if scope.needsC2PASanitization {
            let exported = try Data(contentsOf: outputURL)
            let sanitized = MediaContainerSanitizer.neutralizeC2PABMFFBoxes(
                in: exported,
                includingAIMetadataItems: scope.removesAIMetadataItems,
                removingAllMetadataItems: scope.removesAll)
            if sanitized.count > 0 {
                try sanitized.data.write(to: outputURL, options: .atomic)
            }
        }

        let outputDescriptor = try await MediaCapabilityProbe.inspectVideo(at: outputURL)
        let outputReport = try await VideoMetadataProbe.inspect(url: outputURL)
        try verify(input: inputDescriptor, output: outputDescriptor)
        let remaining = outputReport.removableFindings.filter { scope.matches($0) }
        let verification: VideoCleanVerification = remaining.isEmpty
            ? .containerOnlyFramesUnverified
            : .partial(remainingCount: remaining.count)
        return VideoCleanResult(outputURL: outputURL,
                                outputDescriptor: outputDescriptor,
                                inputFindings: inputReport.findings,
                                remainingFindings: remaining,
                                verification: verification)
    }

    private static func metadataToKeep(asset: AVAsset,
                                       scope: VideoRemovalScope) async throws -> [AVMetadataItem] {
        let formats = try await asset.load(.availableMetadataFormats)
        var kept: [AVMetadataItem] = []
        for format in formats {
            let items = try await asset.loadMetadata(for: format)
            for item in items {
                let identifier: String
                if let itemIdentifier = item.identifier?.rawValue {
                    identifier = itemIdentifier
                } else if let key = item.key {
                    identifier = String(describing: key)
                } else {
                    identifier = ""
                }
                let commonKey = item.commonKey?.rawValue ?? ""
                let summary = (try? await item.load(.stringValue)) ?? ""
                let probeFinding = VideoMetadataFinding(
                    scope: .file,
                    category: .unknown,
                    identifier: identifier,
                    displayName: commonKey,
                    valueSummary: summary,
                    removable: true)
                if !scope.matches(probeFinding) {
                    kept.append(item)
                }
            }
        }
        return kept
    }

    static func outputFileType(for url: URL) -> AVFileType {
        url.pathExtension.lowercased() == "mov" ? .mov : .mp4
    }

    private static func verify(input: MediaAssetDescriptor,
                               output: MediaAssetDescriptor) throws {
        guard output.displayWidth == input.displayWidth,
              output.displayHeight == input.displayHeight else {
            throw VideoPipelineError.verificationFailed("display dimensions changed")
        }
        guard output.hasAudio == input.hasAudio else {
            throw VideoPipelineError.verificationFailed("the audio-track policy changed")
        }
        if let sourceDuration = input.duration, let outputDuration = output.duration {
            let delta = abs(CMTimeGetSeconds(sourceDuration) - CMTimeGetSeconds(outputDuration))
            guard delta <= max(0.05, 1 / max(1, input.frameRate ?? 30)) else {
                throw VideoPipelineError.verificationFailed("duration changed by \(String(format: "%.3f", delta)) seconds")
            }
        }
    }

    private static func export(_ session: AVAssetExportSession, to url: URL,
                               as fileType: AVFileType) async throws {
        if #available(macOS 15.0, *) {
            try await session.export(to: url, as: fileType)
        } else {
            session.outputURL = url
            session.outputFileType = fileType
            await withCheckedContinuation { continuation in
                session.exportAsynchronously { continuation.resume() }
            }
            switch session.status {
            case .completed: return
            case .cancelled: throw CancellationError()
            case .failed: throw VideoPipelineError.exportFailed(
                session.error?.localizedDescription ?? "the exporter returned no details")
            default: throw VideoPipelineError.exportFailed("the exporter stopped unexpectedly")
            }
        }
    }
}

/// Internal adapter that lets the pipeline support both the original single
/// `CleanPreset` API and the new video multi-select groups without duplicating the
/// export/verification path.
private enum VideoRemovalScope: Sendable {
    case preset(CleanPreset)
    case selection(VideoCleanSelection)

    var removesAll: Bool {
        switch self {
        case .preset(let preset): return preset == .allMetadata
        case .selection(let selection): return selection == .all
        }
    }

    var needsC2PASanitization: Bool {
        switch self {
        case .preset(let preset): return preset == .allMetadata || preset == .aiMetadata
        case .selection(let selection):
            return selection == .all || selection.contains(.contentCredentials)
        }
    }

    var removesAIMetadataItems: Bool {
        switch self {
        case .preset(let preset): return preset == .allMetadata || preset == .aiMetadata
        case .selection(let selection):
            // The independent Content Credentials card must not wipe ordinary
            // title/comment items merely because their text mentions AI.
            return selection == .all
        }
    }

    func matches(_ finding: VideoMetadataFinding) -> Bool {
        switch self {
        case .preset(let preset): return preset.matchesVideo(finding)
        case .selection(let selection): return selection.matches(finding)
        }
    }
}
