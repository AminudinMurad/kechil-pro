import Foundation

@main
enum CleanWorkflowChecks {
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("kechil-clean-workflow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = folder.appendingPathComponent("source.bin")
        try Data([1, 2, 3, 4]).write(to: source)
        let identity = try CleanSourceIdentity.capture(at: source)
        check(identity.stillMatches(source), "fresh source identity matches")

        let plan = CleanPlanSummary(sourceIdentity: identity,
                                    selectionRevision: 3,
                                    selectionTitle: "GPS",
                                    detectedEntryCount: 4,
                                    selectedEntryCount: 1,
                                    unsupportedReasons: [], warnings: [])
        check(plan.hasRequestedChanges && plan.isExecutable,
              "cached plan reports an executable selected change")

        try Data([1, 2, 3, 4, 5]).write(to: source)
        check(!identity.stillMatches(source), "size change invalidates inspected identity")

        check(CleanReceiptOutcome.verified.isOrdinarySaveAllowed,
              "verified receipt permits ordinary save")
        check(CleanReceiptOutcome.unchanged.isOrdinarySaveAllowed,
              "unchanged receipt permits deliberate copy save")
        check(!CleanReceiptOutcome.partial.isOrdinarySaveAllowed,
              "partial receipt blocks ordinary verified save")
        check(MediaJobStage.ready.cleanLabel == "Ready for review",
              "Clean lifecycle uses review wording")
        check(MediaJobStage.completed.cleanLabel == "Ready to save",
              "Clean lifecycle exposes ready-to-save state")

        let detached = Task.detached { () -> Bool in
            while !Task.isCancelled { await Task.yield() }
            return Task.isCancelled
        }
        let waiter = Task {
            await CleanCancellation.value(of: detached)
        }
        waiter.cancel()
        let detachedObservedCancellation = await waiter.value
        check(detachedObservedCancellation,
              "workflow cancellation propagates into detached file work")

        print("ALL CLEAN WORKFLOW CHECKS PASSED (8 assertions)")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
