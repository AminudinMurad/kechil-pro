import Foundation
import ImageIO
import Security

// MARK: - Public report model

/// How directly a provenance statement is supported by the bytes in the file.
///
/// None of these levels means Kechil PRO has cryptographically validated a C2PA
/// signature. `declared` means the value came from a C2PA manifest; the report carries
/// an explicit limitation until full trust-chain and revocation validation exists.
enum ProvenanceConfidence: String {
    case declared = "Declared in Content Credentials"
    case stated = "Stated in unsigned metadata"
    case inferred = "Inferred from generator-specific fields"
}

enum ProvenanceFindingKind: String {
    case generativeAI
    case generator
    case sourceType
    case prompt
    case model
    case editHistory
    case ingredient
    case embeddedAsset
    case identity
    case correlationID
    case location
    case softBinding
    case other
}

struct ProvenanceFinding: Identifiable {
    let id = UUID()
    let kind: ProvenanceFindingKind
    let title: String
    let detail: String
    let protocolName: String
    let confidence: ProvenanceConfidence

    var isGenerativeSignal: Bool { kind == .generativeAI }
}

struct ProvenanceReport {
    enum Coverage {
        case containerComplete
        case partial
    }

    let format: ImageFormat
    let carriers: [String]
    let findings: [ProvenanceFinding]
    let stillPresent: [String]
    let limitations: [String]
    let coverage: Coverage

    static func empty(format: ImageFormat) -> ProvenanceReport {
        ProvenanceReport(format: format, carriers: [], findings: [], stillPresent: [],
                         limitations: [],
                         coverage: format == .other ? .partial : .containerComplete)
    }

    var generativeFinding: ProvenanceFinding? {
        findings.first(where: \.isGenerativeSignal)
    }

    var hasGenerativeAI: Bool { generativeFinding != nil }
    var hasDetectedMetadata: Bool { !carriers.isEmpty || !findings.isEmpty }
}

// MARK: - Probe

/// Read-only provenance and metadata inspection.
///
/// The same probe runs on input and output. This is intentionally separate from the
/// stripper: an edit reporting success is not evidence that its output is clean.
enum ProvenanceProbe {
    static func inspect(_ data: Data) -> ProvenanceReport {
        guard !data.isEmpty else { return .empty(format: .other) }
        var builder = ReportBuilder(format: MetadataStripper.detect(data))
        let bytes = [UInt8](data)

        switch builder.format {
        case .jpeg: inspectJPEG(bytes, builder: &builder)
        case .png: inspectPNG(bytes, builder: &builder)
        case .webp: inspectWebP(bytes, builder: &builder)
        case .other: inspectOther(data, bytes: bytes, builder: &builder)
        }

        inspectImageIO(data, builder: &builder)
        inspectRawSignals(bytes, protocolName: "file bytes", builder: &builder)
        return builder.report
    }

    // MARK: JPEG

