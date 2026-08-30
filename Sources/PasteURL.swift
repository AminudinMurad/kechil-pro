import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum PasteURLSource: Equatable {
    case local(URL)
    case remote(URL)
}

enum PasteURLService {
    /// Best-effort clipboard text for the Paste URL sheet. Finder copies a local
    /// file URL to the `fileURL` pasteboard type; browsers usually expose plain
    /// text, so both representations are considered.
    static func clipboardText() -> String {
        if let fileURL = NSPasteboard.general.string(forType: .fileURL), !fileURL.isEmpty {
            return fileURL
        }
        return NSPasteboard.general.string(forType: .string) ?? ""
    }

    /// Pasteboard providers can be owned by another process and may take seconds to
    /// resolve (for example when a clipboard manager or file promise is involved).
    /// Never make that cross-process request from a SwiftUI button action.
    static func clipboardTextAsync() async -> String {
        await Task.detached(priority: .userInitiated) {
            clipboardText()
        }.value
    }

    /// Resolves a local file URL or an absolute local path.
    static func localFileURL(from text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), url.isFileURL {
            return url.standardizedFileURL
        }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value).standardizedFileURL
        }
        return nil
    }

    static func source(from text: String) -> PasteURLSource? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            guard url.host != nil else { return nil }
            return .remote(url)
        }
        if let url = localFileURL(from: value) {
            return .local(url)
        }
        return nil
    }

    static func validationMessage(for text: String, media: MediaKind) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "Paste one direct \(media.singularTitle) URL." }
        guard let source = source(from: value) else {
            return "Use a direct http(s) URL, a local file URL, or an absolute path."
        }
        guard case .local(let url) = source else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return "That local file could not be found."
        }
        if isDirectory.boolValue {
            return "Paste a file URL, not a folder URL."
        }
        guard supports(url: url, media: media) else {
            return "That local file is not a supported \(media.singularTitle)."
        }
        return nil
    }

    static func supports(url: URL, media: MediaKind) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        switch media {
        case .image: return type.conforms(to: .image)
        case .video: return type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
        }
    }
}

enum DirectMediaDownloadError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case tooLarge
    case webpage
    case unsupported(MediaKind)
    case emptyDownload

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server did not return a valid file response."
        case .httpStatus(let status):
            return "The server returned HTTP \(status)."
        case .tooLarge:
            return "That file is larger than Kechil's 20 GB direct-download limit."
        case .webpage:
            return "That URL returned a webpage, not a direct media file."
        case .unsupported(let media):
            return "That URL did not return a supported \(media.singularTitle) file."
        case .emptyDownload:
            return "The downloaded file was empty."
        }
    }
}

/// Downloads one user-supplied direct media URL into Kechil's temporary folder.
/// The source is never uploaded again: all analysis, transformation and saving use
/// this local copy. URLSession writes to disk, so large media is not buffered in RAM.
enum DirectMediaDownloadService {
    static let maximumBytes: Int64 = 20_000_000_000

    static func fetch(_ remoteURL: URL, media: MediaKind) async throws -> URL {
        var request = URLRequest(url: remoteURL,
                                 cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 60)
        request.setValue("KechilPRO/1.0", forHTTPHeaderField: "User-Agent")

        let (downloadURL, response) = try await URLSession.shared.download(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw DirectMediaDownloadError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw DirectMediaDownloadError.httpStatus(http.statusCode)
        }
        if response.expectedContentLength > maximumBytes {
            throw DirectMediaDownloadError.tooLarge
        }

        let mime = response.mimeType?.lowercased() ?? ""
        if mime == "text/html" || mime == "application/xhtml+xml" {
            throw DirectMediaDownloadError.webpage
        }

        let filename = preferredFilename(response: response, originalURL: remoteURL)
        guard let fileExtension = supportedExtension(filename: filename,
                                                     mimeType: mime,
                                                     media: media) else {
            throw DirectMediaDownloadError.unsupported(media)
        }
        if !mime.isEmpty && !mimeMatches(mime, media: media) && !isGenericMIME(mime) {
            throw DirectMediaDownloadError.unsupported(media)
        }

        let size = (try FileManager.default.attributesOfItem(atPath: downloadURL.path)[.size]
                    as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw DirectMediaDownloadError.emptyDownload }
        guard size <= maximumBytes else { throw DirectMediaDownloadError.tooLarge }

        let folder = try importFolder()
        cleanupOldImports(in: folder)
        let base = safeBasename(filename: filename)
        let destination = folder.appendingPathComponent(
            "\(UUID().uuidString)-\(base).\(fileExtension)")
        try FileManager.default.moveItem(at: downloadURL, to: destination)
        return destination
    }

