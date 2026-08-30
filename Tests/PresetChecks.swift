// Compiled and run by tools/check.sh against Sources/DashboardPreset.swift.
//
// `@main` + -parse-as-library rather than top-level code in a main.swift, so this can
// live beside the Python verifier instead of needing a directory of its own.
//
// Scope is deliberately narrow: the pure geometry. Whether an NSWindow actually lands on
// the right rect cannot be asserted headlessly — a GUI app has to be launched for that —
// so what is testable is tested here and the rest is a manual GUI check before release.

import Foundation

@main
enum PresetChecks {

    private static var failures = 0

    private static func check(_ label: String, _ condition: Bool, _ detail: String = "") {
        let mark = condition ? "  PASS" : "  FAIL"
        print(mark, label, detail.isEmpty ? "" : " -- \(detail)")
        if !condition { failures += 1 }
    }

    static func main() {
        let all = DashboardPreset.allCases

        print("\nDashboard presets")
        check("five presets", all.count == 5, all.map(\.controlTitle).joined(separator: ", "))

        for preset in all {
            // A preset that cannot recognise itself leaves the control stuck on
            // "Custom size" immediately after the user clicks it.
            check("\(preset.controlTitle) round-trips",
                  DashboardPreset.matching(contentSize: preset.contentSize) == preset,
                  preset.sizeTitle)

            // Retina rounding lands half a point off; that must still match.
            let jittered = CGSize(width: preset.contentSize.width + 0.5,
                                  height: preset.contentSize.height - 0.5)
            check("\(preset.controlTitle) tolerates ±0.5pt",
                  DashboardPreset.matching(contentSize: jittered) == preset)

            // A real vertical drag must not be mistaken for a preset.
            let dragged = CGSize(width: preset.contentSize.width,
                                 height: preset.contentSize.height + 10)
            check("\(preset.controlTitle) height + 10pt reads as Custom",
                  DashboardPreset.matching(contentSize: dragged) == nil)

            // Below ContentView's own floor, applying a preset would be a no-op.
            let floor = DashboardMetrics.minimumContentSize
            check("\(preset.controlTitle) ≥ window minimum",
                  preset.contentSize.width >= floor.width
                  && preset.contentSize.height >= floor.height)
        }

        check("all presets use the fixed dashboard width",
              all.allSatisfy { $0.contentSize.width == DashboardMetrics.fixedContentWidth },
              "\(Int(DashboardMetrics.fixedContentWidth))pt")

        // The tiles draw a MacBook scaled by diagonal, while only height grows.
        for (smaller, larger) in zip(all, all.dropFirst()) {
            check("\(smaller.controlTitle) < \(larger.controlTitle)",
                  larger.contentSize.width == smaller.contentSize.width
                  && larger.contentSize.height > smaller.contentSize.height
                  && larger.diagonal > smaller.diagonal,
                  "\(smaller.sizeTitle) → \(larger.sizeTitle)")
        }

        check("only the M1 Air has no notch", all.filter { !$0.hasNotch } == [.air13M1])

        // Unversioned, and a future layout change silently inherits a stale rect.
        check("frame preference key is versioned",
              DashboardMetrics.framePreferenceKey.hasSuffix(".v2"),
              DashboardMetrics.framePreferenceKey)

        print(failures == 0 ? "\nALL PRESET CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
