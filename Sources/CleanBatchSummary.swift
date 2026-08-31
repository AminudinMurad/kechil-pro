import SwiftUI

/// Shared compact presentation primitives for Image and Video Clean.
/// Detection and cleanup remain owned by their media-specific models; this file
/// only makes the two workspaces use the same geometry and interaction language.
enum CleanCompactStyle {
    static let scopeHeight: CGFloat = 30
    static let summaryHeight: CGFloat = 38
    static let horizontalPadding: CGFloat = 14
    static let chipSpacing: CGFloat = 6
}

struct CleanBatchMetric: Identifiable {
    enum Tone {
        case neutral
        case critical
        case serious

        var color: Color {
            switch self {
            case .neutral: return .secondary
            case .critical: return VizPalette.critical
            case .serious: return VizPalette.serious
            }
        }
    }

    let id: String
    let label: String
    let value: String
    var tone: Tone = .neutral
    var symbolName: String?
    var valueFirst = false

    init(_ label: String, _ value: String, tone: Tone = .neutral,
         symbolName: String? = nil, valueFirst: Bool = false) {
        id = label
        self.label = label
        self.value = value
        self.tone = tone
        self.symbolName = symbolName
        self.valueFirst = valueFirst
    }
}

struct CleanFindingCategory: Identifiable {
    let id: String
    let title: String
    let symbolName: String
    let count: Int
    let color: Color
    let help: String
}

/// Collapsed by default on every launch. The state deliberately lives in the
/// view and is never written to preferences.
struct CleanBatchSummary<Details: View>: View {
    let metrics: [CleanBatchMetric]
    let activeFilterTitle: String?
    let clearFilter: () -> Void
    private let details: Details
    @State private var isExpanded: Bool

    init(metrics: [CleanBatchMetric], activeFilterTitle: String? = nil,
         initiallyExpanded: Bool = false, clearFilter: @escaping () -> Void = {},
         @ViewBuilder details: () -> Details) {
        self.metrics = metrics
        self.activeFilterTitle = activeFilterTitle
        self.clearFilter = clearFilter
        self.details = details()
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("Findings")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse batch findings" : "Expand batch findings")
                .accessibilityLabel(isExpanded ? "Collapse findings" : "Expand findings")

                inlineMetrics

                if let activeFilterTitle {
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Text("Filtered: \(activeFilterTitle)")
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(1)
                        Button(action: clearFilter) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .help("Clear findings filter")
                        .accessibilityLabel("Clear \(activeFilterTitle) filter")
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.10)))
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, CleanCompactStyle.horizontalPadding)
            .frame(minHeight: CleanCompactStyle.summaryHeight)

            if isExpanded {
                Divider()
                details
                    .padding(.horizontal, CleanCompactStyle.horizontalPadding)
                    .padding(.vertical, 10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var inlineMetrics: some View {
        HStack(spacing: 6) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 {
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 3) {
                    if let symbolName = metric.symbolName {
                        Image(systemName: symbolName)
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    Text(metric.valueFirst
                         ? "\(metric.value) \(metric.label)"
                         : "\(metric.label) \(metric.value)")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                }
                .foregroundStyle(metric.tone.color)
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct CleanCategoryChart: View {
    let categories: [CleanFindingCategory]
    let unitName: String

    var body: some View {
        let maxCount = max(1, categories.map(\.count).max() ?? 1)
        VStack(alignment: .leading, spacing: 6) {
            Text("What was found")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 3) {
                ForEach(categories) { category in
                    CleanCategoryBar(category: category, maxCount: maxCount,
                                     unitName: unitName)
                }
            }
        }
    }
}

private struct CleanCategoryBar: View {
    let category: CleanFindingCategory
    let maxCount: Int
    let unitName: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 9))
                    .foregroundStyle(category.color)
                    .frame(width: 11)
                Text(category.title)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
            }
            .frame(width: 136, alignment: .leading)

            GeometryReader { geometry in
                let available = max(3, geometry.size.width - 34)
                let width = max(3, available * CGFloat(category.count) / CGFloat(maxCount))
                HStack(spacing: 6) {
                    Capsule()
                        .fill(category.color)
                        .frame(width: width, height: 12)
                    Text("\(category.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                }
            }
            .frame(height: 14)
        }
        .frame(height: 16)
        .help(category.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.title): \(category.count) \(category.count == 1 ? unitName : unitName + "s")")
    }
}

struct CleanFilterChips: View {
    let totalCount: Int
    let unitName: String
    let categories: [CleanFindingCategory]
    let activeID: String?
    let select: (String?) -> Void

    var body: some View {
        CompactFlowLayout(spacing: 6, lineSpacing: 6) {
            chip(title: "All \(totalCount)", symbolName: nil, id: nil,
                 tint: .accentColor, help: "Show every \(unitName) in the queue")
            ForEach(categories) { category in
                chip(title: "\(category.title) \(category.count)",
                     symbolName: category.symbolName, id: category.id,
                     tint: category.color, help: category.help)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Detected findings filters")
    }

    private func chip(title: String, symbolName: String?, id: String?,
                      tint: Color, help: String) -> some View {
        let selected = activeID == id
        return Button {
            select(selected ? nil : id)
        } label: {
            HStack(spacing: 4) {
                if let symbolName {
                    Image(systemName: symbolName).font(.system(size: 8))
                }
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(Capsule().fill(selected ? tint : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A macOS 13-compatible wrapping layout used by both scope and finding chips.
struct CompactFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let lines = wrap(subviews, within: proposal.width ?? .infinity)
        let height = lines.reduce(0) { $0 + $1.height }
            + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: proposal.width ?? (lines.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in wrap(subviews, within: bounds.width) {
            var x = bounds.minX
            for index in line.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func wrap(_ subviews: Subviews, within maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extended = line.items.isEmpty ? size.width : line.width + spacing + size.width
            if extended > maxWidth, !line.items.isEmpty {
                lines.append(line)
                line = Line(items: [index], width: size.width, height: size.height)
            } else {
                line.items.append(index)
                line.width = extended
                line.height = max(line.height, size.height)
            }
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}

struct CleanScopeChip: View {
    let title: String
    let symbolName: String
    let help: String
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 9)
            .frame(height: CleanCompactStyle.scopeHeight)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.09),
                              lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel("\(title). \(help)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
