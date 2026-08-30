import Foundation

enum MediaSaveError: LocalizedError {
    case missingOutput
    case destinationUnreadable
    case originalWouldBeOverwritten

    var errorDescription: String? {
        switch self {
        case .missingOutput: return "The processed output is no longer available"
        case .destinationUnreadable: return "The saved file could not be reopened"
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
        try data.write(to: destination, options: .atomic)
        guard FileManager.default.isReadableFile(atPath: destination.path) else {
            throw MediaSaveError.destinationUnreadable
        }
    }

    static func copyTemporaryOutput(from temporaryURL: URL, to destination: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: temporaryURL.path) else { throw MediaSaveError.missingOutput }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).kechil-saving-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: temporaryURL, to: staging)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try manager.moveItem(at: staging, to: destination)
        }
        guard manager.isReadableFile(atPath: destination.path) else {
            throw MediaSaveError.destinationUnreadable
        }
    }
}
