import Foundation

enum MediaSaveError: LocalizedError {
    case missingOutput
    case destinationAlreadyExists
    case destinationUnreadable
    case destinationMismatch
    case originalWouldBeOverwritten

    var errorDescription: String? {
        switch self {
        case .missingOutput: return "The processed output is no longer available"
        case .destinationAlreadyExists:
            return "Kechil never replaces an existing file. Choose a different filename or folder."
        case .destinationUnreadable: return "The saved file could not be reopened"
        case .destinationMismatch:
            return "The saved file did not match the verified output"
        case .originalWouldBeOverwritten:
            return "Kechil never overwrites an original. Choose a different filename or folder."
        }
    }
}

enum MediaSaveService {
    static func protectOriginals(destination: URL, sourceURLs: [URL]) throws {
        let resolvedDestination = destination.standardizedFileURL.resolvingSymlinksInPath()
        let matchesOriginal = sourceURLs.contains {
            $0.standardizedFileURL.resolvingSymlinksInPath() == resolvedDestination
        }
        if matchesOriginal { throw MediaSaveError.originalWouldBeOverwritten }
    }

    static func uniqueURL(in folder: URL, filename: String) -> URL {
        let manager = FileManager.default
        var candidate = folder.appendingPathComponent(filename)
        guard manager.fileExists(atPath: candidate.path) else { return candidate }
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var number = 2
        repeat {
            let name = ext.isEmpty ? "\(base)-\(number)" : "\(base)-\(number).\(ext)"
            candidate = folder.appendingPathComponent(name)
            number += 1
        } while manager.fileExists(atPath: candidate.path) && number < 10_000
        return candidate
    }

    static func save(data: Data, to destination: URL) throws {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory
            .appendingPathComponent("kechil-save-data-\(UUID().uuidString)")
            .appendingPathExtension(destination.pathExtension)
        defer { try? manager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        try copyTemporaryOutput(from: temporary, to: destination)
    }

    /// The URL returned by an NSSavePanel is a file-level sandbox grant. Creating a
    /// hidden sibling file beside it first would require directory-wide permission
    /// (for example to Desktop) and fails even though the user picked the output
    /// filename. Copy directly to the user-selected destination instead, then bind
    /// the saved bytes to the verified temporary artifact before releasing it.
    ///
    /// Existing destinations are deliberately refused: this preserves both original
    /// protection and an unrelated user file if a save panel name collides.
    static func copyTemporaryOutput(from temporaryURL: URL, to destination: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: temporaryURL.path) else { throw MediaSaveError.missingOutput }
        guard !manager.fileExists(atPath: destination.path) else {
            throw MediaSaveError.destinationAlreadyExists
        }

        var createdDestination = false
        do {
            try manager.copyItem(at: temporaryURL, to: destination)
            createdDestination = true
            guard manager.isReadableFile(atPath: destination.path) else {
                throw MediaSaveError.destinationUnreadable
            }
            guard try filesAreIdentical(temporaryURL, destination) else {
                throw MediaSaveError.destinationMismatch
            }
        } catch {
            // The target did not exist when the operation began, so a successfully
            // created but unverifiable file belongs to this save attempt and can be
            // removed safely. Never remove a file when creation itself failed.
            if createdDestination { try? manager.removeItem(at: destination) }
            throw error
        }
    }

    /// Streaming comparison binds the final save to the exact temporary artifact
    /// that passed Clean verification without allocating memory proportional to a
    /// movie's size.
    static func filesAreIdentical(_ first: URL, _ second: URL,
                                  chunkSize: Int = 1_048_576) throws -> Bool {
        precondition(chunkSize > 0)
        let manager = FileManager.default
        let firstSize = try manager.attributesOfItem(atPath: first.path)[.size] as? NSNumber
        let secondSize = try manager.attributesOfItem(atPath: second.path)[.size] as? NSNumber
        guard firstSize?.int64Value == secondSize?.int64Value else { return false }

        let firstHandle = try FileHandle(forReadingFrom: first)
        let secondHandle = try FileHandle(forReadingFrom: second)
        defer {
            try? firstHandle.close()
            try? secondHandle.close()
        }
        while true {
            let firstChunk = try firstHandle.read(upToCount: chunkSize) ?? Data()
            let secondChunk = try secondHandle.read(upToCount: chunkSize) ?? Data()
            guard firstChunk == secondChunk else { return false }
            if firstChunk.isEmpty { return true }
        }
    }
}
