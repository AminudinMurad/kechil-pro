import AVFoundation
import Foundation

@main
enum ScopedVideoFixtureChecks {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            fail("Usage: scoped-video-check VIDEO.mov OPENAI_TEST_ID")
        }
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let identifier = CommandLine.arguments[2]
        let input = try await VideoMetadataProbe.inspect(url: sourceURL)
        let aiInput = input.findings.filter(CleanPreset.aiMetadata.matchesVideo)
        expect(!aiInput.isEmpty, "AI scope sees the synthetic provenance carrier")
        let evidence = aiInput.flatMap(\.evidence)
        expect(!evidence.isEmpty, "provenance findings expose bounded readable evidence")
        expect(evidence.contains { $0.value.contains(identifier) },
               "evidence includes the embedded generative test ID when readable")

        let scoped = try await VideoCleanPipeline.clean(sourceURL: sourceURL,
                                                         selection: .contentCredentials)
        defer { try? FileManager.default.removeItem(at: scoped.outputURL) }
        expect(scoped.remainingFindings.isEmpty,
               "Content Credentials selection removes the scoped provenance carrier")
        let scopedBytes = try Data(contentsOf: scoped.outputURL)
        expect(!MediaContainerSanitizer.containsC2PABMFFBoxes(in: scopedBytes),
               "Content Credentials selection removes the structural C2PA carrier")
        expect(scopedBytes.range(of: Data(identifier.utf8)) != nil,
               "Content Credentials selection preserves the unselected descriptive copy")

        let cleaned = try await VideoCleanPipeline.clean(sourceURL: sourceURL,
                                                          preset: .aiMetadata)
        defer { try? FileManager.default.removeItem(at: cleaned.outputURL) }
        let bytes = try Data(contentsOf: cleaned.outputURL)
        expect(cleaned.remainingFindings.isEmpty,
               "AI scope has no selected findings remaining")
        expect(bytes.range(of: Data(identifier.utf8)) == nil,
               "AI scope removes the embedded generative test ID")
        print("Scoped video Clean checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail("FAIL: \(message)") }
        print("PASS: \(message)")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }

}