    /// Walks every JPEG scan, rather than stopping at the first SOS. This read-only
    /// walk is also the oracle used to verify the output of the stripping algorithm.
    private static func inspectJPEG(_ bytes: [UInt8], builder: inout ReportBuilder) {
        guard bytes.count >= 2 else { return }
        var i = 2
        var app11Parts: [(instance: UInt16, sequence: UInt32, data: Data)] = []

        while i + 1 < bytes.count {
            guard bytes[i] == 0xFF else { i += 1; continue }
            var markerOffset = i
            while markerOffset + 1 < bytes.count, bytes[markerOffset + 1] == 0xFF {
                markerOffset += 1
            }
            guard markerOffset + 1 < bytes.count else { break }
            let marker = bytes[markerOffset + 1]
            i = markerOffset

            if marker == 0x00 { i += 2; continue }
            if marker == 0xD9 {
                if i + 2 < bytes.count {
                    builder.addCarrier("JPEG trailing data after EOI")
                }
                break
            }
            if (0xD0...0xD7).contains(marker) || marker == 0x01 || marker == 0xD8 {
                i += 2
                continue
            }
            guard i + 3 < bytes.count else { break }
            let length = readBE16(bytes, i + 2).map(Int.init) ?? 0
            guard length >= 2, i + 2 + length <= bytes.count else { break }
            let payloadStart = i + 4
            let end = i + 2 + length
            let payload = Data(bytes[payloadStart..<end])

            switch marker {
            case 0xE1:
                let signature = ascii(bytes, payloadStart, min(40, end - payloadStart))
                if signature.hasPrefix("Exif") {
                    if !ImageRenderingMetadata.isOrientationOnlyEXIF(payload) {
                        builder.addCarrier("JPEG APP1 (EXIF)")
                    }
                } else if signature.contains("ns.adobe.com/xap") ||
                            signature.contains("<?xpacket") || signature.contains("<x:xmpmeta") {
                    builder.addCarrier("JPEG APP1 (XMP)")
                    inspectXMP(payload, protocolName: "XMP in JPEG APP1", builder: &builder)
                } else {
                    builder.addCarrier("JPEG APP1 metadata")
                    inspectTextBlob(payload, key: "APP1", protocolName: "JPEG APP1",
                                    confidence: .stated, builder: &builder)
                }
            case 0xEB:
                // ISO 19566-5 JPEG fragmentation begins with common identifier "JP",
                // then a box instance number and packet sequence number.
                if payload.count >= 8, payload[payload.startIndex] == 0x4A,
                   payload[payload.startIndex + 1] == 0x50 {
                    let p = [UInt8](payload)
                    let instance = readBE16(p, 2) ?? 0
                    let sequence = readBE32(p, 4) ?? 0
                    app11Parts.append((instance, sequence, Data(p.dropFirst(8))))
                    builder.addCarrier("JPEG APP11 (C2PA / JUMBF)")
                } else {
                    builder.addCarrier("JPEG APP11")
                    inspectC2PAPayload(payload, protocolName: "JPEG APP11", builder: &builder)
                }
            case 0xED:
                builder.addCarrier("JPEG APP13 (IPTC / Photoshop)")
            case 0xFE:
                builder.addCarrier("JPEG COM comment")
                inspectTextBlob(payload, key: "comment", protocolName: "JPEG COM",
                                confidence: .stated, builder: &builder)
            default:
                if (0xE0...0xEF).contains(marker), marker != 0xE0,
                   marker != 0xE2, marker != 0xEE {
                    builder.addCarrier("JPEG APP\(Int(marker) - 0xE0)")
                }
            }

            if marker == 0xDA {
                // The SOS header has a normal segment length. Entropy-coded bytes then
                // continue until an unstuffed, non-restart marker.
                i = end
                while i + 1 < bytes.count {
                    guard bytes[i] == 0xFF else { i += 1; continue }
                    var j = i + 1
                    while j < bytes.count, bytes[j] == 0xFF { j += 1 }
                    guard j < bytes.count else { i = bytes.count; break }
                    let next = bytes[j]
                    if next == 0x00 || (0xD0...0xD7).contains(next) {
                        i = j + 1
                        continue
                    }
                    i = j - 1
                    break
                }
            } else {
                i = end
            }
        }

        for group in Dictionary(grouping: app11Parts, by: \.instance).values {
            let joined = group.sorted { $0.sequence < $1.sequence }.reduce(into: Data()) {
                $0.append($1.data)
            }
            inspectC2PAPayload(joined, protocolName: "C2PA in JPEG APP11", builder: &builder)
        }
    }

    // MARK: PNG

    private static func inspectPNG(_ bytes: [UInt8], builder: inout ReportBuilder) {
        var i = 8
        var textBudget = PNGTextMetadata.maximumImageTextBytes
        while i + 12 <= bytes.count {
            guard let size32 = readBE32(bytes, i) else { break }
            let size = Int(size32)
            guard size <= bytes.count - i - 12 else { break }
            let type = ascii(bytes, i + 4, 4)
            let payload = Data(bytes[(i + 8)..<(i + 8 + size)])

            switch type {
            case "tEXt", "zTXt", "iTXt":
                do {
                    let field = try PNGTextMetadata.decode(type: type, payload: payload, remainingBytes: &textBudget)
                    builder.addCarrier("PNG \(type): \(field.key)")
                    if field.key.lowercased().contains("xml") || field.text.contains("<x:xmpmeta") ||
                        field.text.contains("<?xpacket") {
                        inspectXMP(Data(field.text.utf8), protocolName: "XMP in PNG \(type)",
                                   builder: &builder)
                    }
                    analyzeText(key: field.key, value: field.text, protocolName: "PNG \(type)",
                                confidence: .inferred, builder: &builder)
                } catch {
                    builder.addCarrier("PNG \(type): undecoded text")
                    builder.addLimitation(error.localizedDescription)
                    builder.coverage = .partial
                }
            case "eXIf":
                if !ImageRenderingMetadata.isOrientationOnlyEXIF(payload) { builder.addCarrier("PNG eXIf") }
            case "tIME": builder.addCarrier("PNG tIME timestamp")
            case "caBX":
                builder.addCarrier("PNG caBX (C2PA / JUMBF)")
                inspectC2PAPayload(payload, protocolName: "C2PA in PNG caBX", builder: &builder)
            case "dSIG": builder.addCarrier("PNG dSIG digital signature")
            default: break
            }

            i += 12 + size
            if type == "IEND" { break }
        }
    }

