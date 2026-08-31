import Foundation

/// A lightweight identity captured before inspection or mutation. This is not a
/// cryptographic content hash; it is the inexpensive guard used to reject a plan
/// when the source path, file identity, byte count or modification time changes.
/// Stronger byte/range verification remains the responsibility of the media engine.
struct CleanSourceIdentity: Hashable, Sendable {
    let standardizedPath: String
    let fileSize: Int64
    let modificationNanoseconds: Int64?
    let resourceIdentifier: String?

    static func capture(at url: URL) throws -> CleanSourceIdentity {
        let standardized = url.standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ])
        guard values.isRegularFile == true else {
            throw CleanWorkflowError.sourceUnavailable
        }
        let modified = values.contentModificationDate.map {
            Int64(($0.timeIntervalSince1970 * 1_000_000_000).rounded())
        }
        return CleanSourceIdentity(
            standardizedPath: standardized.path,
            fileSize: Int64(values.fileSize ?? 0),
            modificationNanoseconds: modified,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) })
    }

    func stillMatches(_ url: URL) -> Bool {
        guard let current = try? Self.capture(at: url) else { return false }
        guard current.standardizedPath == standardizedPath,
              current.fileSize == fileSize,
              current.modificationNanoseconds == modificationNanoseconds else { return false }
        if let resourceIdentifier, let currentIdentifier = current.resourceIdentifier {
            return currentIdentifier == resourceIdentifier
        }
        return true
    }
}

enum CleanWorkflowError: LocalizedError {
    case sourceUnavailable
    case sourceChanged
    case outputUnavailable

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            return "The source file is no longer available."
        case .sourceChanged:
            return "The source changed after it was inspected. Inspect it again before cleaning."
        case .outputUnavailable:
            return "The prepared output is no longer available. Clean the file again."
        }
    }
}

/// Media-neutral summary produced from a cached inspection and the current
/// image/video selection. Updating this value must never read or rewrite the file.
struct CleanPlanSummary: Hashable, Sendable {
    let sourceIdentity: CleanSourceIdentity
    let selectionRevision: UInt64
    let selectionTitle: String
    let detectedEntryCount: Int
    let selectedEntryCount: Int
    let unsupportedReasons: [String]
    let warnings: [String]

    var hasRequestedChanges: Bool { selectedEntryCount > 0 }
    var isExecutable: Bool { unsupportedReasons.isEmpty }
}

enum CleanVerificationOutcome: String, Hashable, Sendable {
    case passed
    case failed
    case notChecked
}

struct CleanVerificationCheck: Hashable, Sendable {
    let title: String
    let detail: String
    let outcome: CleanVerificationOutcome
}

enum CleanReceiptOutcome: String, Hashable, Sendable {
    case unchanged
    case verified
    case partial
    case failed

    var isOrdinarySaveAllowed: Bool {
        self == .unchanged || self == .verified
    }
}

/// Compact shared receipt. Media-specific reports continue to carry typed
/// findings; this records the lifecycle facts needed by both Clean routes.
struct CleanReceipt: Hashable, Sendable {
    let sourceIdentity: CleanSourceIdentity
    let outputIdentity: CleanSourceIdentity?
    let selectionRevision: UInt64
    let selectionTitle: String
    let outcome: CleanReceiptOutcome
    let removed: [String]
    let preserved: [String]
    let remaining: [String]
    let unsupported: [String]
    let checks: [CleanVerificationCheck]
    let limitations: [String]
}

enum CleanTemporaryFiles {
    static func makeURL(suffix: String, extension ext: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pro.kechil.app", isDirectory: true)
            .appendingPathComponent("clean", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let safeExtension = ext.isEmpty ? "bin" : ext.lowercased()
        return folder.appendingPathComponent("\(UUID().uuidString)-\(suffix).\(safeExtension)")
    }
}

/// Bridges cancellation from a structured workflow task into the detached work
/// used to keep image decoding and metadata parsing off the main actor. A plain
/// `Task.detached` does not inherit later cancellation from the task awaiting it.
enum CleanCancellation {
    static func value<T: Sendable>(of task: Task<T, Never>) async -> T {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

extension MediaJobStage {
    /// Clean-specific wording for the shared queue stage. Optimize and Watermark
    /// retain the shorter generic labels in `MediaContracts.swift`.
    var cleanLabel: String {
        switch self {
        case .queued: return "Queued"
        case .analysing: return "Inspecting"
        case .ready: return "Ready for review"
        case .processing: return "Cleaning"
        case .cancelling: return "Cancelling"
        case .cancelled: return "Cancelled"
        case .failed: return "Needs attention"
        case .completed: return "Ready to save"
        case .saved: return "Saved"
        }
    }
}
