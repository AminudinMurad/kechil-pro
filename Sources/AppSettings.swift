import AppKit
import Foundation

/// User preferences that are safe to persist. Media queues and processing history never
/// enter UserDefaults; the only file-related value is a security-scoped bookmark to a
/// folder the user explicitly selected as their save destination.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published private(set) var defaultSaveDirectory: URL?
    @Published private(set) var defaultSaveDirectoryError: String?

    private static let bookmarkKey = "kechil.defaultSaveDirectoryBookmark.v1"
    private var isAccessingDefaultDirectory = false

    private init() {
        restoreDefaultSaveDirectory()
    }

    func chooseDefaultSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose the default folder for processed images and videos"
        panel.directoryURL = defaultSaveDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            activate(url)
            defaultSaveDirectoryError = nil
        } catch {
            defaultSaveDirectoryError = "Could not remember this folder: \(error.localizedDescription)"
        }
    }

    func clearDefaultSaveDirectory() {
        if isAccessingDefaultDirectory, let defaultSaveDirectory {
            defaultSaveDirectory.stopAccessingSecurityScopedResource()
        }
        isAccessingDefaultDirectory = false
        defaultSaveDirectory = nil
        defaultSaveDirectoryError = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    private func restoreDefaultSaveDirectory() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark,
                              options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            activate(url)
            if isStale {
                let refreshed = try url.bookmarkData(options: .withSecurityScope,
                                                     includingResourceValuesForKeys: nil,
                                                     relativeTo: nil)
                UserDefaults.standard.set(refreshed, forKey: Self.bookmarkKey)
            }
        } catch {
            defaultSaveDirectoryError = "The saved folder is no longer available. Choose it again."
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        }
    }

    private func activate(_ url: URL) {
        if isAccessingDefaultDirectory, let defaultSaveDirectory {
            defaultSaveDirectory.stopAccessingSecurityScopedResource()
        }
        defaultSaveDirectory = url
        isAccessingDefaultDirectory = url.startAccessingSecurityScopedResource()
    }
}
