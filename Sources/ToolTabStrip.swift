import SwiftUI

struct ToolTabStrip: View {
    @Binding var selection: KechilTool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(KechilTool.allCases) { tool in
                Button {
                    selection = tool
                } label: {
                    Label(tool.title, systemImage: tool.symbol)
                        .font(.system(size: 11.5, weight: selection == tool ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == tool ? Color.accentColor : Color.secondary)
                .background(
                    Capsule().fill(selection == tool ? Color.accentColor.opacity(0.13) : .clear)
                )
                .accessibilityLabel(tool.scopeDescription)
                .accessibilityAddTraits(selection == tool ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(0.055)))
    }
}
