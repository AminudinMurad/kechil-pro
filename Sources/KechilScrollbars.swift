import AppKit
import SwiftUI

/// A compact persistent scroller shared by every scrollable Kechil workspace.
///
/// SwiftUI does not expose macOS thumb width or colour, so a tiny representable locates
/// the backing `NSScrollView` and installs this scroller. The track stays transparent;
/// the thumb uses adaptive label colour and never depends on hover to become visible.
final class KechilScroller: NSScroller {
    /// Without this opt-in AppKit treats any NSScroller subclass as legacy-only,
    /// silently falls back to the wide system gutter, and can replace the custom
    /// scroller during layout. Kechil only overrides part drawing/hit-testing, so it
    /// satisfies AppKit's overlay compatibility contract.
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize,
                                      scrollerStyle: NSScroller.Style) -> CGFloat {
        12
    }

    /// AppKit can ignore a customised `knobProportion` while calculating its native
    /// drawing geometry. Return the fixed geometry itself so painting, hit-testing,
    /// and knob dragging all use the same ten-percent thumb.
    override func rect(for part: NSScroller.Part) -> NSRect {
        guard part == .knob else { return super.rect(for: part) }

        let naturalKnob = super.rect(for: .knob)
        guard !naturalKnob.isEmpty, super.knobProportion > 0,
              super.knobProportion < 1 else {
            return naturalKnob
        }

        let slot = super.rect(for: .knobSlot)
        return KechilScrollbarGeometry.thumbRect(
            in: slot,
            value: doubleValue,
            axis: bounds.height >= bounds.width ? .vertical : .horizontal)
    }

    override func testPart(_ point: NSPoint) -> NSScroller.Part {
        let knob = rect(for: .knob)
        if knob.insetBy(dx: -2, dy: -2).contains(point) {
            return .knob
        }
        if rect(for: .knobSlot).contains(point) {
            return .knobSlot
        }
        return .noPart
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Overlay scrollers do not need a permanent gutter or dark track.
    }

    override func drawKnob() {
        var knob = rect(for: .knob)
        guard !knob.isEmpty else { return }
        if bounds.width < bounds.height {
            knob = knob.insetBy(dx: 1.5, dy: 2)
        } else {
            knob = knob.insetBy(dx: 2, dy: 1.5)
        }
        let colour = NSColor.labelColor.withAlphaComponent(hitPart == .knob ? 0.72 : 0.52)
        colour.setFill()
        NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3).fill()
    }
}

private struct KechilScrollbarInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.installWhenReady()
    }

    final class ProbeView: NSView {
        private var preferredStyleObserver: NSObjectProtocol?
        private var installQueued = false
        private weak var installedScrollView: NSScrollView?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            preferredStyleObserver = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.installWhenReady()
            }
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            preferredStyleObserver = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.installWhenReady()
            }
        }

        deinit {
            if let preferredStyleObserver {
                NotificationCenter.default.removeObserver(preferredStyleObserver)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // The representable fills the SwiftUI ScrollView only so it can locate
            // the matching AppKit view. It must never intercept clicks or scrolling.
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if installedScrollView?.window !== window {
                installedScrollView = nil
            }
            installWhenReady()
            // SwiftUI can finish configuring its NSScrollView after the representable
            // first enters the window. These bounded follow-ups survive that initial
            // replacement without creating a polling loop.
            installAfter(0.05)
            installAfter(0.25)
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            installedScrollView = nil
            installWhenReady()
        }

        override func layout() {
            super.layout()
            // Layout is hot while scrolling, resizing and switching tools. Once the
            // matching scroll view is configured, revisiting the whole AppKit view
            // tree here only adds main-thread work and can trigger another layout via
            // `tile()`. A new superview/window or the system style notification clears
            // or explicitly rechecks the cached installation.
            if installedScrollView == nil {
                installWhenReady()
            }
        }

        func installWhenReady() {
            guard !installQueued else { return }
            installQueued = true
            DispatchQueue.main.async { [weak self] in
                self?.installQueued = false
                self?.install()
            }
        }

        private func installAfter(_ delay: TimeInterval) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.install()
            }
        }

        private func install() {
            guard let scrollView = targetScrollView() else { return }

            let verticalNeedsInstall = scrollView.hasVerticalScroller &&
                !(scrollView.verticalScroller is KechilScroller)
            let horizontalNeedsInstall = scrollView.hasHorizontalScroller &&
                !(scrollView.horizontalScroller is KechilScroller)
            let configurationChanged = scrollView.scrollerStyle != .legacy ||
                scrollView.autohidesScrollers || verticalNeedsInstall ||
                horizontalNeedsInstall

            installedScrollView = scrollView

            // Legacy style here means persistent, not visually wide: KechilScroller's
            // fixed 12pt width remains compact while AppKit no longer fades it out
            // until hover or active scrolling. Avoid assigning unchanged properties:
            // AppKit invalidates layout even when the incoming value is identical.
            if scrollView.scrollerStyle != .legacy {
                scrollView.scrollerStyle = .legacy
            }
            if scrollView.autohidesScrollers {
                scrollView.autohidesScrollers = false
            }

            if verticalNeedsInstall {
                let scroller = KechilScroller()
                scroller.controlSize = .small
                scrollView.verticalScroller = scroller
            }
            if horizontalNeedsInstall {
                let scroller = KechilScroller()
                scroller.controlSize = .small
                scrollView.horizontalScroller = scroller
            }

            // A settled installation must be a complete no-op. Forcing display or
            // tiling on every SwiftUI update made route switches and scrolling laggy.
            guard configurationChanged else { return }

            for scroller in [scrollView.verticalScroller, scrollView.horizontalScroller]
                .compactMap({ $0 }) {
                scroller.isHidden = false
                scroller.alphaValue = 1
                scroller.needsDisplay = true
            }

            scrollView.tile()
            scrollView.needsDisplay = true
        }

        
        /// A background attached to a SwiftUI `ScrollView` is hosted beside the
        /// underlying NSScrollView, not inside its document view, so
        /// `enclosingScrollView` is normally nil. Match the probe's window-space
        /// centre to the smallest visible NSScrollView underneath it; this also picks
        /// the inner tool/inspector scroller correctly when scroll views are nested.
        private func targetScrollView() -> NSScrollView? {
            if let enclosingScrollView { return enclosingScrollView }
            guard let window, let root = window.contentView else { return nil }

            let point = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            if let installedScrollView,
               installedScrollView.window === window,
               !installedScrollView.isHidden,
               installedScrollView.convert(installedScrollView.bounds, to: nil).contains(point) {
                return installedScrollView
            }
            return allDescendants(of: root)
                .compactMap { $0 as? NSScrollView }
                .filter { scrollView in
                    guard !scrollView.isHidden, scrollView.window === window else { return false }
                    let frameInWindow = scrollView.convert(scrollView.bounds, to: nil)
                    return frameInWindow.contains(point)
                }
                .min { lhs, rhs in
                    lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height
                }
        }

        private func allDescendants(of view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(allDescendants)
        }
    }
}

extension View {
    /// Installs the compact adaptive Kechil scrollbar on the nearest SwiftUI ScrollView.
    func kechilScrollbars() -> some View {
        background(KechilScrollbarInstaller().allowsHitTesting(false))
    }
}
