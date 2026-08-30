import Foundation
import AppKit
import SwiftUI
import ImageIO

/// One image queued in the app.
struct ScrubItem: Identifiable {
    let id: UUID
    let sourceURL: URL

    var originalSize: Int
    var cleanedSize: Int?
    var cleanedData: Data?
    var removed: [String] = []
    var format: ImageFormat = .other
    var lossless: Bool = true
    var provenance: ProvenanceReport = .empty(format: .other)
    var outputProvenance: ProvenanceReport?
    var errorText: String?
    var thumbnail: NSImage?
    var savedTo: URL?
    var preset: CleanPreset

    init(id: UUID = UUID(), sourceURL: URL, originalSize: Int,
         preset: CleanPreset = .allMetadata) {
        self.id = id
        self.sourceURL = sourceURL
        self.originalSize = originalSize
        self.cleanedSize = nil
        self.cleanedData = nil
        self.removed = []
        self.format = .other
        self.lossless = true
        self.provenance = .empty(format: .other)
        self.outputProvenance = nil
        self.errorText = nil
        self.thumbnail = nil
        self.savedTo = nil
        self.preset = preset
    }

    var displayName: String { sourceURL.lastPathComponent }

    var bytesRemoved: Int {
        guard let cleanedSize else { return 0 }
        return max(0, originalSize - cleanedSize)
    }

    var isClean: Bool {
        errorText == nil && !preset.hasRemaining(in: outputProvenance ?? provenance)
    }

    enum VerificationState {
        case clean
        case remaining
        case partial
    }

    var verificationState: VerificationState {
        guard let outputProvenance else { return .partial }
        if preset.hasRemaining(in: outputProvenance) { return .remaining }
        return outputProvenance.coverage == .containerComplete ? .clean : .partial
    }

    /// "photo.jpg" -> "photo-clean.jpg"
    var suggestedFilename: String {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        return ext.isEmpty ? "\(base)-clean" : "\(base)-clean.\(ext)"
    }
}

@MainActor
final class ScrubModel: ObservableObject {
    @Published var items: [ScrubItem] = []
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published private(set) var preset: CleanPreset = .allMetadata

    /// Row the inspector is describing.
    @Published var selectedItemID: UUID?

    /// Category the list is narrowed to. `nil` means all.
    ///
    /// Scopes the list only — the tiles and chart always describe the whole queue, so
    /// filtering can never make the summary understate what was found.
    @Published var activeFilter: MetadataCategory?

