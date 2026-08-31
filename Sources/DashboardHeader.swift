import SwiftUI

/// Compact Image Clean batch summary. Its source counts remain independent of
/// the selected removal scope and of any prepared output.
struct DashboardHeader: View {
    @ObservedObject var model: ScrubModel
    var initiallyExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            BatchOutputHeader(queuedCount: model.items.count, readyCount: model.cleanedCount,
                              isProcessing: model.isProcessing, save: model.saveAll,
                              selectedName: model.selectedItem?.displayName,
                              selectedCount: model.selectedItemCount,
                              selectedReadyCount: model.selectedSaveCount,
                              canSaveSelected: model.canSaveSelected, saveSelected: model.saveSelected)
            Divider()
            findings
        }
    }

    private var findings: some View {
        CleanBatchSummary(metrics: metrics,
                          activeFilterTitle: model.activeFilter?.displayName,
                          initiallyExpanded: initiallyExpanded,
                          clearFilter: { model.selectFilter(nil) }) {
            VStack(alignment: .leading, spacing: 9) {
                if !categories.isEmpty {
                    CleanCategoryChart(categories: categories, unitName: "image")
                }
                callouts
                if !categories.isEmpty {
                    CleanFilterChips(totalCount: model.items.count,
                                     unitName: "image",
                                     categories: categories,
                                     activeID: model.activeFilter?.rawValue) { id in
                        model.selectFilter(id.flatMap(MetadataCategory.init(rawValue:)))
                    }
                }
            }
        }
    }

    private var metrics: [CleanBatchMetric] {
        [
            CleanBatchMetric(model.items.count == 1 ? "image" : "images",
                             "\(model.items.count)", valueFirst: true),
            CleanBatchMetric("Metadata", "\(model.hadMetadataCount)"),
            CleanBatchMetric("GPS", "\(model.locationLeakCount)",
                             tone: model.locationLeakCount > 0 ? .critical : .neutral,
                             symbolName: model.locationLeakCount > 0 ? "location.fill" : nil),
            CleanBatchMetric("AI", "\(model.aiGeneratedCount)",
                             tone: model.aiGeneratedCount > 0 ? .serious : .neutral,
                             symbolName: model.aiGeneratedCount > 0 ? "sparkles" : nil),
            CleanBatchMetric("Stripped", Fmt.bytes(model.totalBytesRemoved)),
        ]
    }

    private var categories: [CleanFindingCategory] {
        model.presentCategories.map { category in
            CleanFindingCategory(id: category.rawValue,
                                 title: category.displayName,
                                 symbolName: category.symbolName,
                                 count: model.count(of: category),
                                 color: VizPalette.color(for: category),
                                 help: category.blurb)
        }
    }

    private var callouts: some View {
        VStack(alignment: .leading, spacing: 3) {
            if model.locationLeakCount > 0 {
                Label("\(model.locationLeakCount) \(model.locationLeakCount == 1 ? "image carries" : "images carry") exact GPS coordinates.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(VizPalette.critical)
            }
            if model.aiGeneratedCount > 0 {
                Label("\(model.aiGeneratedCount) \(model.aiGeneratedCount == 1 ? "image declares or identifies" : "images declare or identify") Generative AI.",
                      systemImage: "sparkles")
                    .foregroundStyle(VizPalette.serious)
            }
            if model.reencodedCount > 0 {
                Text("\(model.reencodedCount) re-encoded — pixels changed on \(model.reencodedCount == 1 ? "that file" : "those files").")
                    .foregroundStyle(.secondary)
            }
            Text("Invisible in-pixel watermarks such as SynthID are not metadata and are not removed.")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10.5, weight: .medium))
    }
}
