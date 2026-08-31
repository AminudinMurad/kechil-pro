import Foundation

@main
struct MediaSaveChecks {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("kechil-media-save-checks-\(UUID().uuidString)",
                                    isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let original = root.appendingPathComponent("original.mov")
        try Data("original".utf8).write(to: original)

        do {
            try MediaSaveService.protectOriginals(
                destination: original, sourceURLs: [original])
            fail("original path was accepted")
        } catch MediaSaveError.originalWouldBeOverwritten {
            pass("original path is rejected")
        }

        let temporary = root.appendingPathComponent("temporary.mov")
        let destination = root.appendingPathComponent("export.mov")
        try Data("first export".utf8).write(to: temporary)
        try MediaSaveService.copyTemporaryOutput(from: temporary, to: destination)
        let firstSaved = try Data(contentsOf: destination)
        check(firstSaved == Data("first export".utf8),
              "new destination receives the output")
        let firstMatches = try MediaSaveService.filesAreIdentical(
            temporary, destination, chunkSize: 3)
        check(firstMatches,
              "saved output matches the verified artifact across chunk boundaries")

        try Data("replacement".utf8).write(to: temporary)
        do {
            try MediaSaveService.copyTemporaryOutput(from: temporary, to: destination)
            fail("existing destination was accepted")
        } catch MediaSaveError.destinationAlreadyExists {
            pass("existing destination is never replaced")
        }
        let preservedFirstSaved = try Data(contentsOf: destination)
        check(preservedFirstSaved == Data("first export".utf8),
              "existing destination stays byte-identical after a rejected save")

        let replacementDestination = root.appendingPathComponent("replacement.mov")
        try MediaSaveService.copyTemporaryOutput(from: temporary, to: replacementDestination)
        let replacementSaved = try Data(contentsOf: replacementDestination)
        check(replacementSaved == Data("replacement".utf8),
              "a fresh destination receives the replacement output")

        let directDataDestination = root.appendingPathComponent("direct-data.png")
        try MediaSaveService.save(data: Data("direct data".utf8), to: directDataDestination)
        let directDataSaved = try Data(contentsOf: directDataDestination)
        check(directDataSaved == Data("direct data".utf8),
              "direct data uses the same verified destination flow")
        do {
            try MediaSaveService.save(data: Data("changed data".utf8), to: directDataDestination)
            fail("existing direct-data destination was accepted")
        } catch MediaSaveError.destinationAlreadyExists {
            pass("direct data does not replace an existing destination")
        }

        let different = root.appendingPathComponent("different.mov")
        try Data("replacemenx".utf8).write(to: different)
        let corruptionDetected = try !MediaSaveService.filesAreIdentical(
            temporary, different, chunkSize: 2)
        check(corruptionDetected,
              "same-size corruption is detected")

        let collision = MediaSaveService.uniqueURL(in: root, filename: "export.mov")
        check(collision.lastPathComponent == "export-2.mov",
              "batch filenames avoid collisions")

        print("Media save checks passed")
    }

    private static func check(_ condition: @autoclosure () -> Bool,
                              _ message: String) {
        if condition() { pass(message) } else { fail(message) }
    }

    private static func pass(_ message: String) { print("  PASS  \(message)") }

    private static func fail(_ message: String) -> Never {
        fputs("  FAIL  \(message)\n", stderr)
        exit(1)
    }
}
