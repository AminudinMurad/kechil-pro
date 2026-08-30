import SwiftUI

@main
struct KechilProApp: App {
    /// Shared with `ContentView`'s size popover, so the menu items and the tiles drive
    /// the same window. `.shared` rather than `@StateObject`, because a `@MainActor`
    /// object cannot be built in `App`'s nonisolated initialiser.
    private let sizer = DashboardSizer.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // DashboardSizer fixes content width at 940 on the resolved NSWindow while
        // leaving height resizable. SwiftUI supplies the matching content floor.
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }   // no "New Window"

            // Under Window ▸ where macOS already keeps size commands, so the presets are
            // reachable by keyboard and discoverable without opening the popover.
            CommandGroup(after: .windowSize) {
                Menu("Dashboard Best Fit") {
                    ForEach(Array(DashboardPreset.allCases.enumerated()), id: \.element) { index, preset in
                        Button("\(preset.controlTitle)  —  \(preset.sizeTitle)") {
                            sizer.apply(preset)
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    }
                }
            }
        }
    }
}
