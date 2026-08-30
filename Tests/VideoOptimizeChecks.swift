import CoreGraphics
import Foundation

private var failures = 0
private func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() { print("  PASS  \(label)") }
    else { failures += 1; print("  FAIL  \(label)") }
}

@main
struct VideoOptimizeChecks {
    static func main() throws {
        print("\nVideo optimize policy")
        var settings = VideoOptimizeSettings()
        settings.sizeMode = .targetSize
        settings.targetMegabytes = 25
        settings.audioBitrateKbps = 128
        settings.trimEndSeconds = 42
        let plan = try VideoSizeTargetPolicy.plan(sourceSize: CGSize(width: 1920, height: 1080),
            sourceFrameRate: 30, sourceDuration: 42, settings: settings)
        check(plan.targetBytes == 25_000_000, "25 MB uses a decimal file-size target")
        check(plan.videoBitrate > 4_400_000 && plan.videoBitrate < 4_600_000,
              "target budget reserves audio and container overhead")
        check(plan.width == 1920 && plan.height == 1080,
              "balanced 25 MB / 42 s keeps 1080p when bitrate is healthy")

        settings.targetMegabytes = 8
        let reduced = try VideoSizeTargetPolicy.plan(sourceSize: CGSize(width: 1920, height: 1080),
            sourceFrameRate: 30, sourceDuration: 42, settings: settings)
        check(reduced.width <= 1280 && reduced.height <= 720 && reduced.resolutionWasReducedForTarget,
              "smart mode lowers resolution before severe artifacts")

        settings.priority = .keepResolution
        let preserved = try VideoSizeTargetPolicy.plan(sourceSize: CGSize(width: 1920, height: 1080),
            sourceFrameRate: 30, sourceDuration: 42, settings: settings)
        check(preserved.width == 1920 && preserved.height == 1080,
              "Keep resolution never changes dimensions")

        settings = VideoOptimizeSettings()
        settings.cropPreset = .story
        let portrait = try VideoSizeTargetPolicy.plan(sourceSize: CGSize(width: 1920, height: 1080),
            sourceFrameRate: 30, sourceDuration: 10, settings: settings)
        check(Double(portrait.width) / Double(portrait.height) < 0.57,
              "9:16 crop produces portrait output without stretching")

        settings.trimStartSeconds = 4
        settings.trimEndSeconds = 9
        let trimmed = try VideoSizeTargetPolicy.plan(sourceSize: CGSize(width: 1280, height: 720),
            sourceFrameRate: 30, sourceDuration: 10, settings: settings)
        check(abs(trimmed.duration - 5) < 0.001, "trim duration drives bitrate and size estimates")
        check(trimmed.width % 2 == 0 && trimmed.height % 2 == 0,
              "encoder dimensions are always even")

        check(VideoTrimRangePolicy.isFullSource(start: 0, end: nil),
              "no trim markers means the complete source")
        check(VideoTrimRangePolicy.end(proposed: 10, duration: 10, start: 0) == nil,
              "an Out handle at the source boundary is stored as no marker")
        check(abs(VideoTrimRangePolicy.start(proposed: 8, duration: 10, end: 7) - 6.95) < 0.001,
              "the In handle cannot cross the Out handle")
        check(abs((VideoTrimRangePolicy.end(proposed: 2, duration: 10, start: 4) ?? 0) - 4.05) < 0.001,
              "the Out handle cannot cross the In handle")

        if failures == 0 { print("\nALL VIDEO OPTIMIZE CHECKS PASSED") }
        else { print("\n\(failures) VIDEO OPTIMIZE CHECK(S) FAILED"); exit(1) }
    }
}
