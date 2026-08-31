import Foundation
import SwiftUI

/// A small GitHub release checker shared by the dashboard and Settings popover.
///
/// It only reads the public latest-release endpoint. It never uploads media, sends
/// account information or downloads an update automatically; the user chooses when
/// to open the public release page.
@MainActor
final class UpdateChecker: ObservableObject {
    struct UpdateNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let releaseURL: URL?
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    static let shared = UpdateChecker()
    static let autoCheckKey = "kechil.autoCheckUpdates"
    static let repositoryAPIURL = URL(string: "https://api.github.com/repos/AminudinMurad/kechil-pro/releases/latest")!
    static let releasesURL = URL(string: "https://github.com/AminudinMurad/kechil-pro/releases/latest")!

    @Published private(set) var isChecking = false
    @Published private(set) var updateAvailableURL: URL?
    @Published private(set) var updateAvailableVersion: String?
    @Published var notice: UpdateNotice?

    private var requestTask: Task<Void, Never>?
    private var automaticCheckAttempted = false

    private init() {}

    var automaticChecksEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true
    }

    /// Runs once on the first real dashboard appearance. Snapshot rendering is
    /// intentionally offline so visual regression tests never depend on GitHub.
    func checkOnLaunchIfNeeded() {
        guard !automaticCheckAttempted else { return }
        automaticCheckAttempted = true
        guard automaticChecksEnabled, !Self.isSnapshotRenderer else { return }
        check(silently: true)
    }

    /// If the user turns the setting on while the app is open, check immediately.
    /// Turning it off cancels an in-flight request and clears the ready marker.
    func automaticChecksChanged(_ enabled: Bool) {
        guard enabled else {
            requestTask?.cancel()
            requestTask = nil
            isChecking = false
            updateAvailableURL = nil
            updateAvailableVersion = nil
            notice = nil
            return
        }
        if automaticCheckAttempted {
            guard !Self.isSnapshotRenderer else { return }
            check(silently: true)
        } else {
            checkOnLaunchIfNeeded()
        }
    }

    func checkManually() {
        check(silently: false)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = numericComponents(candidate)
        let currentParts = numericComponents(current)
        for index in 0..<max(candidateParts.count, currentParts.count) {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart { return candidatePart > currentPart }
        }
        return false
    }

    private func check(silently: Bool) {
        requestTask?.cancel()
        isChecking = true
        if !silently { notice = nil }
        let currentVersion = Self.currentVersion

        requestTask = Task { @MainActor [weak self] in
            do {
                let release = try await Self.fetchLatestRelease()
                guard let self, !Task.isCancelled else { return }
                self.finish(release: release, currentVersion: currentVersion, silently: silently)
            } catch is CancellationError {
                // A newer request or the opt-out setting owns the next result.
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.finish(error: error, silently: silently)
            }
        }
    }

    private func finish(release: GitHubRelease, currentVersion: String, silently: Bool) {
        requestTask = nil
        isChecking = false
        let latestVersion = Self.normalisedVersion(release.tagName)
        guard !latestVersion.isEmpty else {
            finish(error: UpdateCheckerError.invalidRelease, silently: silently)
            return
        }

        if Self.isNewer(latestVersion, than: currentVersion), let releaseURL = release.htmlURL {
            updateAvailableVersion = latestVersion
            updateAvailableURL = releaseURL
            if !silently {
                notice = UpdateNotice(
                    title: "Update available — v\(latestVersion)",
                    message: "You have v\(currentVersion). Open the release page to download the latest version.",
                    releaseURL: releaseURL
                )
            }
        } else {
            updateAvailableVersion = nil
            updateAvailableURL = nil
            if !silently {
                notice = UpdateNotice(
                    title: "You're up to date",
                    message: "Kechil PRO v\(currentVersion) is the latest version.",
                    releaseURL: nil
                )
            }
        }
    }

    private func finish(error: Error, silently: Bool) {
        requestTask = nil
        isChecking = false
        updateAvailableVersion = nil
        updateAvailableURL = nil
        guard !silently else { return }
        notice = UpdateNotice(
            title: "Couldn't check for updates",
            message: "Please check your connection and try again, or visit the Releases page.",
            releaseURL: Self.releasesURL
        )
    }

    private static func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: repositoryAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Kechil-PRO", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw UpdateCheckerError.httpFailure
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private static func normalisedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.first == "v" || trimmed.first == "V" {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private static func numericComponents(_ value: String) -> [Int] {
        normalisedVersion(value).split(separator: ".").map { Int($0) ?? 0 }
    }

    private static var isSnapshotRenderer: Bool {
        ProcessInfo.processInfo.arguments.first?.hasSuffix("ui-snapshot-renderer") == true
    }

    private enum UpdateCheckerError: LocalizedError {
        case httpFailure
        case invalidRelease

        var errorDescription: String? {
            switch self {
            case .httpFailure: return "GitHub did not return a release response."
            case .invalidRelease: return "GitHub returned an invalid release tag."
            }
        }
    }
}
