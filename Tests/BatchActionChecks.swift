import Foundation

@main
enum BatchActionChecks {
    static func main() {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        for (count, busy, enabled) in [(0, false, false), (1, false, true),
                                       (3, false, true), (3, true, false),
                                       (0, true, false), (-1, false, false)] {
            let state = BatchSaveState(readyCount: count, isProcessing: busy)
            expect(state.canSave == enabled, "Save availability must use ready outputs and busy state")
            var invoked = 0
            state.saveIfReady { invoked += 1 }
            expect(invoked == (enabled ? 1 : 0), "Unavailable Save must not dispatch a callback")
        }
        expect(BatchSaveState(readyCount: 3, isProcessing: false).help.contains("all 3 ready files"),
               "Save help must explain whole-batch scope")
        expect(BatchSaveState(readyCount: 1, isProcessing: true).help.contains("Wait"),
               "Processing must explain why Save is unavailable")

        for (ready, matches, busy, enabled, title) in [
            (3, 2, false, true, "Clean All"),
            (3, 0, false, true, "Prepare Copies"),
            (0, 0, false, false, "Clean All"),
            (3, 2, true, false, "Clean All"),
            (3, 0, true, false, "Prepare Copies"),
        ] {
            let state = CleanBatchActionState(readyCount: ready, plannedChangeCount: matches,
                                              isProcessing: busy)
            expect(state.canClean == enabled, "Clean waits for inspected files and an idle batch")
            expect(state.title == title, "No-match batches must not claim metadata was cleaned")
            var invoked = 0
            state.cleanIfReady { invoked += 1 }
            expect(invoked == (enabled ? 1 : 0), "Clean callback fires only for eligible batches")
        }
        print("ALL BATCH ACTION CHECKS PASSED (\(checks) assertions)")
    }
}
