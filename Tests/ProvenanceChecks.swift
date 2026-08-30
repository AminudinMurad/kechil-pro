import Foundation

@main
struct ProvenanceChecks {
    private static var passed = 0
    private static var failed = 0

    static func main() {
        print("\nProvenance probe")
        testStandardSourceTypes()
        testGeneratorSpecificPNG()
        testC2PAWebP()
        testC2PABMFFNeutralization()
        testPostScanJPEG()
        testOutputVerification()

        if failed == 0 {
            print("\nALL PROVENANCE CHECKS PASSED (\(passed) assertions)")
        } else {
            print("\nPROVENANCE CHECKS FAILED: \(failed) of \(passed + failed)")
            exit(1)
        }
    }

    private static func testStandardSourceTypes() {
        let generated = png(chunks: [
            chunk("iTXt", bytes("DigitalSourceType\0\0\0\0\0http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia")),
        ])
        let generatedReport = ProvenanceProbe.inspect(generated)
        expect(generatedReport.hasGenerativeAI, "IPTC trainedAlgorithmicMedia is Generative AI")
        expect(generatedReport.carriers.contains(where: { $0.contains("iTXt") }),
               "exact PNG iTXt carrier is reported")

        let computational = png(chunks: [
            chunk("iTXt", bytes("DigitalSourceType\0\0\0\0\0http://cv.iptc.org/newscodes/digitalsourcetype/computationalCapture")),
        ])
        let computationalReport = ProvenanceProbe.inspect(computational)
        expect(!computationalReport.hasGenerativeAI,
               "computationalCapture (phone HDR) is not misreported as Generative AI")
        expect(computationalReport.findings.contains(where: { $0.title.contains("not Generative AI") }),
               "non-generative algorithmic processing is explained")
    }

    private static func testGeneratorSpecificPNG() {
        let parameters = "parameters\0A harbour at dawn\nNegative prompt: blur\nSteps: 24, Sampler: Euler, CFG scale: 7, Seed: 1234, Model: flux"
        let report = ProvenanceProbe.inspect(png(chunks: [chunk("tEXt", bytes(parameters))]))
        expect(report.hasGenerativeAI, "AUTOMATIC1111-style parameters trigger AI emphasis")
        expect(report.findings.contains(where: { $0.kind == .prompt }),
               "prompt and parameters are surfaced")
        expect(report.findings.contains(where: { $0.kind == .model }),
               "model information is surfaced")
        expect(report.generativeFinding?.confidence == .inferred,
               "generator-specific fields are labelled inferred")
    }

    private static func testC2PAWebP() {
        let cbor = cborMap([
            ("claim_generator", "Adobe Firefly"),
            ("digitalSourceType", "http://cv.iptc.org/newscodes/digitalsourcetype/compositeWithTrainedAlgorithmicMedia"),
            ("softwareAgent", "Adobe Firefly 4"),
        ])
        let manifest = box("cbor", cbor)
        let source = webp(chunks: [("C2PA", manifest)])
        let report = ProvenanceProbe.inspect(source)
        expect(report.carriers.contains("WebP C2PA chunk"), "WebP C2PA carrier is detected")
        expect(report.hasGenerativeAI, "C2PA Digital Source Type triggers AI emphasis")
        expect(report.findings.contains(where: { $0.title.contains("Adobe Firefly") }),
               "claim generator is named")
        expect(report.generativeFinding?.confidence == .declared,
               "C2PA field is labelled declared")
        expect(report.limitations.contains(where: { $0.contains("not cryptographically validated") }),
               "C2PA trust-validation limitation is explicit")
        do {
            let clean = try MetadataStripper.strip(source).data
            expect(!ProvenanceProbe.inspect(clean).carriers.contains("WebP C2PA chunk"),
                   "WebP C2PA is absent when the stripped output is re-read")
        } catch {
            expect(false, "C2PA WebP strips without an error: \(error)")
        }
    }

