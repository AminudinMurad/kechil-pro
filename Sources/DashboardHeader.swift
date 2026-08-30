import SwiftUI

/// Batch-level summary: what this queue of images was carrying, before the user thinks
/// about saving anything. Replaces the old one-line summary bar.
struct DashboardHeader: View {
    @ObservedObject var model: ScrubModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            tileRow
            if !model.presentCategories.isEmpty {
                breakdown
            }
            calloutAndFootnote
            FilterRow(model: model)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: KPI tiles

    // Stat tiles, not a chart: these are a handful of headline numbers, and a one-bar
    // bar chart per number would say less in more space.
    private var tileRow: some View {
        HStack(spacing: 10) {
            StatTile(label: "Images", value: "\(model.items.count)")
            StatTile(label: "Carried metadata", value: "\(model.hadMetadataCount)")
            StatTile(label: "GPS location",
                     value: "\(model.locationLeakCount)",
                     accent: model.locationLeakCount > 0 ? VizPalette.critical : nil,
                     symbol: model.locationLeakCount > 0 ? MetadataCategory.gps.symbolName : nil)
            StatTile(label: "Generative AI",
                     value: "\(model.aiGeneratedCount)",
                     accent: model.aiGeneratedCount > 0 ? VizPalette.serious : nil,
                     symbol: model.aiGeneratedCount > 0 ? MetadataCategory.ai.symbolName : nil)
            StatTile(label: "Stripped", value: Fmt.bytes(model.totalBytesRemoved))
        }
    }

    // MARK: Category breakdown

    /// Horizontal bars, one per category, single series with the two high-stakes
    /// categories flagged in status colour.
    ///
    /// Deliberately *not* a stacked part-to-whole bar: one image can carry GPS and EXIF
    /// and XMP at once, so the counts do not sum to the image count and any share-of-total
    /// reading would be false. Deliberately not shaded by count either — that would
    /// encode bar length twice and spend the colour channel on nothing.
    private var breakdown: some View {
        let counts = model.categoryCounts
        let maxCount = max(1, counts.values.max() ?? 1)
        // Sorted by count, but ties break on the category's fixed rank so the order is
        // stable rather than dependent on dictionary iteration.
        let rows = model.presentCategories.sorted {
            let (a, b) = (counts[$0] ?? 0, counts[$1] ?? 0)
            return a == b ? $0.sortRank < $1.sortRank : a > b
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text("What was found")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            // No legend box: this is a single series, and the title above names it.
            VStack(spacing: 2) {   // the 2px surface gap that separates adjacent bars
                ForEach(rows) { category in
                    CategoryBar(category: category,
                                count: counts[category] ?? 0,
                                maxCount: maxCount)
                }
            }

            Rectangle()   // baseline: solid hairline, one step off the surface
                .fill(VizPalette.axis)
                .frame(height: 1)
                .padding(.leading, CategoryBar.labelWidth)
        }
    }

    // MARK: Callout