    // MARK: WebP

    private static func inspectWebP(_ bytes: [UInt8], builder: inout ReportBuilder) {
        var i = 12
        while i + 8 <= bytes.count {
            guard let size32 = readLE32(bytes, i + 4) else { break }
            let size = Int(size32)
            guard size <= bytes.count - i - 8 else { break }
            let fourCC = ascii(bytes, i, 4)
            let payload = Data(bytes[(i + 8)..<(i + 8 + size)])
            switch fourCC {
            case "EXIF":
                if !ImageRenderingMetadata.isOrientationOnlyEXIF(payload) { builder.addCarrier("WebP EXIF") }
            case "XMP ":
                builder.addCarrier("WebP XMP")
                inspectXMP(payload, protocolName: "XMP in WebP", builder: &builder)
            case "C2PA":
                builder.addCarrier("WebP C2PA chunk")
                inspectC2PAPayload(payload, protocolName: "C2PA in WebP", builder: &builder)
            default: break
            }
            i += 8 + size + (size & 1)
        }
    }

    // MARK: Other containers and ImageIO

    private static func inspectOther(_ data: Data, bytes: [UInt8],
                                     builder: inout ReportBuilder) {
        let strings = printableStrings(bytes, minimumLength: 5)
        let bmffC2PAUUID = Data([
            0xD8, 0xFE, 0xC3, 0xD6, 0x1B, 0x0E, 0x48, 0x3C,
            0x92, 0x97, 0x58, 0x28, 0x87, 0x7E, 0xC4, 0x81,
        ])
        if let uuid = data.range(of: bmffC2PAUUID) {
            builder.addCarrier("ISO BMFF C2PA uuid box")
            let payloadStart = uuid.upperBound
            if payloadStart < data.endIndex {
                inspectC2PAPayload(Data(data[payloadStart...]),
                                   protocolName: "C2PA in ISO BMFF uuid",
                                   builder: &builder)
            }
        } else if strings.contains(where: { $0.localizedCaseInsensitiveContains("c2pa") ||
            $0.localizedCaseInsensitiveContains("jumb") }) {
            builder.addCarrier("C2PA / JUMBF in an unparsed container")
            builder.addLimitation("This container's C2PA box location is detected but not structurally removed or fully decoded.")
            inspectC2PAPayload(data, protocolName: "C2PA in unparsed container", builder: &builder)
        }
        if strings.contains(where: { $0.contains("ns.adobe.com/xap") ||
            $0.contains("<x:xmpmeta") || $0.contains("<?xpacket") }) {
            builder.addCarrier("XMP in an unparsed container")
            inspectXMP(data, protocolName: "XMP in unparsed container", builder: &builder)
        }
        builder.coverage = .partial
    }

    private static func inspectImageIO(_ data: Data, builder: inout ReportBuilder) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else { return }

        var pairs: [(String, String)] = []
        flattenProperty(properties, path: "", into: &pairs)
        let gpsPairs = pairs.filter { $0.0.lowercased().contains("gps") }
        if !gpsPairs.isEmpty {
            let coordinates = gpsPairs
                .filter { $0.0.lowercased().contains("latitude") ||
                          $0.0.lowercased().contains("longitude") }
                .prefix(4)
                .map { "\($0.0.components(separatedBy: ".").last ?? $0.0)=\($0.1)" }
                .joined(separator: ", ")
            builder.addFinding(kind: .location, title: "GPS coordinates present",
                               detail: coordinates.isEmpty ? "The image contains a GPS metadata dictionary." : coordinates,
                               protocolName: "ImageIO metadata", confidence: .stated)
        }

