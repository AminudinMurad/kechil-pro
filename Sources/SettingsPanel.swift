import SwiftUI

struct SettingsPanel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var sizer: DashboardSizer
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @Environment(\.openURL) private var openURL
    @AppStorage(UpdateChecker.autoCheckKey) private var automaticUpdateChecks = true

    private let githubURL = URL(string: "https://github.com/AminudinMurad/kechil-pro")!
    private let sponsorsURL = URL(string: "https://github.com/sponsors/aminudinmurad")!
    private let kofiURL = URL(string: "https://ko-fi.com/aminudinmurad")!
    private let paypalURL = URL(string: "https://www.paypal.com/paypalme/aminudinmurad")!
    private let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.en.html")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Settings")
                        .font(.system(size: 15, weight: .semibold))
                }

                DashboardSizeControl(sizer: sizer)
                    .background(cardBackground)

                saveDirectorySection
                    .background(cardBackground)

                convertedFilenameSection
                    .background(cardBackground)

                aboutSection
                supportSection
            }
            .padding(14)
        }
        .kechilScrollbars()
        // Keep the popover usable on the smallest supported MacBook now that output
        // naming is configurable. Every setting remains reachable by scrolling.
        .frame(width: 500, height: 700)
        .alert(item: $updateChecker.notice) { notice in
            if let releaseURL = notice.releaseURL {
                return Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    primaryButton: .default(Text("Open Release Page")) {
                        openURL(releaseURL)
                    },
                    secondaryButton: .cancel(Text("Later"))
                )
            }
            return Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
    }

    private var saveDirectorySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading("Default save folder")

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: settings.defaultSaveDirectory == nil
                      ? "folder.badge.questionmark" : "folder.fill")
                    .foregroundStyle(.secondary)
                Text(settings.defaultSaveDirectory?.path(percentEncoded: false)
                     ?? "Not set — Save All will ask each time")
                    .font(.system(size: 11.5))
                    .foregroundStyle(settings.defaultSaveDirectory == nil ? .secondary : .primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.045)))

            HStack {
                Button(settings.defaultSaveDirectory == nil ? "Choose Folder…" : "Change Folder…") {
                    settings.chooseDefaultSaveDirectory()
                }
                if settings.defaultSaveDirectory != nil {
                    Button("Clear") { settings.clearDefaultSaveDirectory() }
                }
            }

            Text("Processed outputs from selected or fetched media save here with collision-safe filenames. Individual Save dialogs open here first; fetched source files remain temporary.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = settings.defaultSaveDirectoryError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(VizPalette.serious)
            }
        }
        .padding(16)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("About")

            Text("Open-source image and video cleanup, optimization and watermarking for macOS.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.top, 18)

            Text("Version \(version) (\(buildNumber))")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            Toggle(isOn: $automaticUpdateChecks) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatically check for updates")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("Check GitHub for a newer version at launch")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: automaticUpdateChecks) { enabled in
                updateChecker.automaticChecksChanged(enabled)
            }
            .padding(.top, 10)

            HStack(alignment: .center, spacing: 12) {
                Link(destination: licenseURL) {
                    Text(copyright)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Read the GNU GPL v3.0 license")

                Spacer(minLength: 8)

                Button {
                    if let releaseURL = updateChecker.updateAvailableURL {
                        openURL(releaseURL)
                    } else {
                        updateChecker.checkManually()
                    }
                } label: {
                    Label(updateButtonTitle, systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(updateChecker.isChecking)
                .help(updateButtonHelp)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var convertedFilenameSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading("Converted filenames")

            HStack(spacing: 8) {
                Text("Append")
                    .font(.system(size: 11.5, weight: .medium))

                TextField("-kechil", text: $settings.convertedFilenameAppendage)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Converted image filename appendage")

                Button("Reset") {
                    settings.resetConvertedFilenameAppendage()
                }
                .disabled(settings.convertedFilenameAppendage ==
                          ConvertedFilenameNaming.defaultAppendage)
            }

            Text("Examples: photo\(settings.effectiveConvertedFilenameAppendage)\(resolutionExample).webp · clip-optimized\(resolutionExample).mp4")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)

            Toggle("Append saved resolution to filename",
                   isOn: $settings.appendsResolutionToConvertedFilenames)
                .font(.system(size: 11.5))
                .toggleStyle(.checkbox)
                .help("Append each saved image or video's actual final width and height to its filename.")

            Text("Kechil automatically reads each finished file's actual final width × height. There are no dimensions to enter.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Custom text applies to converted images. Saved resolution applies to image and video outputs from Optimize and Watermark. Leave the text blank to keep an image's original base name; Kechil still protects existing files and originals.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var resolutionExample: String {
        settings.appendsResolutionToConvertedFilenames ? "-1920x1080" : ""
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Support open-source development")

            HStack(spacing: 6) {
                supportLink("GitHub", symbol: "chevron.left.forwardslash.chevron.right",
                            tint: .secondary, destination: githubURL)
                supportLink("GitHub Sponsors", symbol: "heart.fill",
                            tint: .pink, destination: sponsorsURL)
                supportLink("Ko-fi", symbol: "cup.and.saucer.fill",
                            tint: Color(red: 1, green: 0.37, blue: 0.36), destination: kofiURL)
                supportLink("PayPal", symbol: "dollarsign.circle.fill",
                            tint: Color(red: 0, green: 0.44, blue: 0.73), destination: paypalURL)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)
    }

    private func supportLink(_ title: String, symbol: String, tint: Color,
                             destination: URL) -> some View {
        Link(destination: destination) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .help("Open \(title)")
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var updateButtonTitle: String {
        if updateChecker.isChecking { return "Checking…" }
        if updateChecker.updateAvailableURL != nil { return "Update ready" }
        return "Updates…"
    }

    private var updateButtonHelp: String {
        if updateChecker.updateAvailableURL != nil {
            return "Open the latest Kechil PRO GitHub release"
        }
        return "Check GitHub for a newer Kechil PRO release"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 Aminudin Murad · GPL-3.0"
    }
}
