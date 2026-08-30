import Foundation

@main
struct SizeTargetChecks {
    private static var failures = 0

    static func main() throws {
        print("\nSize-target encoder")

        var calls: [Int] = []
        let noTarget = try SizeTargetEncoder.encode(
            targetBytes: nil, qualityFloor: 40, qualityCeiling: 84
        ) { quality in
            calls.append(quality)
            return Data(repeating: 0, count: quality * 10)
        }
        check(calls == [84] && noTarget.finalQuality == 84 && noTarget.iterations == 1,
              "no target encodes once at the ceiling", detail: "calls=\(calls)")

        calls = []
        let reachable = try SizeTargetEncoder.encode(
            targetBytes: 730, qualityFloor: 40, qualityCeiling: 90
        ) { quality in
            calls.append(quality)
            return Data(repeating: 0, count: quality * 10)
        }
        check(reachable.targetMet && reachable.finalQuality == 73 && reachable.data.count == 730,
              "reachable target chooses the highest tested quality at or under target",
              detail: "q\(reachable.finalQuality), \(reachable.data.count) bytes")

        calls = []
        let unreachable = try SizeTargetEncoder.encode(
            targetBytes: 350, qualityFloor: 40, qualityCeiling: 90
        ) { quality in
            calls.append(quality)
            return Data(repeating: 0, count: quality * 10)
        }
        check(!unreachable.targetMet && unreachable.finalQuality >= 40 && calls.allSatisfy { $0 >= 40 },
              "unreachable target never drops below the quality floor",
              detail: "q\(unreachable.finalQuality), calls=\(calls)")
        check(unreachable.statusText?.contains("without dropping below quality 40") == true,
              "quality-floor conflict is explained", detail: unreachable.statusText ?? "nil")

        calls = []
        let insensitiveMet = try SizeTargetEncoder.encode(
            targetBytes: 900, qualityFloor: 20, qualityCeiling: 88,
            qualityAffectsSize: false
        ) { quality in
            calls.append(quality)
            return Data(repeating: 0, count: 800)
        }
        check(calls == [88] && insensitiveMet.targetMet && insensitiveMet.iterations == 1,
              "size-insensitive format encodes once and reports a met target")

        calls = []
        let insensitiveMiss = try SizeTargetEncoder.encode(
            targetBytes: 700, qualityFloor: 20, qualityCeiling: 88,
            qualityAffectsSize: false
        ) { quality in
            calls.append(quality)
            return Data(repeating: 0, count: 800)
        }
        check(calls == [88] && !insensitiveMiss.targetMet && insensitiveMiss.iterations == 1,
              "size-insensitive format encodes once and reports a missed target")

        calls = []
        _ = try SizeTargetEncoder.encode(
            targetBytes: 500, qualityFloor: 0, qualityCeiling: 100
        ) { quality in
            calls.append(quality)
            return Data(repeating: 0, count: quality * 100 + 1_000)
        }
        check(calls.count <= 8, "search never exceeds eight encoder calls",
              detail: "calls=\(calls.count)")

        if failures == 0 {
            print("\nALL SIZE-TARGET CHECKS PASSED")
        } else {
            print("\n\(failures) SIZE-TARGET CHECK(S) FAILED")
            exit(1)
        }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ name: String,
                              detail: String? = nil) {
        if condition() {
            print("  PASS  \(name)\(detail.map { "  -- \($0)" } ?? "")")
        } else {
            failures += 1
            print("  FAIL  \(name)\(detail.map { "  -- \($0)" } ?? "")")
        }
    }
}
