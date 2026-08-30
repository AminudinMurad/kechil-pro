import SwiftUI

struct ToolSidebar: View {
    @Binding var selection: ToolRoute
    let count: (ToolRoute) -> Int
    @State private var expanded = Set(KechilTool.allCases)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Text("TOOLS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                ForEach(KechilTool.allCases) { tool in
                    DisclosureGroup(isExpanded: binding(for: tool)) {
                        VStack(spacing: 3) {
                            routeButton(ToolRoute(tool: tool, media: .image))
                            routeButton(ToolRoute(tool: tool, media: .video))
                        }
                        .padding(.top, 4)
                    } label: {
                        Label(tool.title, systemImage: tool.symbol)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .tint(.secondary)
                }

                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Label("Private by design", systemImage: "lock.shield.fill")
                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.green)
                    Text("Processing and saving stay on this Mac. Originals are never overwritten.")
                        .font(.system(size: 9.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.055))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.green.opacity(0.18), lineWidth: 1)))
            }
            .padding(12)
        }
        .kechilScrollbars()
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kechil tools")
    }

    private func binding(for tool: KechilTool) -> Binding<Bool> {
        Binding(get: { expanded.contains(tool) }, set: { isExpanded in
            if isExpanded { expanded.insert(tool) } else { expanded.remove(tool) }
        })
    }

    private func routeButton(_ route: ToolRoute) -> some View {
        Button { selection = route } label: {
            HStack(spacing: 8) {
                Image(systemName: route.media.symbol)
                    .font(.system(size: 11, weight: .semibold)).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(route.media.title)
                        .font(.system(size: 11.5, weight: selection == route ? .semibold : .regular))
                    Text(detail(for: route))
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                if count(route) > 0 {
                    Text("\(count(route))")
                        .font(.system(size: 8.5, weight: .bold)).monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            .foregroundStyle(selection == route ? Color.accentColor : Color.primary)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(selection == route ? Color.accentColor.opacity(0.12) : Color.clear))
        }
        .buttonStyle(.plain)
        .help(route.title)
        .accessibilityLabel("\(route.tool.title), \(route.media.title), \(count(route)) queued")
    }

    private func detail(for route: ToolRoute) -> String {
        switch (route.tool, route.media) {
        case (.clean, .image): return "EXIF, GPS, XMP and more"
        case (.clean, .video): return "MOV, MP4 and M4V metadata"
        case (.optimize, .image): return "Crop, resize and convert"
        case (.optimize, .video): return "Trim, crop and compress"
        case (.watermark, .image): return "Text or logo with preview"
        case (.watermark, .video): return "Static full-video mark"
        }
    }
}