    private static func testC2PABMFFNeutralization() {
        let uuid = Data([
            0xD8, 0xFE, 0xC3, 0xD6, 0x1B, 0x0E, 0x48, 0x3C,
            0x92, 0x97, 0x58, 0x28, 0x87, 0x7E, 0xC4, 0x81,
        ])
        let ftyp = box("ftyp", bytes("heic\0\0\0\0heic"))
        let privateBox = box("uuid", uuid + bytes("c2pa private manifest and prompt"))
        let media = box("mdat", Data([1, 2, 3, 4, 5, 6]))
        let source = ftyp + privateBox + media
        let before = ProvenanceProbe.inspect(source)
        expect(before.carriers.contains("ISO BMFF C2PA uuid box"),
               "HEIF/AVIF C2PA uuid is detected by its standard UUID")

        let result = MetadataStripper.neutralizeC2PABMFFBoxes(in: source)
        expect(result.count == 1, "one C2PA BMFF box is neutralized")
        expect(result.data.count == source.count, "BMFF byte offsets are preserved")
        expect(result.data.suffix(media.count) == media, "following media bytes do not move or change")
        expect(!ProvenanceProbe.inspect(result.data).carriers.contains("ISO BMFF C2PA uuid box"),
               "neutralized BMFF output no longer detects C2PA")
    }

    private static func testPostScanJPEG() {
        let xmp = bytes("http://ns.adobe.com/xap/1.0/\0<x:xmpmeta><DigitalSourceType>trainedAlgorithmicMedia</DigitalSourceType></x:xmpmeta>")
        let source = Data([0xFF, 0xD8])
            + segment(marker: 0xDA, payload: Data([1, 1, 0, 0, 63, 0]))
            + Data([0x11, 0x22, 0x33])
            + segment(marker: 0xE1, payload: xmp)
            + Data([0xFF, 0xD9])
        let report = ProvenanceProbe.inspect(source)
        expect(report.carriers.contains("JPEG APP1 (XMP)"),
               "metadata between progressive JPEG scans is inspected")
        expect(report.hasGenerativeAI, "post-scan XMP is analysed, not merely located")
    }

    private static func testOutputVerification() {
        let source = png(chunks: [
            chunk("tEXt", bytes("parameters\0Steps: 20, Sampler: Euler, Seed: 9")),
        ])
        do {
            let clean = try MetadataStripper.strip(source).data
            let report = ProvenanceProbe.inspect(clean)
            expect(report.carriers.isEmpty && report.findings.isEmpty,
                   "strip output is re-readable as clean")
        } catch {
            expect(false, "PNG fixture strips without an error: \(error)")
        }
    }

    // MARK: Fixtures

    private static func png(chunks extras: [Data]) -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data.append(chunk("IHDR", Data([0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0])))
        for extra in extras { data.append(extra) }
        data.append(chunk("IDAT", Data()))
        data.append(chunk("IEND", Data()))
        return data
    }

    private static func chunk(_ type: String, _ payload: Data) -> Data {
        var data = be32(UInt32(payload.count))
        let typeData = bytes(type)
        data.append(typeData)
        data.append(payload)
        data.append(be32(crc32(typeData + payload)))
        return data
    }

    private static func webp(chunks: [(String, Data)]) -> Data {
        var body = Data("WEBP".utf8)
        for (type, payload) in chunks {
            body.append(Data(type.utf8))
            body.append(le32(UInt32(payload.count)))
            body.append(payload)
            if payload.count & 1 == 1 { body.append(0) }
        }
        return Data("RIFF".utf8) + le32(UInt32(body.count)) + body
    }

    private static func box(_ type: String, _ payload: Data) -> Data {
        be32(UInt32(8 + payload.count)) + Data(type.utf8) + payload
    }

    private static func segment(marker: UInt8, payload: Data) -> Data {
        Data([0xFF, marker]) + be16(UInt16(payload.count + 2)) + payload
    }

    /// Definite CBOR map of text keys and text values; enough to exercise the real
    /// decoder without making the fixture depend on another CBOR library.
    private static func cborMap(_ pairs: [(String, String)]) -> Data {
        var data = cborLength(major: 5, value: pairs.count)
        for (key, value) in pairs {
            data.append(cborText(key))
            data.append(cborText(value))
        }
        return data
    }

    private static func cborText(_ value: String) -> Data {
        let payload = Data(value.utf8)
        return cborLength(major: 3, value: payload.count) + payload
    }

    private static func cborLength(major: UInt8, value: Int) -> Data {
        if value < 24 { return Data([major << 5 | UInt8(value)]) }
        if value <= 0xFF { return Data([major << 5 | 24, UInt8(value)]) }
        return Data([major << 5 | 25]) + be16(UInt16(value))
    }

    private static func bytes(_ value: String) -> Data { Data(value.utf8) }

    private static func be16(_ value: UInt16) -> Data {
        Data([UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    private static func be32(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24), UInt8((value >> 16) & 0xFF),
              UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        if condition() {
            passed += 1
            print("  PASS  \(label)")
        } else {
            failed += 1
            print("  FAIL  \(label)")
        }
    }
}
