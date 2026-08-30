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

        try Data("replacement".utf8).write(to: temporary)
        try MediaSaveService.copyTemporaryOutput(from: temporary, to: destination)
        let replacementSaved = try Data(contentsOf: destination)
        check(replacementSaved == Data("replacement".utf8),
              "confirmed non-original destination can be replaced")

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
