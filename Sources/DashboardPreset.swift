import AppKit
import SwiftUI

// MARK: - Presets

/// Best-fit dashboard sizes, one per MacBook the app is expected to run on.
///
/// Mirrors `KlikProDashboardPreset` in Klik PRO so the two apps offer the same
/// fixed-width, height-only control. Kechil's split layouts fit comfortably inside
/// the shared 940-point dashboard width.
enum DashboardPreset: String, CaseIterable, Identifiable {
    case air13M1
    case air13Modern
    case pro14
    case air15
    case pro16

    var id: String { rawValue }

    var controlTitle: String {
        switch self {
        case .air13M1:     return "13-inch M1"
        case .air13Modern: return "13-inch M2+"
        case .pro14:       return "14-inch"
        case .air15:       return "15-inch"
        case .pro16:       return "16-inch"
        }
    }

    /// Content size, not frame size — the title bar is added by `DashboardSizer`.
    ///
    /// Width stays fixed while each MacBook preset contributes only its best-fit
    /// height. Height is still clamped to the visible screen when applied.
    var contentSize: CGSize {
        switch self {
        case .air13M1:     return CGSize(width: DashboardMetrics.fixedContentWidth, height: 770)
        case .air13Modern: return CGSize(width: DashboardMetrics.fixedContentWidth, height: 820)
        case .pro14:       return CGSize(width: DashboardMetrics.fixedContentWidth, height: 860)
        case .air15:       return CGSize(width: DashboardMetrics.fixedContentWidth, height: 900)
        case .pro16:       return CGSize(width: DashboardMetrics.fixedContentWidth, height: 960)
        }
    }

    var sizeTitle: String { "\(Int(contentSize.width)) × \(Int(contentSize.height))" }

    /// Screen diagonal in inches. Drives the width of the drawn MacBook glyph, so the
    /// tiles read as a size ladder before any label is read.
    var diagonal: CGFloat {
        switch self {
        case .air13M1:     return 13.3
        case .air13Modern: return 13.6
        case .pro14:       return 14.2
        case .air15:       return 15.3
        case .pro16:       return 16.2
        }
    }

    /// The M1 Air is the one model in this list with no display notch.
    var hasNotch: Bool { self != .air13M1 }

    /// Reverse lookup for the "On now" status.
    ///
    /// The tolerance absorbs the half-point rounding AppKit applies on Retina without
    /// reaching a neighbouring preset — the closest two differ by 40 points.
    static func matching(contentSize size: CGSize) -> DashboardPreset? {
        allCases.first {
            abs(size.width  - $0.contentSize.width)  < 1.5 &&
            abs(size.height - $0.contentSize.height) < 1.5
        }
    }
}

// MARK: - Metrics

enum DashboardMetrics {
    static let fixedContentWidth: CGFloat = 940

    /// Height floor matching `ContentView`. The equal minimum and maximum widths make
    /// AppKit expose only the vertical resize direction.
    // Image Optimize and Watermark both use a split workspace with a scrollable
    // settings column. Below 650 pt AppKit can satisfy the split view's intrinsic
    // height by pushing the global brand header above the visible content. Keep a
    // compact floor that is still well below the smallest 770 pt MacBook preset.
    static let minimumContentSize = CGSize(width: fixedContentWidth, height: 650)

    /// Window geometry only — a rect, nothing else.
    ///
    /// This does not reopen the session-only decision. That rule is about scrub
    /// results: which files were dropped and what they were found to disclose. None of
    /// that is written here, and a window rectangle discloses nothing about the user's
    /// photos.
    static let framePreferenceKey = "kechil.dashboardWindowFrame.v2"
}

// MARK: - Sizer

/// Applies presets to the real `NSWindow`, and remembers where the user left it.
///
/// Not `@MainActor`-isolated, unlike `ScrubModel`: every entry point here is either a
/// SwiftUI action or an AppKit window callback, both already on the main thread, and
/// nothing in this file touches another actor. Marking the type would only fight
/// `App`'s nonisolated initialiser for no gain in safety.
final class DashboardSizer: NSObject, ObservableObject {

    /// Shared because the menu commands live in `App` and the popover lives in
    /// `ContentView`, and both must drive the same window.
    static let shared = DashboardSizer()

    /// Live content size, so the size control can say what is on now while the user is
    /// still dragging the window edge.
    @Published private(set) var contentSize: CGSize = DashboardMetrics.minimumContentSize

    private weak var window: NSWindow?
    private let defaults = UserDefaults.standard

    private override init() { super.init() }

    /// The preset currently in effect, or `nil` when the user has dragged to a size of
    /// their own.
    var activePreset: DashboardPreset? { DashboardPreset.matching(contentSize: contentSize) }

    // MARK: Attaching

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        NotificationCenter.default.removeObserver(self)
        self.window = window

