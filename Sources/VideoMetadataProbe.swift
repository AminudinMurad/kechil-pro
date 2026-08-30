import AVFoundation
import Foundation

/// A bounded, copyable piece of readable metadata evidence. Binary payloads and
/// signatures are never surfaced verbatim; only short printable excerpts that
/// help a person understand why a finding was reported are retained.
struct VideoMetadataEvidence: Identifiable, Hashable, Sendable {
    let id: UUID
    let label: String
    let value: String
    let source: String

    init(id: UUID = UUID(), label: String, value: String, source: String) {
        self.id = id
        self.label = label
        self.value = value
        self.source = source
    }
}

struct VideoMetadataFinding: Identifiable, Hashable, Sendable {
    enum Scope: Hashable, Sendable {
        case file
        case track(Int)
        case timedTrack(Int)

        var label: String {
            switch self {
            case .file: return "File"
            case .track(let index): return "Track \(index)"
            case .timedTrack(let index): return "Timed track \(index)"
            }
        }
    }

    enum Category: String, CaseIterable, Hashable, Sendable {
        case location
        case descriptive
        case device
        case timestamp
        case artwork
        case timed
        case provenance
        case technical
        case unknown

        var title: String {
            switch self {
            case .location: return "Location"
            case .descriptive: return "Title and description"
            case .device: return "Device and software"
            case .timestamp: return "Dates and timestamps"
            case .artwork: return "Artwork"
            case .timed: return "Timed metadata"
            case .provenance: return "Content credentials"
            case .technical: return "Technical"
            case .unknown: return "Other metadata"
            }
        }
    }

    let id: UUID
    let scope: Scope
    let category: Category
    let identifier: String
    let displayName: String
    let valueSummary: String
    let evidence: [VideoMetadataEvidence]
    let removable: Bool

    init(id: UUID = UUID(), scope: Scope, category: Category, identifier: String,
         displayName: String, valueSummary: String,
         evidence: [VideoMetadataEvidence] = [], removable: Bool) {
        self.id = id
        self.scope = scope
        self.category = category
        self.identifier = identifier
        self.displayName = displayName
        self.valueSummary = valueSummary
        self.evidence = evidence
        self.removable = removable
    }
}

struct VideoMetadataReport: Sendable {
    let findings: [VideoMetadataFinding]
    let inspectedFormats: [String]
    let hasTimedMetadata: Bool
    let containerScanWasBounded: Bool

    var removableFindings: [VideoMetadataFinding] { findings.filter(\.removable) }
}

enum VideoMetadataProbe {
    static func inspect(url: URL) async throws -> VideoMetadataReport {
        let asset = AVURLAsset(url: url)
        let formats = try await asset.load(.availableMetadataFormats)
        var findings: [VideoMetadataFinding] = []

        for format in formats {
            let items = try await asset.loadMetadata(for: format)
            for item in items {
                if let finding = await finding(from: item, scope: .file,
                                               fallbackIdentifier: format.rawValue) {
                    findings.append(finding)
                }
            }
        }

        let tracks = try await asset.load(.tracks)
        var timedIndex = 0
        for (index, track) in tracks.enumerated() {
            let mediaType = track.mediaType
            let scope: VideoMetadataFinding.Scope
            if mediaType == .metadata || mediaType == .text || mediaType == .subtitle {
                timedIndex += 1
                scope = .timedTrack(timedIndex)
                findings.append(VideoMetadataFinding(scope: scope, category: .timed,
                    identifier: mediaType.rawValue, displayName: "Timed metadata track",
                    valueSummary: "A timed \(mediaType.rawValue) track is present", removable: true))
            } else {
                scope = .track(index + 1)
            }
            let metadata = try await track.load(.metadata)
            for item in metadata {
                if let finding = await finding(from: item, scope: scope,
                                               fallbackIdentifier: mediaType.rawValue) {
                    findings.append(finding)
                }
            }
        }

        findings.append(contentsOf: try boundedContainerFindings(url: url))
        findings = deduplicated(findings)
        return VideoMetadataReport(findings: findings,
                                   inspectedFormats: formats.map(\.rawValue),
                                   hasTimedMetadata: timedIndex > 0,
                                   containerScanWasBounded: true)
    }

