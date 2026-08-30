import Foundation

extension CleanPreset {
    /// Whether a probe report still contains anything in this preset's scope.
    /// This is deliberately conservative: an unknown carrier is never presented
    /// as removed merely because an export returned successfully.
    func hasRemaining(in report: ProvenanceReport) -> Bool {
        guard report.hasDetectedMetadata else { return false }
        switch self {
        case .allMetadata:
            return true
        case .gps:
            return report.findings.contains { $0.kind == .location } ||
                containsAny(in: report, markers: ["gps", "location", "iso6709", "xyz"])
        case .exif:
            return containsAny(in: report, markers: ["exif", "tiff", "maker", "camera", "lens"])
        case .aiMetadata:
            if report.findings.contains(where: { finding in
                switch finding.kind {
                case .generativeAI, .generator, .prompt, .model,
                     .editHistory, .ingredient, .correlationID, .softBinding:
                    return true
                default:
                    return false
                }
            }) { return true }
            return containsAny(in: report, markers: [
                "c2pa", "content credentials", "provenance", "jumbf",
                "ai metadata", "ai provenance", "ai generated", "ai-related",
                "openai",
                "stable diffusion", "automatic1111", "comfyui", "invokeai",
                "midjourney", "firefly", "dall-e", "gpt-image", "ideogram",
                "leonardo", "flux", "trainedalgorithmicmedia", "prompt",
                "sampler", "model hash", "digital source type",
            ])
        }
    }

    /// A concise, user-readable message when the selected operation did not find
    /// anything in its requested scope.
    func noMatchMessage(for media: MediaKind) -> String {
        switch self {
        case .allMetadata:
            return "No supported metadata was found in this \(media.singularTitle)."
        case .aiMetadata:
            return "No AI-related metadata was found in this \(media.singularTitle)."
        case .exif:
            return "No EXIF camera data was found in this \(media.singularTitle)."
        case .gps:
            return "No GPS location data was found in this \(media.singularTitle)."
        }
    }

    private func containsAny(in report: ProvenanceReport, markers: [String]) -> Bool {
        let haystack = (report.carriers + report.findings.map {
            [$0.title, $0.detail, $0.protocolName].joined(separator: " ")
        }).joined(separator: " ").lowercased()
        return markers.contains { haystack.contains($0) }
    }
}
