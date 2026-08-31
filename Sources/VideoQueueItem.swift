import AppKit
import AVFoundation
import Foundation

struct VideoQueueItem: Identifiable {
    let id: UUID
    let sourceURL: URL
    let sourceFileSize: Int64
    var descriptor: MediaAssetDescriptor?
    var outputDescriptor: MediaAssetDescriptor?
    var stage: MediaJobStage
    var phase: MediaJobPhase?
    var progress: Double?
    /// Every finding reported for the original file, including groups that are not
    /// selected for removal. The inspector uses this to show honest source evidence.
    var detectedFindings: [VideoMetadataFinding]
    /// The multi-select groups used for this item's latest clean run.
    var selection: VideoCleanSelection
    /// Legacy single-preset value retained for source compatibility with older
    /// snapshots/callers. New video UI uses `selection`.
    var findings: [VideoMetadataFinding]
    var remainingFindings: [VideoMetadataFinding]
    var verification: VideoCleanVerification?
    var outputURL: URL?
    var outputFileSize: Int64?
    var poster: NSImage?
    var errorText: String?
    var statusText: String?
    var savedTo: URL?
    var preset: CleanPreset
    var sourceIdentity: CleanSourceIdentity?
    var inspectionReport: VideoMetadataReport?
    var plan: CleanPlanSummary?
    var receipt: CleanReceipt?

    init(sourceURL: URL) {
        id = UUID()
        self.sourceURL = sourceURL
        sourceFileSize = Int64((try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        stage = .queued
        detectedFindings = []
        selection = .all
        findings = []
        remainingFindings = []
        preset = .allMetadata
        sourceIdentity = nil
        inspectionReport = nil
        plan = nil
        receipt = nil
    }

    var displayName: String { sourceURL.lastPathComponent }
    /// Findings from the inspected original. Cleanup selection and output
    /// verification never replace this source-of-truth collection.
    var sourceFindings: [VideoMetadataFinding] {
        if !detectedFindings.isEmpty { return detectedFindings }
        if let inspectionReport { return inspectionReport.findings }
        return findings
    }
    var isSaveReady: Bool {
        guard outputURL != nil, stage == .completed else { return false }
        return receipt?.outcome.isOrdinarySaveAllowed ?? true
    }
    var saveActionTitle: String {
        switch verification {
        case .unchanged: return "Save Unchanged Copy…"
        case .partial: return "Save Partial Copy…"
        default: return "Save Clean Copy…"
        }
    }

    func suggestedFilename(suffix: String, extension ext: String) -> String {
        "\(sourceURL.deletingPathExtension().lastPathComponent)-\(suffix).\(ext)"
    }
}

enum VideoPosterGenerator {
    static func image(for url: URL, at seconds: Double = 0) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 540)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 15)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 15)
        do {
            let requested = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            let (image, _) = try await generator.image(at: requested)
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            return nil
        }
    }
}