    private static func finding(from item: AVMetadataItem, scope: VideoMetadataFinding.Scope,
                                fallbackIdentifier: String) async -> VideoMetadataFinding? {
        let keyDescription: String
        if let key = item.key { keyDescription = String(describing: key) }
        else { keyDescription = fallbackIdentifier }
        let identifier = item.identifier?.rawValue ?? keyDescription
        let commonKey = item.commonKey?.rawValue ?? ""
        let combined = "\(identifier) \(commonKey)".lowercased()
        guard let summary = await valueSummary(for: item), !summary.isEmpty else { return nil }
        let category = category(for: combined)
        let evidence = await evidence(for: item, identifier: identifier,
                                      commonKey: commonKey, scope: scope,
                                      summary: summary)
        return VideoMetadataFinding(scope: scope, category: category,
                                    identifier: identifier,
                                    displayName: displayName(for: commonKey, identifier: identifier),
                                    valueSummary: summary,
                                    evidence: evidence,
                                    removable: category != VideoMetadataFinding.Category.technical)
    }

    private static func category(for identifier: String) -> VideoMetadataFinding.Category {
        if identifier.contains("location") || identifier.contains("iso6709") ||
            identifier.contains("gps") || identifier.contains("xyz") { return .location }
        if identifier.contains("creation") || identifier.contains("date") ||
            identifier.contains("time") { return .timestamp }
        if identifier.contains("make") || identifier.contains("model") ||
            identifier.contains("software") || identifier.contains("encoder") ||
            identifier.contains("device") { return .device }
        if identifier.contains("artwork") || identifier.contains("cover") ||
            identifier.contains("thumbnail") { return .artwork }
        if identifier.contains("c2pa") || identifier.contains("provenance") ||
            identifier.contains("credential") || identifier.contains("uuid") { return .provenance }
        if identifier.contains("format") || identifier.contains("codec") ||
            identifier.contains("bitrate") { return .technical }
        if identifier.contains("title") || identifier.contains("author") ||
            identifier.contains("description") || identifier.contains("comment") ||
            identifier.contains("copyright") || identifier.contains("keyword") { return .descriptive }
        return .unknown
    }

    private static func displayName(for commonKey: String, identifier: String) -> String {
        if !commonKey.isEmpty {
            return commonKey.replacingOccurrences(of: "_", with: " ").capitalized
        }
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func valueSummary(for item: AVMetadataItem) async -> String? {
        if let _ = try? await item.load(.dataValue) {
            return "Embedded binary data"
        }
        if let string = try? await item.load(.stringValue) {
            let collapsed = string.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !collapsed.isEmpty else { return nil }
            return collapsed.count > 96 ? String(collapsed.prefix(93)) + "…" : collapsed
        }
        if let number = try? await item.load(.numberValue) {
            return number.stringValue
        }
        if let date = try? await item.load(.dateValue) {
            return date.formatted(date: .abbreviated, time: .standard)
        }
        return nil
    }

    /// Extracts only human-readable, bounded evidence. The AVFoundation item can
    /// contain a credential signature or compressed binary blob; those are reduced
    /// to a safe printable excerpt only when it includes a useful provenance marker.
    private static func evidence(for item: AVMetadataItem,
                                 identifier: String,
                                 commonKey: String,
                                 scope: VideoMetadataFinding.Scope,
                                 summary: String) async -> [VideoMetadataEvidence] {
        var output: [VideoMetadataEvidence] = []
        if !identifier.isEmpty {
            output.append(VideoMetadataEvidence(label: "Identifier", value: identifier,
                                                source: scope.label))
        }
        if !commonKey.isEmpty, commonKey != identifier {
            output.append(VideoMetadataEvidence(label: "Common key", value: commonKey,
                                                source: scope.label))
        }

        if let string = try? await item.load(.stringValue) {
            let cleaned = readableExcerpt(string)
            if !cleaned.isEmpty, cleaned != summary {
                output.append(VideoMetadataEvidence(label: "Value", value: cleaned,
                                                    source: "metadata value"))
            }
        }
        if let data = try? await item.load(.dataValue),
           let excerpt = readablePayloadExcerpt(data) {
            output.append(VideoMetadataEvidence(label: "Readable payload", value: excerpt,
                                                source: "embedded metadata"))
        }
        return output
    }

    private static let evidenceMarkers = [
        "openai", "sora", "genid", "generative", "ai ", "c2pa", "jumbf",
        "content credential", "provenance", "digital source", "claim_generator",
        "softwareagent", "xmp", "gps", "location",
    ]

    private static func readablePayloadExcerpt(_ data: Data) -> String? {
        let bytes = data.prefix(4096).map { byte -> UInt8 in
            (byte == 9 || byte == 10 || byte == 13 || (byte >= 32 && byte < 127)) ? byte : 32
        }
        let text = String(decoding: bytes, as: UTF8.self)
        let cleaned = readableExcerpt(text)
        guard !cleaned.isEmpty else { return nil }
        let lower = cleaned.lowercased()
        guard evidenceMarkers.contains(where: lower.contains) else { return nil }
        return cleaned
    }

    private static func readableExcerpt(_ text: String) -> String {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "" }
        return collapsed.count > 360 ? String(collapsed.prefix(357)) + "…" : collapsed
    }