    private static func importFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kechil PRO URL Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)
        return folder
    }

    private static func cleanupOldImports(in folder: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for file in files {
            let date = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            if let date, date < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static func preferredFilename(response: URLResponse, originalURL: URL) -> String {
        if let suggested = response.suggestedFilename, !suggested.isEmpty {
            return suggested
        }
        if let finalName = response.url?.lastPathComponent, !finalName.isEmpty {
            return finalName
        }
        return originalURL.lastPathComponent.isEmpty ? "download" : originalURL.lastPathComponent
    }

    private static func supportedExtension(filename: String, mimeType: String,
                                           media: MediaKind) -> String? {
        let candidate = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif",
                                            "tif", "tiff", "gif", "bmp"]
        let allowed = media == .video ? videoExtensions : imageExtensions
        if allowed.contains(candidate) { return candidate }

        switch (media, mimeType) {
        case (.video, "video/mp4"), (.video, "application/mp4"): return "mp4"
        case (.video, "video/quicktime"): return "mov"
        case (.video, "video/x-m4v"): return "m4v"
        case (.image, "image/jpeg"): return "jpg"
        case (.image, "image/png"): return "png"
        case (.image, "image/webp"): return "webp"
        case (.image, "image/heic"), (.image, "image/heif"): return "heic"
        case (.image, "image/tiff"): return "tiff"
        case (.image, "image/gif"): return "gif"
        case (.image, "image/bmp"): return "bmp"
        default: return nil
        }
    }

    private static func mimeMatches(_ mime: String, media: MediaKind) -> Bool {
        switch media {
        case .image: return mime.hasPrefix("image/")
        case .video: return mime.hasPrefix("video/") || mime == "application/mp4"
        }
    }

    private static func isGenericMIME(_ mime: String) -> Bool {
        mime == "application/octet-stream" || mime == "binary/octet-stream"
    }

    private static func safeBasename(filename: String) -> String {
        let raw = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let value = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "download" : String(value.prefix(80))
    }
}

/// URL/path field with an explicit, non-blocking clipboard action. Keeping the icon
/// inside the field matches the input convention used by the reference workflow while
/// making it clear that Kechil will not read the clipboard merely because a tab opened.
struct ClipboardURLField: View {
    let placeholder: String
    @Binding var text: String
    let isReadingClipboard: Bool
    let paste: () -> Void
    let submit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { submit() }

            Button(action: paste) {
                if isReadingClipboard {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "clipboard")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isReadingClipboard)
            .help("Paste from Clipboard")
            .accessibilityLabel("Paste from Clipboard")
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(isFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                          lineWidth: isFocused ? 2 : 1))
    }
}

struct PasteURLPanel: View {
    @Binding var isPresented: Bool
    @State private var value: String
    @State private var error: String?
    @State private var isReadingClipboard = false
    @State private var isFetching = false
    @State private var fetchTask: Task<Void, Never>?
    let media: MediaKind
    let submit: (URL) -> Void

    init(isPresented: Binding<Bool>, initialValue: String, media: MediaKind,
         submit: @escaping (URL) -> Void) {
        _isPresented = isPresented
        _value = State(initialValue: initialValue)
        self.media = media
        self.submit = submit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Paste URL", systemImage: "link")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Cancel") {
                    cancelFetch()
                    isPresented = false
                }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderless)
            }

            Text("Kechil downloads one direct \(media.singularTitle) URL to a temporary local file. Processing and saving stay on this Mac; nothing is uploaded.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ClipboardURLField(placeholder: "Paste one direct \(media.singularTitle) URL…",
                              text: $value,
                              isReadingClipboard: isReadingClipboard,
                              paste: pasteFromClipboard,
                              submit: useURL)
                .disabled(isFetching)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isFetching {
                Label("Downloading \(media.singularTitle) to this Mac…",
                      systemImage: "arrow.down.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            HStack {
                if isFetching {
                    Button("Stop") { cancelFetch() }
                }
                Spacer()
                Button {
                    useURL()
                } label: {
                    HStack(spacing: 6) {
                        if isFetching { ProgressView().controlSize(.small) }
                        Text("Fetch \(media.singularTitle)")
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isFetching || value.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 430)
        .onDisappear { fetchTask?.cancel() }
    }

    private func pasteFromClipboard() {
        guard !isReadingClipboard else { return }
        isReadingClipboard = true
        error = nil
        Task {
            let clipboard = await PasteURLService.clipboardTextAsync()
            isReadingClipboard = false
            guard !clipboard.isEmpty else {
                error = "The clipboard does not contain a URL or path."
                return
            }
            value = clipboard
        }
    }

    private func useURL() {
        if let message = PasteURLService.validationMessage(for: value, media: media) {
            error = message
            return
        }
        guard let source = PasteURLService.source(from: value) else { return }
        error = nil
        switch source {
        case .local(let url):
            submit(url)
            isPresented = false
        case .remote(let url):
            isFetching = true
            fetchTask = Task {
                do {
                    let localURL = try await DirectMediaDownloadService.fetch(url, media: media)
                    try Task.checkCancellation()
                    submit(localURL)
                    isPresented = false
                } catch is CancellationError {
                    // Cancellation is user-directed and does not need an error banner.
                } catch {
                    self.error = error.localizedDescription
                }
                isFetching = false
                fetchTask = nil
            }
        }
    }

    private func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
        isFetching = false
    }
}