        for (key, value) in pairs {
            let lower = key.lowercased()
            if lower.contains("software") || lower.contains("creatortool") ||
                lower.contains("usercomment") || lower.contains("imagedescription") ||
                lower.contains("documentid") || lower.contains("instanceid") ||
                lower.contains("digitalsourcetype") {
                analyzeText(key: key, value: value, protocolName: "EXIF / TIFF / ImageIO",
                            confidence: .stated, builder: &builder)
            }
        }
    }

    private static func flattenProperty(_ value: Any, path: String,
                                        into pairs: inout [(String, String)]) {
        if let dictionary = value as? [CFString: Any] {
            for (key, child) in dictionary {
                let name = path.isEmpty ? key as String : "\(path).\(key as String)"
                flattenProperty(child, path: name, into: &pairs)
            }
        } else if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                flattenProperty(child, path: path.isEmpty ? key : "\(path).\(key)", into: &pairs)
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                flattenProperty(child, path: "\(path)[\(index)]", into: &pairs)
            }
        } else {
            pairs.append((path, String(describing: value)))
        }
    }

    // MARK: XMP and generator fields

    private static func inspectXMP(_ data: Data, protocolName: String,
                                   builder: inout ReportBuilder) {
        let raw = utf8(data)
        guard !raw.isEmpty else { return }
        builder.addCarrier(protocolName)

        if let document = try? XMLDocument(data: data, options: [.nodePreserveAll]),
           let nodes = try? document.nodes(forXPath: "//*") {
            for node in nodes {
                guard let element = node as? XMLElement else { continue }
                if let value = element.stringValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    analyzeText(key: element.name ?? "XMP element", value: value,
                                protocolName: protocolName, confidence: .stated,
                                builder: &builder)
                }
                for attribute in element.attributes ?? [] {
                    if let value = attribute.stringValue {
                        analyzeText(key: attribute.name ?? "XMP attribute", value: value,
                                    protocolName: protocolName, confidence: .stated,
                                    builder: &builder)
                    }
                }
            }
        } else {
            inspectTextBlob(data, key: "XMP", protocolName: protocolName,
                            confidence: .stated, builder: &builder)
        }
    }

    private static func inspectTextBlob(_ data: Data, key: String, protocolName: String,
                                        confidence: ProvenanceConfidence,
                                        builder: inout ReportBuilder) {
        let strings = printableStrings([UInt8](data), minimumLength: 4)
        if strings.isEmpty {
            analyzeText(key: key, value: utf8(data), protocolName: protocolName,
                        confidence: confidence, builder: &builder)
        } else {
            for string in strings.prefix(80) {
                analyzeText(key: key, value: string, protocolName: protocolName,
                            confidence: confidence, builder: &builder)
            }
        }
    }

    private static func analyzeText(key: String, value: String, protocolName: String,
                                    confidence: ProvenanceConfidence,
                                    builder: inout ReportBuilder) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let joined = "\(key) \(trimmed)".lowercased()

        let generativeTypes: [(String, String)] = [
            ("compositewithtrainedalgorithmicmedia", "Edited using Generative AI"),
            ("compositedwithtrainedalgorithmicmedia", "Edited using Generative AI"),
            ("trainedalgorithmicmedia", "Created using Generative AI"),
            ("compositesynthetic", "Composite including Generative AI elements"),
        ]
        if let source = generativeTypes.first(where: { joined.contains($0.0) }) {
            builder.addFinding(kind: .generativeAI, title: source.1,
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: confidence)
            builder.addFinding(kind: .sourceType, title: "Digital Source Type",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: confidence)
        }

        // These values explicitly describe non-generative processing. Surface them as
        // context, but never turn them into the red AI-generated banner.
        if joined.contains("computationalcapture") || joined.contains("algorithmicallyenhanced") ||
            joined.contains("algorithmicmedia") {
            builder.addFinding(kind: .sourceType, title: "Algorithmic processing (not Generative AI evidence)",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: confidence)
        }

        let generator = MetadataTextClassifier.isGeneratorField(key: key, value: value)
            ? MetadataTextClassifier.knownGenerator(in: value)
            : nil
        if let generator {
            builder.addFinding(kind: .generator, title: generator,
                               detail: "Named by \(key)", protocolName: protocolName,
                               confidence: confidence)
            builder.addFinding(kind: .generativeAI, title: "AI generator detected: \(generator)",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: confidence)
        }

        let lowerKey = key.lowercased()
        if MetadataTextClassifier.isGenerationParameters(key: key, value: value) {
            builder.addFinding(kind: .generator, title: "Stable Diffusion / AUTOMATIC1111-style parameters",
                               detail: "Generator-specific parameter block", protocolName: protocolName,
                               confidence: .inferred)
            builder.addFinding(kind: .generativeAI, title: "AI generation parameters detected",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: .inferred)
        }
        if MetadataTextClassifier.isComfyWorkflow(key: key, value: value) {
            builder.addFinding(kind: .generator, title: "ComfyUI workflow",
                               detail: "Embedded node graph", protocolName: protocolName,
                               confidence: .inferred)
            builder.addFinding(kind: .generativeAI, title: "ComfyUI generation data detected",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: .inferred)
        }
        if lowerKey.contains("invokeai_") || lowerKey.contains("sd-metadata") {
            builder.addFinding(kind: .generator, title: "InvokeAI metadata",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: .inferred)
            builder.addFinding(kind: .generativeAI, title: "InvokeAI generation data detected",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: .inferred)
        }

        if lowerKey.contains("prompt") || lowerKey.contains("parameters") ||
            lowerKey.contains("usercomment") || lowerKey.contains("description") {
            if generator != nil || joined.contains("negative prompt") || joined.contains("sampler") ||
                joined.contains("seed") || joined.contains("model") {
                builder.addFinding(kind: .prompt, title: "Generation prompt / parameters",
                                   detail: shortened(trimmed), protocolName: protocolName,
                                   confidence: confidence == .declared ? .declared : .inferred)
            }
        }
        if lowerKey.contains("model") || joined.contains("model hash") || joined.contains("model:") {
            builder.addFinding(kind: .model, title: "Model information",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: confidence)
        }
        if lowerKey.contains("history") || lowerKey.contains("softwareagent") ||
            joined.contains("c2pa.actions") {
            builder.addFinding(kind: .editHistory, title: "Editing software / action history",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: confidence)
        }
        if lowerKey.contains("ingredient") {
            builder.addFinding(kind: .ingredient, title: "Source ingredient reference",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: confidence)
        }
        if lowerKey.contains("documentid") || lowerKey.contains("instanceid") ||
            lowerKey.contains("originaldocumentid") {
            builder.addFinding(kind: .correlationID, title: "Cross-file correlation ID",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: confidence)
        }
        if lowerKey.contains("provenance") && (trimmed.contains("http://") || trimmed.contains("https://")) {
            builder.addFinding(kind: .correlationID, title: "External provenance pointer",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: confidence)
        }
        if joined.contains("soft binding") || joined.contains("soft_binding") ||
            joined.contains("c2pa.watermarked") || joined.contains("watermarking") {
            builder.addFinding(kind: .softBinding, title: "Declared in-pixel soft binding",
                               detail: shortened(trimmed), protocolName: protocolName,
                               confidence: confidence)
            builder.addStillPresent("A declared in-pixel watermark or fingerprint may remain after metadata removal.")
        }
    }

    // MARK: C2PA / JUMBF / CBOR

    private static func inspectC2PAPayload(_ data: Data, protocolName: String,
                                           builder: inout ReportBuilder) {
        guard !data.isEmpty else { return }
        builder.sawC2PA = true
        builder.addLimitation("C2PA fields are decoded locally, but signature trust, revocation and asset binding are not cryptographically validated.")

        let bytes = [UInt8](data)
        var foundBox = false
        walkBoxes(bytes, start: 0, end: bytes.count, depth: 0,
                  protocolName: protocolName, foundBox: &foundBox, builder: &builder)

        // Fragmented JPEG data or a vendor wrapper can leave bytes before the first
        // ISO box. Scan for well-known box types and try again from the size field.
        if !foundBox {
            for type in ["jumb", "jumd", "cbor", "json", "brob"] {
                guard let typeRange = data.range(of: Data(type.utf8)), typeRange.lowerBound >= 4 else { continue }
                let start = typeRange.lowerBound - 4
                walkBoxes(bytes, start: start, end: bytes.count, depth: 0,
                          protocolName: protocolName, foundBox: &foundBox, builder: &builder)
            }
        }

        inspectTextBlob(data, key: "C2PA manifest", protocolName: protocolName,
                        confidence: .declared, builder: &builder)
    }

    private static func walkBoxes(_ bytes: [UInt8], start: Int, end: Int, depth: Int,
                                  protocolName: String, foundBox: inout Bool,
                                  builder: inout ReportBuilder) {
        guard depth < 16, start >= 0, end <= bytes.count else { return }
        var i = start
        while i + 8 <= end {
            guard let size32 = readBE32(bytes, i) else { break }
            let type = ascii(bytes, i + 4, 4)
            var header = 8
            var size = Int(size32)
            if size32 == 1 {
                guard let extended = readBE64(bytes, i + 8), extended <= UInt64(Int.max) else { break }
                size = Int(extended)
                header = 16
            } else if size32 == 0 {
                size = end - i
            }
            guard size >= header, size <= end - i else { break }
            let payloadStart = i + header
            let boxEnd = i + size
            let payload = Data(bytes[payloadStart..<boxEnd])
            foundBox = true

            switch type {
            case "jumb":
                walkBoxes(bytes, start: payloadStart, end: boxEnd, depth: depth + 1,
                          protocolName: protocolName, foundBox: &foundBox, builder: &builder)
            case "jumd":
                let strings = printableStrings([UInt8](payload), minimumLength: 4)
                for label in strings.prefix(8) {
                    if label.lowercased().contains("c2pa") {
                        builder.addCarrier("JUMBF label: \(shortened(label, limit: 120))")
                    }
                    analyzeText(key: "JUMBF label", value: label,
                                protocolName: protocolName, confidence: .declared,
                                builder: &builder)
                    if label.lowercased().contains("thumbnail") {
                        builder.addFinding(kind: .embeddedAsset,
                                           title: "Embedded thumbnail or source preview",
                                           detail: shortened(label), protocolName: protocolName,
                                           confidence: .declared)
                    }
                }
            case "cbor":
                do {
                    var decoder = CBORDecoder(bytes: [UInt8](payload))
                    let value = try decoder.decode()
                    inspectCBOR(value, path: "", protocolName: protocolName, builder: &builder)
                } catch {
                    builder.addLimitation("A C2PA CBOR box was present but could not be fully decoded.")
                }
            case "json":
                if let object = try? JSONSerialization.jsonObject(with: payload) {
                    inspectJSON(object, path: "", protocolName: protocolName, builder: &builder)
                } else {
                    inspectTextBlob(payload, key: "C2PA JSON", protocolName: protocolName,
                                    confidence: .declared, builder: &builder)
                }
            case "brob":
                builder.addCarrier("C2PA Brotli-compressed box")
                builder.addLimitation("A Brotli-compressed C2PA box is present and cannot be decoded by the built-in probe.")
            case "bidb", "bfdb", "jpg ", "jpeg":
                builder.addFinding(kind: .embeddedAsset, title: "Embedded C2PA asset",
                                   detail: "\(type) box, \(payload.count) bytes",
                                   protocolName: protocolName, confidence: .declared)
            default:
                if type == "uuid" || type == "c2pa" {
                    walkBoxes(bytes, start: payloadStart, end: boxEnd, depth: depth + 1,
                              protocolName: protocolName, foundBox: &foundBox, builder: &builder)
                }
            }
            i = boxEnd
        }
    }

    private static func inspectCBOR(_ value: CBORValue, path: String,
                                    protocolName: String, builder: inout ReportBuilder) {
        switch value {
        case .text(let text):
            analyzeText(key: path.isEmpty ? "CBOR text" : path, value: text,
                        protocolName: protocolName, confidence: .declared, builder: &builder)
        case .bytes(let data):
            if path.lowercased().contains("x5chain") || path.hasSuffix(".33") {
                if let certificate = SecCertificateCreateWithData(nil, data as CFData),
                   let subject = SecCertificateCopySubjectSummary(certificate) as String? {
                    builder.addFinding(kind: .identity, title: "C2PA signer certificate",
                                       detail: subject, protocolName: protocolName,
                                       confidence: .declared)
                }
            }
            inspectTextBlob(data, key: path.isEmpty ? "CBOR bytes" : path,
                            protocolName: protocolName, confidence: .declared,
                            builder: &builder)
        case .array(let values):
            for (index, child) in values.enumerated() {
                inspectCBOR(child, path: "\(path)[\(index)]", protocolName: protocolName,
                            builder: &builder)
            }
        case .map(let pairs):
            for (key, child) in pairs {
                let component = key.pathComponent
                let next = path.isEmpty ? component : "\(path).\(component)"
                inspectCBOR(child, path: next, protocolName: protocolName, builder: &builder)
            }
        case .tag(_, let child):
            inspectCBOR(child, path: path, protocolName: protocolName, builder: &builder)
        case .unsigned, .negative, .boolean, .null, .floating: break
        }
    }

    private static func inspectJSON(_ value: Any, path: String,
                                    protocolName: String, builder: inout ReportBuilder) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                inspectJSON(child, path: path.isEmpty ? key : "\(path).\(key)",
                            protocolName: protocolName, builder: &builder)
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                inspectJSON(child, path: "\(path)[\(index)]", protocolName: protocolName,
                            builder: &builder)
            }
        } else if let string = value as? String {
            analyzeText(key: path, value: string, protocolName: protocolName,
                        confidence: .declared, builder: &builder)
        } else if !(value is NSNull) {
            analyzeText(key: path, value: String(describing: value),
                        protocolName: protocolName, confidence: .declared,
                        builder: &builder)
        }
    }

    private static func inspectRawSignals(_ bytes: [UInt8], protocolName: String,
                                          builder: inout ReportBuilder) {
        for string in printableStrings(bytes, minimumLength: 6).prefix(300) {
            let lower = string.lowercased()
            guard lower.contains("trainedalgorithmic") || lower.contains("compositesynthetic") ||
                    lower.contains("compositewithtrained") || lower.contains("c2pa.") ||
                    lower.contains("creator tool") || MetadataTextClassifier.knownGenerator(in: lower) != nil else { continue }
            analyzeText(key: "embedded string", value: string, protocolName: protocolName,
                        confidence: .inferred, builder: &builder)
        }
    }

    // MARK: Binary and text helpers

    private static func readBE16(_ bytes: [UInt8], _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private static func readBE32(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 |
               UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    private static func readBE64(_ bytes: [UInt8], _ offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= bytes.count else { return nil }
        var value: UInt64 = 0
        for byte in bytes[offset..<(offset + 8)] { value = value << 8 | UInt64(byte) }
        return value
    }

    private static func readLE32(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
               UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private static func ascii(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> String {
        guard offset >= 0, offset < bytes.count else { return "" }
        return String(bytes: bytes[offset..<min(bytes.count, offset + count)], encoding: .ascii) ?? ""
    }

    private static func utf8(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    private static func printableStrings(_ bytes: [UInt8], minimumLength: Int) -> [String] {
        var result: [String] = []
        var current: [UInt8] = []
        current.reserveCapacity(128)
        func flush() {
            if current.count >= minimumLength {
                result.append(String(decoding: current, as: UTF8.self))
            }
            current.removeAll(keepingCapacity: true)
        }
        for byte in bytes {
            if byte == 9 || byte == 10 || byte == 13 || (32...126).contains(byte) {
                current.append(byte)
                if current.count >= 4096 { flush() }
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    private static func shortened(_ value: String, limit: Int = 900) -> String {
        let collapsed = value.replacingOccurrences(of: "\\s+", with: " ",
                                                   options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }
}

// MARK: - Report builder

private struct ReportBuilder {
    let format: ImageFormat
    var carriers: [String] = []
    var findings: [ProvenanceFinding] = []
    var stillPresent: [String] = []
    var limitations: [String] = []
    var coverage: ProvenanceReport.Coverage
    var sawC2PA = false

    init(format: ImageFormat) {
        self.format = format
        coverage = format == .other ? .partial : .containerComplete
    }

    mutating func addCarrier(_ carrier: String) { addUnique(carrier, to: &carriers) }
    mutating func addStillPresent(_ item: String) { addUnique(item, to: &stillPresent) }
    mutating func addLimitation(_ limitation: String) { addUnique(limitation, to: &limitations) }

    mutating func addFinding(kind: ProvenanceFindingKind, title: String, detail: String,
                             protocolName: String, confidence: ProvenanceConfidence) {
        guard !title.isEmpty else { return }
        let duplicate = findings.contains {
            $0.kind == kind && $0.title == title && $0.detail == detail &&
            $0.protocolName == protocolName
        }
        guard !duplicate else { return }
        findings.append(ProvenanceFinding(kind: kind, title: title, detail: detail,
                                          protocolName: protocolName, confidence: confidence))
    }

    var report: ProvenanceReport {
        ProvenanceReport(format: format, carriers: carriers, findings: findings,
                         stillPresent: stillPresent, limitations: limitations,
                         coverage: coverage)
    }

    private func addUnique(_ value: String, to array: inout [String]) {
        if !array.contains(value) { array.append(value) }
    }
}

// MARK: - Small CBOR decoder (RFC 8949 data model)

private indirect enum CBORValue {
    case unsigned(UInt64)
    case negative(Int64)
    case bytes(Data)
    case text(String)
    case array([CBORValue])
    case map([(CBORValue, CBORValue)])
    case tag(UInt64, CBORValue)
    case boolean(Bool)
    case null
    case floating(Double)

    var pathComponent: String {
        switch self {
        case .text(let value): return value
        case .unsigned(let value): return String(value)
        case .negative(let value): return String(value)
        default: return "key"
        }
    }
}

private enum CBORError: Error { case truncated, malformed, tooDeep }

private struct CBORDecoder {
    let bytes: [UInt8]
    var index = 0

    mutating func decode(depth: Int = 0) throws -> CBORValue {
        guard depth < 64 else { throw CBORError.tooDeep }
        guard index < bytes.count else { throw CBORError.truncated }
        let initial = bytes[index]
        index += 1
        let major = initial >> 5
        let additional = initial & 0x1F

        switch major {
        case 0: return .unsigned(try length(additional))
        case 1:
            let magnitude = try length(additional)
            guard magnitude <= UInt64(Int64.max) else { throw CBORError.malformed }
            return .negative(-1 - Int64(magnitude))
        case 2:
            if additional == 31 {
                var data = Data()
                while !isBreak {
                    guard case .bytes(let part) = try decode(depth: depth + 1) else {
                        throw CBORError.malformed
                    }
                    data.append(part)
                }
                index += 1
                return .bytes(data)
            }
            let count = try intLength(additional)
            guard index + count <= bytes.count else { throw CBORError.truncated }
            defer { index += count }
            return .bytes(Data(bytes[index..<(index + count)]))
        case 3:
            if additional == 31 {
                var text = ""
                while !isBreak {
                    guard case .text(let part) = try decode(depth: depth + 1) else {
                        throw CBORError.malformed
                    }
                    text += part
                }
                index += 1
                return .text(text)
            }
            let count = try intLength(additional)
            guard index + count <= bytes.count else { throw CBORError.truncated }
            defer { index += count }
            return .text(String(decoding: bytes[index..<(index + count)], as: UTF8.self))
        case 4:
            var values: [CBORValue] = []
            if additional == 31 {
                while !isBreak { values.append(try decode(depth: depth + 1)) }
                index += 1
            } else {
                let count = try intLength(additional)
                for _ in 0..<count {
                    values.append(try decode(depth: depth + 1))
                }
            }
            return .array(values)
        case 5:
            var pairs: [(CBORValue, CBORValue)] = []
            if additional == 31 {
                while !isBreak {
                    pairs.append((try decode(depth: depth + 1), try decode(depth: depth + 1)))
                }
                index += 1
            } else {
                let count = try intLength(additional)
                for _ in 0..<count {
                    pairs.append((try decode(depth: depth + 1), try decode(depth: depth + 1)))
                }
            }
            return .map(pairs)
        case 6:
            return .tag(try length(additional), try decode(depth: depth + 1))
        case 7:
            switch additional {
            case 20: return .boolean(false)
            case 21: return .boolean(true)
            case 22, 23: return .null
            case 25:
                let bits = UInt16(try length(additional))
                return .floating(Double(Self.half(bits)))
            case 26:
                return .floating(Double(Float(bitPattern: UInt32(try length(additional)))))
            case 27:
                return .floating(Double(bitPattern: try length(additional)))
            default: throw CBORError.malformed
            }
        default: throw CBORError.malformed
        }
    }

    private var isBreak: Bool { index < bytes.count && bytes[index] == 0xFF }

    private mutating func intLength(_ additional: UInt8) throws -> Int {
        let value = try length(additional)
        guard value <= UInt64(Int.max) else { throw CBORError.malformed }
        return Int(value)
    }

    private mutating func length(_ additional: UInt8) throws -> UInt64 {
        switch additional {
        case 0...23: return UInt64(additional)
        case 24: return try read(1)
        case 25: return try read(2)
        case 26: return try read(4)
        case 27: return try read(8)
        default: throw CBORError.malformed
        }
    }

    private mutating func read(_ count: Int) throws -> UInt64 {
        guard index + count <= bytes.count else { throw CBORError.truncated }
        var value: UInt64 = 0
        for byte in bytes[index..<(index + count)] { value = value << 8 | UInt64(byte) }
        index += count
        return value
    }

    private static func half(_ bits: UInt16) -> Float {
        let sign: Float = (bits & 0x8000) == 0 ? 1 : -1
        let exponent = Int((bits >> 10) & 0x1F)
        let fraction = Int(bits & 0x03FF)
        if exponent == 0 { return sign * Float(fraction) * pow(2, -24) }
        if exponent == 31 { return fraction == 0 ? sign * .infinity : .nan }
        return sign * Float(1024 + fraction) * pow(2, Float(exponent - 25))
    }
}
