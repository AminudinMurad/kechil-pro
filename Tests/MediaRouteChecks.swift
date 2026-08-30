import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() {
        print("  PASS  \(label)")
    } else {
        failures += 1
        print("  FAIL  \(label)")
    }
}

@main
struct MediaRouteChecks {
    static func main() {
        print("\nMedia routes")
        check(ToolRoute.all.count == 6, "exactly six tool/media routes")
        check(Set(ToolRoute.all.map(\.id)).count == 6, "route identifiers are unique")
        check(Set(ToolRoute.all.map(\.tool)) == Set(KechilTool.allCases),
              "every primary tool is represented")
        for tool in KechilTool.allCases {
            let modes = Set(ToolRoute.all.filter { $0.tool == tool }.map(\.media))
            check(modes == Set(MediaKind.allCases), "\(tool.title) has separate Images and Videos routes")
        }
        check(ToolRoute.cleanImages != ToolRoute.cleanVideos,
              "image and video queues cannot share a route key")
        check(ToolRoute.optimizeVideos.media.addLabel == "Add Videos…",
              "video route uses a media-specific Add label")
        check(ToolRoute.watermarkImages.media.chooseLabel == "Choose Images…",
              "image route uses a media-specific Choose label")

        if failures == 0 {
            print("\nALL MEDIA ROUTE CHECKS PASSED")
        } else {
            print("\n\(failures) MEDIA ROUTE CHECK(S) FAILED")
            exit(1)
        }
    }
}
