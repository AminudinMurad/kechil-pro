import SwiftUI

struct SettingsPanel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var sizer: DashboardSizer
    @State private var showingUpdateNotice = false

    private let githubURL = URL(string: "https://github.com/AminudinMurad")!
    private let sponsorsURL = URL(string: "https://github.com/sponsors/aminudinmurad")!
    private let kofiURL = URL(string: "https://ko-fi.com/aminudinmurad")!
    private let paypalURL = URL(string: "https://www.paypal.com/paypalme/aminudinmurad")!
    private let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.en.html")!

    var body: some View {
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

            aboutSection
            supportSection
        }
        .padding(14)
        .frame(width: 500)
        // The complete Settings stack fits below the smallest dashboard preset.
        // Keep it fully expanded so macOS does not add an inner scroll bar.
        .fixedSize(horizontal: false, vertical: true)
        .alert("Updates", isPresented: $showingUpdateNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Update checking is not configured yet.")
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
                    showingUpdateNotice = true
                } label: {
                    Label("Updates…", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Update checking is not configured yet")
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(cardBackground)
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

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 Aminudin Murad · GPL-3.0"
    }
}
