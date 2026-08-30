import AVFoundation
import Foundation

@main
enum OpenAIProvenanceFixtureChecks {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            fail("Usage: fixture-check VIDEO.mov OPENAI_TEST_ID")
        }
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let identifier = CommandLine.arguments[2]
        let descriptor = try await MediaCapabilityProbe.inspectVideo(at: sourceURL)
        let duration = descriptor.duration.map(CMTimeGetSeconds) ?? 0
        expect(abs(duration - 5) < 0.05, "fixture duration is five seconds")
        expect(descriptor.displayWidth == 640 && descriptor.displayHeight == 360,
               "fixture is 640 by 360")
        expect(descriptor.videoCodec == "H.264", "fixture uses H.264")

        let report = try await VideoMetadataProbe.inspect(url: sourceURL)
        let provenance = report.findings.filter { $0.category == .provenance }
        expect(!provenance.isEmpty, "Kechil detects the synthetic C2PA carrier")
        let summaries = report.findings.map(\.valueSummary).joined(separator: " ")
        let bytes = try Data(contentsOf: sourceURL)
        expect(summaries.contains(identifier) || bytes.range(of: Data(identifier.utf8)) != nil,
               "the requested generative test ID is embedded")

        let cleaned = try await VideoCleanPipeline.clean(sourceURL: sourceURL)
        defer { try? FileManager.default.removeItem(at: cleaned.outputURL) }
        expect(!cleaned.inputFindings.isEmpty, "Clean sees removable input metadata")
        if !cleaned.remainingFindings.isEmpty {
            for finding in cleaned.remainingFindings {
                print("REMAINING: \(finding.identifier) | \(finding.displayName) | \(finding.valueSummary)")
            }
        }
        expect(cleaned.remainingFindings.isEmpty, "Clean removes all detected fixture metadata")
        let cleanedBytes = try Data(contentsOf: cleaned.outputURL)
        expect(cleanedBytes.range(of: Data(identifier.utf8)) == nil,
               "Clean removes the embedded generative test ID")
        let cleanedDuration = cleaned.outputDescriptor.duration.map(CMTimeGetSeconds) ?? 0
        expect(abs(cleanedDuration - 5) < 0.05, "Clean preserves the five-second duration")

        print("Kechil fixture checks passed")
        print("Detected provenance findings: \(provenance.count)")
        print("Clean result: \(cleaned.verification.label)")
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
