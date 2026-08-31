import AVFoundation
import Foundation

@main
enum VideoCleanSafetyChecks {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { exit(2) }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("kechil-video-safety-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("ordinary-title.mov")
        let title = "OpenAI interview: ordinary descriptive title"
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset,
                                                presetName: AVAssetExportPresetPassthrough) else { exit(2) }
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        item.value = title as NSString
        item.extendedLanguageTag = "und"
        session.metadata = [item]
        session.metadataItemFilter = nil
        if #available(macOS 15.0, *) {
            try await session.export(to: source, as: .mov)
        } else {
            session.outputURL = source
            session.outputFileType = .mov
            await withCheckedContinuation { continuation in
                session.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed else {
                throw session.error ?? VideoPipelineError.exportFailed("fixture export failed")
            }
        }
        // A harmless free box makes an unnecessary remux observable: the old
        // exporter discarded it even with no selected metadata to remove.
        let padding = box("free", Data("unselected padding must stay byte-identical".utf8))
        try (Data(contentsOf: source) + padding).write(to: source)
        let originalBytes = try Data(contentsOf: source)
        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            print("\(condition ? "PASS" : "FAIL"): \(message)")
            if !condition { failures += 1 }
        }
        for (selection, label) in [(VideoCleanSelection(), "empty selection"),
                                   (.location, "unmatched Location selection"),
                                   (.contentCredentials, "credentials-only title selection")] {
            let result = try await VideoCleanPipeline.clean(sourceURL: source, selection: selection)
            let outputBytes = try Data(contentsOf: result.outputURL)
            expect(outputBytes == originalBytes, "\(label) keeps source bytes exactly when nothing matches")
            expect(result.verification == .unchanged, "\(label) reports unchanged, not cleaned")
            expect(result.outputURL != source, "\(label) owns a separate temporary output")
            let saved = folder.appendingPathComponent("\(selection.rawValue)-saved.mov")
            try MediaSaveService.copyTemporaryOutput(from: result.outputURL, to: saved)
            expect(try Data(contentsOf: saved) == originalBytes,
                   "\(label) can save unchanged local or fetched media")
            try FileManager.default.removeItem(at: result.outputURL)
            expect(FileManager.default.fileExists(atPath: source.path),
                   "\(label) output cleanup never deletes the source")
        }

        // A credential carrier and an ordinary title must remain independent.
        let mixed = folder.appendingPathComponent("credentials-and-title.mov")
        let uuid: [UInt8] = [0xd8, 0xfe, 0xc3, 0xd6, 0x1b, 0x0e, 0x48, 0x3c,
                             0x92, 0x97, 0x58, 0x28, 0x87, 0x7e, 0xc4, 0x81]
        let credential = box("uuid", Data(uuid) + Data("c2pa safety-credential-fixture".utf8))
        try (originalBytes + credential).write(to: mixed)
        let cleaned = try await VideoCleanPipeline.clean(sourceURL: mixed, selection: .contentCredentials)
        defer { try? FileManager.default.removeItem(at: cleaned.outputURL) }
        let output = AVURLAsset(url: cleaned.outputURL)
        let metadata = try await output.load(.commonMetadata)
        var outputTitles: [String] = []
        for value in metadata where value.commonKey == .commonKeyTitle {
            if let text = try await value.load(.stringValue) { outputTitles.append(text) }
        }
        expect(outputTitles.contains(title), "credentials-only clean retains ordinary OpenAI title")
        expect(cleaned.remainingFindings.isEmpty, "credentials-only clean removes detected credential carrier")
        expect(try Data(contentsOf: source) == originalBytes, "original fixture remains byte-identical")

        let legacy = try await VideoCleanPipeline.clean(sourceURL: mixed, preset: .aiMetadata)
        defer { try? FileManager.default.removeItem(at: legacy.outputURL) }
        let legacyAsset = AVURLAsset(url: legacy.outputURL)
        let legacyMetadata = try await legacyAsset.load(.commonMetadata)
        var legacyTitles: [String] = []
        for item in legacyMetadata where item.commonKey == .commonKeyTitle {
            if let text = try await item.load(.stringValue) { legacyTitles.append(text) }
        }
        expect(legacyTitles.contains(title),
               "legacy AI scope keeps an ordinary title mentioning OpenAI")

        let titleItem = box("name", Data(title.utf8))
        let aiItem = box("prompt", Data("prompt\0negative prompt: blur; sampler: Euler".utf8))
        let structural = box("moov", box("ilst", titleItem + aiItem) + credential)
        let strict = MediaContainerSanitizer.neutralizeC2PABMFFBoxes(
            in: structural, includingAIMetadataItems: false)
        let broad = MediaContainerSanitizer.neutralizeC2PABMFFBoxes(in: structural)
        expect(strict.data.range(of: Data(title.utf8)) != nil && strict.count == 1,
               "strict credential sanitizer preserves descriptive item payload")
        expect(broad.data.range(of: Data(title.utf8)) != nil &&
               broad.data.range(of: Data("sampler: Euler".utf8)) == nil && broad.count == 2,
               "legacy broad/AI sanitizer retains intentional AI-item cleanup")
        expect(strict.data.count == structural.count && broad.data.count == structural.count,
               "both sanitizer modes preserve container size")
        if failures > 0 { exit(1) }
        print("Video Clean safety checks passed")
    }

    private static func box(_ type: String, _ payload: Data) -> Data {
        let size = UInt32(payload.count + 8)
        return Data([UInt8(size >> 24), UInt8((size >> 16) & 255),
                     UInt8((size >> 8) & 255), UInt8(size & 255)]) + Data(type.utf8) + payload
    }
}