    /// A bounded prefix/suffix scan catches private/provenance box names without ever
    /// loading a multi-gigabyte movie into memory. It deliberately reports a carrier,
    /// not a cryptographic validation result.
    private static func boundedContainerFindings(url: URL) throws -> [VideoMetadataFinding] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        var sample = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
        if size > 5 * 1024 * 1024 {
            try handle.seek(toOffset: size - 1024 * 1024)
            sample.append(try handle.read(upToCount: 1024 * 1024) ?? Data())
        }
        let haystack = String(decoding: sample, as: UTF8.self).lowercased()
        let carriers: [(String, String, VideoMetadataFinding.Category)] = [
            ("c2pa", "C2PA content-credential carrier", .provenance),
            ("com.apple.quicktime.location", "QuickTime location carrier", .location),
            ("©xyz", "QuickTime ISO 6709 location carrier", .location),
            ("com.apple.quicktime.make", "Camera make carrier", .device),
            ("com.apple.quicktime.model", "Camera model carrier", .device),
            ("com.apple.quicktime.software", "Software carrier", .device),
        ]
        return carriers.compactMap { marker, name, category in
            guard haystack.contains(marker) else { return nil }
            return VideoMetadataFinding(scope: .file, category: category,
                                        identifier: marker, displayName: name,
                                        valueSummary: "Carrier detected in the movie container",
                                        evidence: [VideoMetadataEvidence(
                                            label: "Carrier", value: marker,
                                            source: "bounded container scan")],
                                        removable: true)
        }
    }

    private static func deduplicated(_ findings: [VideoMetadataFinding]) -> [VideoMetadataFinding] {
        var seen = Set<String>()
        return findings.filter {
            let key = "\($0.scope.label)|\($0.identifier)|\($0.valueSummary)"
            return seen.insert(key).inserted
        }
    }
}

extension CleanPreset {
    /// Whether a video metadata finding is inside this preset's scope. Technical
    /// codec/bitrate fields are never selected by these privacy presets.
    func matchesVideo(_ finding: VideoMetadataFinding) -> Bool {
        guard finding.removable else { return false }
        switch self {
        case .allMetadata:
            return true
        case .gps:
            return finding.category == .location || containsAny(
                [finding.identifier, finding.displayName, finding.valueSummary],
                markers: ["gps", "location", "iso6709", "xyz"])
        case .exif:
            return finding.category == .device || containsAny(
                [finding.identifier, finding.displayName, finding.valueSummary],
                markers: ["make", "model", "software", "device", "camera", "lens", "capture"])
        case .aiMetadata:
            return finding.category == .provenance || containsAny(
                [finding.identifier, finding.displayName, finding.valueSummary],
                markers: ["c2pa", "content credential", "provenance", "jumbf",
                          "ai metadata", "ai provenance", "ai generated", "ai-related", "openai",
                          "stable diffusion", "automatic1111", "comfyui", "invokeai",
                          "midjourney", "firefly", "dall-e", "gpt-image", "prompt",
                          "model hash", "trainedalgorithmicmedia"])
        }
    }

    private func containsAny(_ values: [String], markers: [String]) -> Bool {
        let haystack = values.joined(separator: " ").lowercased()
        return markers.contains { haystack.contains($0) }
    }
}