        // Selector-based observation rather than taking the delegate: SwiftUI's
        // `WindowGroup` already owns this window's delegate, and replacing it would
        // silently break whatever else SwiftUI routes through it.
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(geometryChanged), name: name, object: window)
        }

        // The frame is ours to persist, so AppKit's own state restoration must not also
        // write one — otherwise two writers race and which size comes back next launch
        // depends on shutdown order.
        window.isRestorable = false

        // Keep the app vertically resizable while removing horizontal resize. Setting
        // both content limits is the AppKit constraint; the SwiftUI minimum alone would
        // still permit the user to widen the window.
        window.contentMinSize = DashboardMetrics.minimumContentSize
        window.contentMaxSize = CGSize(width: DashboardMetrics.fixedContentWidth,
                                       height: CGFloat.greatestFiniteMagnitude)

        restore()
        record()
    }

    @objc private func geometryChanged() { record() }

    private func record() {
        guard let window else { return }
        contentSize = window.contentRect(forFrameRect: window.frame).size
        defaults.set(NSStringFromRect(window.frame), forKey: DashboardMetrics.framePreferenceKey)
    }

    // MARK: Applying

    func apply(_ preset: DashboardPreset) { apply(preset, animate: true, recentre: false) }

    private func apply(_ preset: DashboardPreset, animate: Bool, recentre: Bool) {
        guard let window else { return }
        let screen = window.screen ?? NSScreen.main
        let target = fitted(preset.contentSize, on: screen)

        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: target))
        if recentre, let visible = screen?.visibleFrame {
            frame.origin = CGPoint(x: visible.midX - frame.width / 2,
                                   y: visible.midY - frame.height / 2)
        } else {
            // Pin the top-left corner. Growing downward is how a manual resize behaves;
            // re-centring on every click would make the window hop around the screen.
            frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        }

        window.setFrame(nudgedOnScreen(frame, on: screen), display: true, animate: animate)
        record()
    }

    // MARK: Restoring

    private func restore() {
        guard let window else { return }

        if let stored = storedFrame(), let screen = screen(showing: stored) {
            window.setFrame(nudgedOnScreen(stored, on: screen), display: false)
            return
        }
        // First launch: the largest preset this screen can actually hold, so a 16-inch
        // Pro is not handed a 13-inch window and a 13-inch Air is not handed one whose
        // buttons fall off the bottom.
        let screen = window.screen ?? NSScreen.main
        let best = DashboardPreset.allCases.last { fits($0.contentSize, on: screen) }
        apply(best ?? .air13M1, animate: false, recentre: true)
    }

    private func storedFrame() -> CGRect? {
        guard let raw = defaults.string(forKey: DashboardMetrics.framePreferenceKey) else {
            return nil
        }
        let rect = NSRectFromString(raw)
        // A malformed or stale string can decode to zeros or NaN, which would place the
        // window at the origin with no size and look like a launch failure.
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width >= DashboardMetrics.minimumContentSize.width,
              rect.height >= DashboardMetrics.minimumContentSize.height
        else { return nil }
        return rect
    }

    /// The screen the stored frame actually overlaps. Nil when the display it was on has
    /// been unplugged, which is the case that would otherwise open the window nowhere.
    private func screen(showing frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) }
    }

    // MARK: Geometry

    private func fits(_ size: CGSize, on screen: NSScreen?) -> Bool {
        guard let usable = usableContentSize(on: screen) else { return true }
        return size.width <= usable.width && size.height <= usable.height
    }

    /// Height is clamped to the screen and content floor. Width is invariant.
    private func fitted(_ size: CGSize, on screen: NSScreen?) -> CGSize {
        let floor = DashboardMetrics.minimumContentSize
        guard let usable = usableContentSize(on: screen) else {
            return CGSize(width: DashboardMetrics.fixedContentWidth, height: size.height)
        }
        return CGSize(width: DashboardMetrics.fixedContentWidth,
                      height: max(floor.height, min(size.height, usable.height)))
    }

    /// How much *content* fits on screen. Compared in content terms, not frame terms,
    /// because the title bar eats height a preset's height does not account for.
    private func usableContentSize(on screen: NSScreen?) -> CGSize? {
        guard let window, let screen else { return nil }
        return window.contentRect(forFrameRect: screen.visibleFrame).size
    }

    /// Slides a frame back inside the visible area without resizing it, so applying a
    /// preset near the screen edge cannot push the title bar under the menu bar.
    private func nudgedOnScreen(_ frame: CGRect, on screen: NSScreen?) -> CGRect {
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.origin.x = min(max(result.minX, visible.minX), max(visible.minX, visible.maxX - result.width))
        result.origin.y = min(max(result.minY, visible.minY), max(visible.minY, visible.maxY - result.height))
        return result
    }
}

// MARK: - Window access

/// Hands the real `NSWindow` to a closure once the hosting view is installed in one.
///
/// `NSViewRepresentable` rather than `NSApp.windows.first`: this app will gain a
/// Settings scene eventually, and picking a window out of a global list guesses at
/// which one the view belongs to.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Probe(onResolve: onResolve) }
    func updateNSView(_ nsView: NSView, context: Context) { }

    private final class Probe: NSView {
        private let onResolve: (NSWindow) -> Void

        init(onResolve: @escaping (NSWindow) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("WindowAccessor.Probe is not archived") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onResolve(window) }
        }
    }
}
