import AppKit
import Foundation

@main
@MainActor
enum TransformPreviewChecks {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fail("Usage: transform-preview-checks IMAGE")
        }
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let model = TransformModel()
        model.add(urls: [sourceURL])
        try await waitUntil("initial image conversion") {
            !model.isProcessing && model.items.first?.outputData != nil
        }
        guard let itemID = model.items.first?.id else { fail("queue item was not created") }

        model.cropAspect = .square
        model.cropFocusX = 0.2
        model.refreshOptimizePreview()
        try await waitUntil("square crop preview") {
            !model.isOptimizePreviewRendering &&
                model.optimizePreviewItemID == itemID &&
                model.optimizePreviewWidth != nil
        }
        expect(model.optimizePreviewWidth == model.optimizePreviewHeight,
               "changing crop settings updates the selected preview")

        model.resizeMode = .width
        model.resizeValue = 80
        expect(model.allowsUpscaling,
               "Image Optimize enables upscaling by default")
        model.refreshOptimizePreview()
        try await waitUntil("resize preview") {
            !model.isOptimizePreviewRendering && model.optimizePreviewWidth == 80
        }
        expect(model.optimizePreviewHeight ?? 0 > 0,
               "changing resize settings updates preview dimensions")
        expect(model.items.first?.width != 80,
               "live preview does not silently replace the queue output")

        print("Transform preview checks passed")
    }

    private static func waitUntil(_ label: String, condition: @escaping @MainActor () -> Bool)
        async throws {
        for _ in 0..<240 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        fail("timed out waiting for \(label)")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail("FAIL: \(message)") }
        print("PASS: \(message)")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }
}
