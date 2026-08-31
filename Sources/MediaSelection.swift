import AppKit
import Foundation

/// The shared selection contract used by every media queue.
///
/// A plain click selects one item, Command-click toggles one item, and
/// Shift-click selects the range between the previous anchor and the clicked
/// item. The caller keeps the clicked item as the preview/inspector primary.
struct MediaSelectionResult: Equatable {
    let ids: Set<UUID>
    let anchorID: UUID?
}

enum MediaSelection {
    static func update(current: Set<UUID>, anchorID: UUID?, tappedID: UUID,
                       orderedIDs: [UUID], modifiers: NSEvent.ModifierFlags)
        -> MediaSelectionResult {
        let command = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)

        if shift,
           let anchorID,
           let anchorIndex = orderedIDs.firstIndex(of: anchorID),
           let tappedIndex = orderedIDs.firstIndex(of: tappedID) {
            let lower = min(anchorIndex, tappedIndex)
            let upper = max(anchorIndex, tappedIndex)
            let range = Set(orderedIDs[lower...upper])
            return MediaSelectionResult(
                ids: command ? current.union(range) : range,
                anchorID: anchorID)
        }

        if command {
            var ids = current
            if ids.contains(tappedID) {
                ids.remove(tappedID)
            } else {
                ids.insert(tappedID)
            }
            return MediaSelectionResult(ids: ids, anchorID: tappedID)
        }

        return MediaSelectionResult(ids: [tappedID], anchorID: tappedID)
    }

    static func primaryID(for ids: Set<UUID>, preferredID: UUID?, orderedIDs: [UUID]) -> UUID? {
        if let preferredID, ids.contains(preferredID) { return preferredID }
        return orderedIDs.first(where: ids.contains)
    }
}