    private var calloutAndFootnote: some View {
        VStack(alignment: .leading, spacing: 3) {
            if model.locationLeakCount > 0 {
                Label {
                    Text("\(model.locationLeakCount) \(model.locationLeakCount == 1 ? "image" : "images") "
                         + "carried exact GPS coordinates.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(VizPalette.critical)
            }

            if model.aiGeneratedCount > 0 {
                Label("\(model.aiGeneratedCount) \(model.aiGeneratedCount == 1 ? "image declares or identifies" : "images declare or identify") Generative AI.",
                      systemImage: "sparkles")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(VizPalette.serious)
            }

            if model.reencodedCount > 0 {
                Text("\(model.reencodedCount) re-encoded — pixels changed on \(model.reencodedCount == 1 ? "that file" : "those files").")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Stays put in every state. The product must never imply it removes
            // in-pixel watermarks, because it cannot.
            Text("Invisible in-pixel watermarks such as SynthID are not metadata and are not removed.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Stat tile

/// Label, value, and an optional status accent. No delta or sparkline: there is no time
/// dimension in a queue of dropped files, so both would be decoration.
private struct StatTile: View {
    let label: String
    let value: String
    var accent: Color?
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let symbol, let accent {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accent)
                }
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Proportional figures, not tabular: these do not align in a column, and
            // equal-width digits make a value like "121" look loose at this size.
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(VizPalette.surface)
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(.quaternary, lineWidth: 1))
        )
    }
}

// MARK: - Bar

private struct CategoryBar: View {
    static let labelWidth: CGFloat = 132

    let category: MetadataCategory
    let count: Int
    let maxCount: Int

    var body: some View {
        HStack(spacing: 8) {
            // Identity comes from the label plus the coloured mark beside it. The text
            // itself stays in ink tokens — a mark colour is not a text colour.
            HStack(spacing: 5) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 9))
                    .foregroundStyle(VizPalette.color(for: category))
                    .frame(width: 11)
                Text(category.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: Self.labelWidth, alignment: .leading)

            GeometryReader { geo in
                let full = max(0, geo.size.width - valueColumn)
                let width = max(3, full * CGFloat(count) / CGFloat(maxCount))
                HStack(spacing: 6) {
                    BarShape(radius: 4)
                        .fill(VizPalette.color(for: category))
                        .frame(width: width)
                    // Value at the tip, in ink — one label per mark on a short chart,
                    // which is what direct labelling is for.
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: valueColumn - 6, alignment: .leading)
                }
            }
            .frame(height: barThickness)
        }
        .frame(height: barThickness)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.displayName): \(count) \(count == 1 ? "image" : "images")")
    }

    /// Capped well under the 24px ceiling; the leftover band stays as air.
    private var barThickness: CGFloat { 16 }
    private var valueColumn: CGFloat { 34 }
}

/// A bar with its data-end rounded and its baseline end square.
///
/// Hand-rolled because `UnevenRoundedRectangle` is macOS 14+ and this app targets 13.
private struct BarShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                    radius: r, startAngle: .degrees(-90), endAngle: .degrees(0),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                    radius: r, startAngle: .degrees(0), endAngle: .degrees(90),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Filter row

/// One filter row, above everything it scopes. It narrows the list only; the tiles and
/// chart keep describing the whole queue.
private struct FilterRow: View {
    @ObservedObject var model: ScrubModel

    var body: some View {
        // Wraps rather than truncating. A mixed queue routinely presents eight or nine
        // categories, and "Content Credentials 2" alone is ~140pt — a single HStack
        // overflows the main column and compresses every chip to "Content Cred…".
        FlowLayout(spacing: 6, lineSpacing: 6) {
            chip(title: "All \(model.items.count)", category: nil)
            ForEach(model.presentCategories) { category in
                chip(title: "\(category.displayName) \(model.count(of: category))",
                     category: category)
            }
        }
    }

    private func chip(title: String, category: MetadataCategory?) -> some View {
        let isActive = model.activeFilter == category
        // Colour follows the category, never its rank or the filter state, so choosing a
        // filter never repaints the categories that survive it.
        let tint = category.map { VizPalette.color(for: $0) } ?? Color.accentColor

        return Button {
            model.activeFilter = isActive ? nil : category
        } label: {
            HStack(spacing: 4) {
                if let category {
                    Image(systemName: category.symbolName).font(.system(size: 8))
                }
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(isActive ? .white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(isActive ? tint : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(category?.blurb ?? "Show every image in the queue")
    }
}

// MARK: - Wrapping layout

/// Lays subviews left to right, wrapping to a new line when the next one will not fit.
///
/// `Layout` landed in macOS 13, so this stays on the deployment target — unlike
/// `HStack`, which cannot wrap, and unlike `LazyVGrid`, which would force every chip
/// into a uniform column width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
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
                // Centre each chip in its line, so a taller neighbour does not drag the
                // short ones to the top of the band.
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
            // A chip wider than the whole row still gets placed rather than dropped —
            // it just takes a line of its own.
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