    private let acceptedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "webp", "heic", "heif",
        "tif", "tiff", "gif", "bmp", "avif", "dng",
    ]

    var totalBytesRemoved: Int { items.reduce(0) { $0 + $1.bytesRemoved } }
    var cleanedCount: Int { items.filter { $0.cleanedData != nil }.count }
    var hadMetadataCount: Int {
        items.filter { !$0.removed.isEmpty || $0.provenance.hasDetectedMetadata }.count
    }

    // MARK: Dashboard aggregates

    /// Number of *files* carrying each category — not occurrences. A photo with three
    /// maker-note segments counts once, because the user cares how many of their images
    /// are affected, not how many segments were in them.
    var categoryCounts: [MetadataCategory: Int] {
        var counts: [MetadataCategory: Int] = [:]
        for item in items {
            for category in item.categories {
                counts[category, default: 0] += 1
            }
        }
        return counts
    }

    func count(of category: MetadataCategory) -> Int { categoryCounts[category] ?? 0 }

    /// Categories actually present in this queue, in fixed display order.
    var presentCategories: [MetadataCategory] {
        categoryCounts.keys.sorted { $0.sortRank < $1.sortRank }
    }

    var locationLeakCount: Int { count(of: .gps) }
    var aiGeneratedCount: Int { items.filter { $0.provenance.hasGenerativeAI }.count }
    var reencodedCount: Int { items.filter { $0.cleanedData != nil && !$0.lossless }.count }
    var losslessCount: Int { items.filter { $0.cleanedData != nil && $0.lossless }.count }
    var cleanCount: Int { items.filter(\.isClean).count }

    /// The list's contents under the active filter.
    var visibleItems: [ScrubItem] {
        guard let activeFilter else { return items }
        return items.filter { $0.categories.contains(activeFilter) }
    }

    var selectedItem: ScrubItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    /// Changes the cleanup scope and re-renders the current queue from the original
    /// files. The picker is disabled while work is active so no item can mix scopes.
    func selectPreset(_ newPreset: CleanPreset) {
        guard newPreset != preset else { return }
        guard !isProcessing else {
            statusMessage = "Finish the current cleanup before changing the preset."
            return
        }
        preset = newPreset
        guard !items.isEmpty else { return }

        let work = items.map { ($0.id, $0.sourceURL) }
        isProcessing = true
        statusMessage = "Applying \(newPreset.title.lowercased())…"
        Task {
            for (id, url) in work {
                let refreshed = await Self.process(url: url, id: id, preset: newPreset)
                if let index = self.items.firstIndex(where: { $0.id == id }) {
                    self.items[index] = refreshed
                }
            }
            self.isProcessing = false
            self.statusMessage = "Applied \(newPreset.title.lowercased()) to \(work.count) image\(work.count == 1 ? "" : "s")."
        }
    }

    // MARK: Intake

    func add(urls: [URL]) {
        let expanded = expand(urls: urls)
        guard !expanded.isEmpty else {
            statusMessage = "No supported images found."
            return
        }
        isProcessing = true
        statusMessage = nil

        Task {
            for url in expanded {
                let item = await Self.process(url: url, preset: self.preset)
                self.items.append(item)
            }
            self.isProcessing = false
            // Leaving the inspector blank after a batch lands is just a dead panel.
            if self.selectedItemID == nil { self.selectedItemID = self.items.first?.id }
        }
    }

    /// Accepts dropped folders by walking them one level deep on down.
    private func expand(urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let e = fm.enumerator(at: url,
                                      includingPropertiesForKeys: [.isRegularFileKey],
                                      options: [.skipsHiddenFiles])
                while let child = e?.nextObject() as? URL {
                    if acceptedExtensions.contains(child.pathExtension.lowercased()) {
                        result.append(child)
                    }
                }
            } else if acceptedExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result
    }

    // MARK: Work

    /// Runs off the main actor: file IO and byte scanning should not block the UI.
    private static func process(url: URL, id: UUID = UUID(),
                                preset: CleanPreset = .allMetadata) async -> ScrubItem {
        await Task.detached(priority: .userInitiated) { () -> ScrubItem in
            do {
                // Read once. The previous path read the whole file for its size and then
                // read it again inside `strip(fileAt:)`, which doubled IO and peak memory.
                let original = try Data(contentsOf: url)
                var item = ScrubItem(id: id, sourceURL: url, originalSize: original.count,
                                     preset: preset)
                item.provenance = ProvenanceProbe.inspect(original)

                let result = try MetadataStripper.strip(original, preset: preset)
                item.cleanedData = result.data
                item.cleanedSize = result.data.count
                item.removed = result.removed
                item.format = result.format
                item.lossless = result.lossless
                item.outputProvenance = ProvenanceProbe.inspect(result.data)
                item.thumbnail = Self.thumbnail(from: result.data)
                return item
            } catch {
                let fallback = try? Data(contentsOf: url)
                var item = ScrubItem(id: id, sourceURL: url,
                                     originalSize: fallback?.count ?? 0,
                                     preset: preset)
                if let fallback { item.provenance = ProvenanceProbe.inspect(fallback) }
                item.errorText = error.localizedDescription
                item.thumbnail = fallback.flatMap { Self.thumbnail(from: $0) }
                return item
            }
        }.value
    }

    /// Downscales via ImageIO rather than `NSImage.lockFocus`, which is not safe
    /// off the main thread. `nonisolated` because this is called from the detached
    /// processing task, never from the main actor.
    nonisolated static func thumbnail(from data: Data, max side: Int = 160) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // MARK: Saving

    func save(item: ScrubItem) {
        guard let data = item.cleanedData else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.suggestedFilename
        panel.directoryURL = AppSettings.shared.defaultSaveDirectory
        panel.canCreateDirectories = true
        panel.message = "Save the cleaned copy of \(item.displayName)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(data, to: url, itemID: item.id)
    }

    func saveAll() {
        let pending = items.filter { $0.cleanedData != nil }
        guard !pending.isEmpty else { return }

        let folder: URL
        if let configured = AppSettings.shared.defaultSaveDirectory {
            folder = configured
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Save Here"
            panel.message = "Choose a folder for \(pending.count) cleaned image\(pending.count == 1 ? "" : "s")"
            guard panel.runModal() == .OK, let selected = panel.url else { return }
            folder = selected
        }

        var written = 0
        for item in pending {
            guard let data = item.cleanedData else { continue }
            let target = uniqueURL(in: folder, filename: item.suggestedFilename)
            if write(data, to: target, itemID: item.id) { written += 1 }
        }
        statusMessage = "Saved \(written) image\(written == 1 ? "" : "s") to \(folder.lastPathComponent)."
    }

    @discardableResult
    private func write(_ data: Data, to url: URL, itemID: UUID) -> Bool {
        do {
            try MediaSaveService.protectOriginals(
                destination: url, sourceURLs: items.map(\.sourceURL))
            try data.write(to: url, options: .atomic)
            if let idx = items.firstIndex(where: { $0.id == itemID }) {
                items[idx].savedTo = url
                // A cleaned batch can be hundreds of megabytes. Once the bytes are on
                // disk, retain only the report and destination rather than every output.
                items[idx].cleanedData = nil
            }
            return true
        } catch {
            statusMessage = "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }

    /// Avoids clobbering: photo-clean.jpg, photo-clean-2.jpg, ...
    private func uniqueURL(in folder: URL, filename: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(filename)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var n = 2
        repeat {
            let name = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
            candidate = folder.appendingPathComponent(name)
            n += 1
        } while fm.fileExists(atPath: candidate.path) && n < 1000
        return candidate
    }

    // MARK: Queue

    func clear() {
        items.removeAll()
        statusMessage = nil
        selectedItemID = nil
        activeFilter = nil
    }

    func remove(item: ScrubItem) {
        items.removeAll { $0.id == item.id }
        // Move the inspector to a neighbour rather than blanking it out.
        if selectedItemID == item.id { selectedItemID = visibleItems.first?.id ?? items.first?.id }
        // A filter with nothing left behind it is a dead end the user cannot see out of.
        if let activeFilter, count(of: activeFilter) == 0 { self.activeFilter = nil }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose images to scrub"
        guard panel.runModal() == .OK else { return }
        add(urls: panel.urls)
    }
}

// MARK: - Formatting

enum Fmt {
    static func bytes(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1024 * 1024 { return String(format: "%.1f KB", Double(n) / 1024) }
        return String(format: "%.2f MB", Double(n) / 1024 / 1024)
    }
}
