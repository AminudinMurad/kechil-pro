import AppKit
import Foundation

@main
enum MediaSelectionChecks {
    static func main() {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        let ids = (0..<5).map { _ in UUID() }
        let order = ids

        let first = MediaSelection.update(current: [], anchorID: nil,
                                          tappedID: ids[1], orderedIDs: order,
                                          modifiers: [])
        expect(first.ids == [ids[1]], "plain click selects exactly one item")
        expect(first.anchorID == ids[1], "plain click establishes the range anchor")

        let commandAdd = MediaSelection.update(current: first.ids, anchorID: first.anchorID,
                                                tappedID: ids[3], orderedIDs: order,
                                                modifiers: [.command])
        expect(commandAdd.ids == [ids[1], ids[3]], "Command-click adds a second item")

        let commandRemove = MediaSelection.update(current: commandAdd.ids,
                                                  anchorID: commandAdd.anchorID,
                                                  tappedID: ids[1], orderedIDs: order,
                                                  modifiers: [.command])
        expect(commandRemove.ids == [ids[3]], "Command-click toggles an existing item off")

        let range = MediaSelection.update(current: commandRemove.ids,
                                          anchorID: commandRemove.anchorID,
                                          tappedID: ids[0], orderedIDs: order,
                                          modifiers: [.shift])
        expect(range.ids == [ids[0], ids[1]],
               "Shift-click selects the contiguous range from the anchor")
        expect(range.anchorID == ids[1], "Shift-click keeps the previous anchor")

        let additiveRange = MediaSelection.update(current: range.ids,
                                                  anchorID: range.anchorID,
                                                  tappedID: ids[4], orderedIDs: order,
                                                  modifiers: [.command, .shift])
        expect(additiveRange.ids == Set(ids),
               "Command-Shift-click adds a range without clearing the existing selection")

        expect(MediaSelection.primaryID(for: additiveRange.ids, preferredID: ids[4],
                                        orderedIDs: order) == ids[4],
               "the last clicked item remains the preview primary")
        expect(MediaSelection.primaryID(for: [ids[0], ids[2]], preferredID: ids[4],
                                        orderedIDs: order) == ids[0],
               "the primary falls back to the first remaining item after a toggle")

        print("MEDIA SELECTION CHECKS PASSED (\(checks) assertions)")
    }
}
