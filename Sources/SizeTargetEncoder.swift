import Foundation

struct SizeTargetResult {
    let data: Data
    let finalQuality: Int
    let targetBytes: Int?
    let targetMet: Bool
    let iterations: Int

    var statusText: String? {
        guard let targetBytes, !targetMet else { return nil }
        return "Could not reach \(formatBytes(targetBytes)) without dropping below quality \(finalQuality); closest was \(formatBytes(data.count)) at q\(finalQuality)."
    }

    private func formatBytes(_ count: Int) -> String {
        if count < 1024 { return "\(count) B" }
        if count < 1024 * 1024 {
            return String(format: "%.1f KB", Double(count) / 1024)
        }
        return String(format: "%.2f MB", Double(count) / 1024 / 1024)
    }
}

/// Bounded quality search shared by WebP and ImageIO encoders.
///
/// The quality floor is a hard constraint. A size target can fail; the encoder reports
/// that conflict rather than silently lowering quality or pretending the target was met.
enum SizeTargetEncoder {
    static func encode(targetBytes: Int?, qualityFloor: Int, qualityCeiling: Int,
                       qualityAffectsSize: Bool = true,
                       encoder: (Int) throws -> Data) throws -> SizeTargetResult {
        let floor = max(0, min(100, min(qualityFloor, qualityCeiling)))
        let ceiling = max(floor, min(100, max(qualityFloor, qualityCeiling)))

        guard let targetBytes, targetBytes > 0, qualityAffectsSize else {
            let data = try encoder(ceiling)
            return SizeTargetResult(data: data, finalQuality: ceiling,
                                    targetBytes: targetBytes,
                                    targetMet: targetBytes.map { data.count <= $0 } ?? true,
                                    iterations: 1)
        }

        var low = floor
        var high = ceiling
        var iterations = 0
        var bestUnder: (data: Data, quality: Int)?
        var smallestOver: (data: Data, quality: Int)?

        while low <= high, iterations < 8 {
            let quality = low + (high - low) / 2
            let data = try encoder(quality)
            iterations += 1

            if data.count <= targetBytes {
                if bestUnder == nil || quality > bestUnder!.quality {
                    bestUnder = (data, quality)
                }
                low = quality + 1
            } else {
                if smallestOver == nil || data.count < smallestOver!.data.count {
                    smallestOver = (data, quality)
                }
                high = quality - 1
            }
        }

        if let bestUnder {
            return SizeTargetResult(data: bestUnder.data, finalQuality: bestUnder.quality,
                                    targetBytes: targetBytes, targetMet: true,
                                    iterations: iterations)
        }

        // Binary search reaches the floor for monotonic encoders, but unusual content
        // can make output size non-monotonic. Explicitly test it before reporting the
        // nearest result so the quality-floor promise is still exact.
        if smallestOver?.quality != floor, iterations < 8 {
            let data = try encoder(floor)
            iterations += 1
            if data.count <= targetBytes {
                return SizeTargetResult(data: data, finalQuality: floor,
                                        targetBytes: targetBytes, targetMet: true,
                                        iterations: iterations)
            }
            if smallestOver == nil || data.count < smallestOver!.data.count {
                smallestOver = (data, floor)
            }
        }

        let fallback: (data: Data, quality: Int)
        if let smallestOver {
            fallback = smallestOver
        } else {
            fallback = (try encoder(floor), floor)
            iterations += 1
        }
        return SizeTargetResult(data: fallback.data, finalQuality: fallback.quality,
                                targetBytes: targetBytes, targetMet: false,
                                iterations: iterations)
    }
}
