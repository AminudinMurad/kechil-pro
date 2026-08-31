import Foundation
import SwiftUI

/// The editor-style trim surface used directly below the video preview. It keeps a
/// scrubbable preview playhead separate from the two trim boundaries: clicking or
/// dragging the track previews a frame, while the blue In/Out handles change what
/// is exported. Boundary handles at the source edges still mean the full source.
struct VideoTrimRangeControl: View {
    let duration: Double
    @Binding var startSeconds: Double
    @Binding var endSeconds: Double?
    @Binding var playheadSeconds: Double
    let refreshPreview: () -> Void
    var compact = false

    private enum Boundary: Equatable {
        case start
        case end

        var label: String { self == .start ? "IN" : "OUT" }
        var accessibilityLabel: String { self == .start ? "Trim start" : "Trim end" }
        var systemImage: String { self == .start ? "chevron.left" : "chevron.right" }
        var help: String {
            self == .start
                ? "Drag to choose where the exported clip begins"
                : "Drag to choose where the exported clip ends"
        }
    }

    private var horizontalInset: CGFloat { compact ? 18 : 24 }
    private var timelineHeight: CGFloat { compact ? 54 : 72 }
    private var timelineCenter: CGFloat { compact ? 23 : 30 }
    @State private var activeHandle: Boundary?
    @State private var isScrubbing = false
    @State private var lastPreviewRefresh = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            header
            timeline
            timingSummary
            controls
            Text(helperText)
                .font(.system(size: compact ? 8.5 : 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(compact ? 1 : nil)
                .truncationMode(.tail)
        }
        .padding(compact ? 7 : 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label("Trim", systemImage: isFullSource ? "arrow.left.and.right" : "scissors")
                .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
            Text(rangeTitle)
                .font(.system(size: compact ? 9 : 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("\(Self.time(startSeconds)) – \(Self.time(effectiveEnd))")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var timeline: some View {
        GeometryReader { geometry in
            let timelineWidth = geometry.size.width
            let usableWidth = max(1, timelineWidth - horizontalInset * 2)
            let startX = position(for: startSeconds, usableWidth: usableWidth)
            let endX = position(for: effectiveEnd, usableWidth: usableWidth)
            let playheadX = position(for: clampedPlayhead, usableWidth: usableWidth)

            ZStack(alignment: .topLeading) {
                ruler(usableWidth: usableWidth)

                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .separatorColor).opacity(0.62))
                    .frame(width: usableWidth, height: compact ? 8 : 10)
                    .position(x: horizontalInset + usableWidth / 2, y: timelineCenter)
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.72))
                    .frame(width: max(2, endX - startX), height: compact ? 8 : 10)
                    .position(x: startX + max(2, endX - startX) / 2, y: timelineCenter)
                    .allowsHitTesting(false)

                scrubTarget(timelineWidth: timelineWidth, usableWidth: usableWidth)

                playhead(x: playheadX)
                    .zIndex(1)

                handle(.start, x: startX, timelineWidth: timelineWidth,
                       usableWidth: usableWidth)
                    .zIndex(2)
                handle(.end, x: endX, timelineWidth: timelineWidth,
                       usableWidth: usableWidth)
                    .zIndex(2)
            }
            .coordinateSpace(name: "videoTrimTimeline")
        }
        .frame(height: timelineHeight)
    }

    private var timingSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Self.time(startSeconds))
                .font(.system(size: compact ? 9 : 10, design: .monospaced))
                .foregroundStyle(Color.accentColor)
            Spacer()
            Text("Preview \(Self.time(clampedPlayhead))")
                .font(.system(size: compact ? 8.5 : 9.5, design: .monospaced))
                .foregroundStyle(Color.orange)
            Spacer()
            Text(Self.time(effectiveEnd))
                .font(.system(size: compact ? 9 : 10, design: .monospaced))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button { setIn(at: playheadSeconds) } label: {
                Label("Set start", systemImage: "arrow.backward.to.line")
            }
            .help("Set the trim start at the current preview position")

            Button { setOut(at: playheadSeconds) } label: {
                Label("Set end", systemImage: "arrow.forward.to.line")
            }
            .help("Set the trim end at the current preview position")

            Spacer(minLength: 4)

            Button(action: clearMarkers) {
                Label("Clear", systemImage: "arrow.counterclockwise")
            }
            .help("Reset the trim range to the complete source")
            .disabled(isFullSource)
        }
        .controlSize(compact ? .mini : .small)
        .font(.system(size: compact ? 9.5 : 11))
    }

    private func ruler(usableWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...16, id: \.self) { tick in
                let fraction = CGFloat(tick) / 16
                let isMajor = tick.isMultiple(of: 4)
                Rectangle()
                    .fill(Color.secondary.opacity(isMajor ? 0.55 : 0.28))
                    .frame(width: 1, height: isMajor ? 7 : 4)
                    .position(x: horizontalInset + usableWidth * fraction,
                              y: isMajor ? 4 : 5.5)
                    .allowsHitTesting(false)
            }
        }
    }

    private func scrubTarget(timelineWidth: CGFloat, usableWidth: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: usableWidth, height: compact ? 42 : 50)
            .position(x: timelineWidth / 2, y: timelineCenter)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("videoTrimTimeline"))
                    .onChanged { drag in
                        isScrubbing = true
                        updatePlayhead(at: drag.location.x, usableWidth: usableWidth)
                        refreshPreviewWhileInteracting()
                    }
                    .onEnded { _ in
                        isScrubbing = false
                        lastPreviewRefresh = 0
                        refreshPreview()
                    }
            )
            .help("Click or drag to preview a different video frame")
            .accessibilityLabel("Video preview position")
            .accessibilityValue(Self.time(clampedPlayhead))
            .accessibilityHint("Drag to scrub the preview without changing the trim range")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    nudgePlayhead(by: 0.1)
                case .decrement:
                    nudgePlayhead(by: -0.1)
                @unknown default:
                    break
                }
            }
    }

    private func handle(_ boundary: Boundary, x: CGFloat, timelineWidth: CGFloat,
                        usableWidth: CGFloat) -> some View {
        let isActive = activeHandle == boundary
        let handleX = min(max(22, x), max(22, timelineWidth - 22))

        return VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor)
                .frame(width: compact ? 14 : 16, height: compact ? 28 : 34)
                .overlay {
                    Image(systemName: boundary.systemImage)
                        .font(.system(size: compact ? 7.5 : 8.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            Text(boundary.label)
                .font(.system(size: compact ? 7 : 7.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, compact ? 4 : 5)
                .padding(.vertical, compact ? 1 : 2)
                .background(Color.accentColor, in: Capsule())
        }
        .frame(width: 44, height: timelineHeight)
        .contentShape(Rectangle())
        .position(x: handleX, y: timelineHeight / 2)
        .scaleEffect(isActive ? 1.06 : 1)
        .shadow(color: isActive ? Color.accentColor.opacity(0.35) : .clear,
                radius: 4, y: 1)
        .animation(.easeOut(duration: 0.12), value: isActive)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("videoTrimTimeline"))
                .onChanged { drag in
                    activeHandle = boundary
                    let seconds = seconds(at: drag.location.x, usableWidth: usableWidth)
                    if boundary == .start { updateIn(seconds) } else { updateOut(seconds) }
                    refreshPreviewWhileInteracting()
                }
                .onEnded { _ in
                    activeHandle = nil
                    lastPreviewRefresh = 0
                    refreshPreview()
                }
        )
        .help(boundary.help)
        .accessibilityLabel(boundary.accessibilityLabel)
        .accessibilityValue(Self.time(boundary == .start ? startSeconds : effectiveEnd))
        .accessibilityHint(boundary.help)
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 0.1 : -0.1
            if boundary == .start {
                updateIn(startSeconds + delta)
            } else {
                updateOut(effectiveEnd + delta)
            }
            refreshPreview()
        }
    }

    private func playhead(x: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Circle()
                .fill(Color.orange)
                .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                .offset(y: compact ? 9 : 12)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.orange.opacity(0.95))
                .frame(width: 2, height: compact ? 28 : 38)
                .offset(y: compact ? 14 : 18)
        }
        .frame(width: 14, height: timelineHeight, alignment: .top)
        .position(x: x, y: timelineHeight / 2)
        .scaleEffect(isScrubbing ? 1.12 : 1)
        .animation(.easeOut(duration: 0.12), value: isScrubbing)
        .allowsHitTesting(false)
    }

    private var effectiveEnd: Double {
        VideoTrimRangePolicy.effectiveEnd(endSeconds, duration: duration)
    }

    private var clampedPlayhead: Double { min(max(0, playheadSeconds), duration) }
    private var isFullSource: Bool {
        VideoTrimRangePolicy.isFullSource(start: startSeconds, end: endSeconds)
    }
    private var rangeTitle: String { isFullSource ? "Full source" : "Selected range" }
    private var helperText: String {
        if compact {
            return isFullSource
                ? "Drag to preview; set In or Out to trim."
                : "Drag the blue In and Out handles to trim."
        }
        return isFullSource
            ? "Drag the timeline to preview a frame, then set a start or end. Export uses the full source."
            : "Drag the blue In and Out handles to trim, or move the playhead and set either boundary."
    }

    private func position(for seconds: Double, usableWidth: CGFloat) -> CGFloat {
        let fraction = CGFloat(min(max(0, seconds), duration) / duration)
        return horizontalInset + usableWidth * fraction
    }

    private func seconds(at x: CGFloat, usableWidth: CGFloat) -> Double {
        let fraction = min(max((x - horizontalInset) / usableWidth, 0), 1)
        return Double(fraction) * duration
    }

    private func updatePlayhead(at x: CGFloat, usableWidth: CGFloat) {
        playheadSeconds = seconds(at: x, usableWidth: usableWidth)
    }

    private func nudgePlayhead(by delta: Double) {
        playheadSeconds = min(max(0, playheadSeconds + delta), duration)
        refreshPreview()
    }

    private func refreshPreviewWhileInteracting() {
        // Pointer drags emit many events per second. Limiting preview work while a
        // gesture is active keeps both the range and the preview responsive.
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastPreviewRefresh >= 0.1 else { return }
        lastPreviewRefresh = now
        refreshPreview()
    }

    private func updateIn(_ proposed: Double) {
        startSeconds = VideoTrimRangePolicy.start(proposed: proposed, duration: duration,
                                                  end: endSeconds)
        playheadSeconds = startSeconds
    }

    private func updateOut(_ proposed: Double) {
        endSeconds = VideoTrimRangePolicy.end(proposed: proposed, duration: duration,
                                              start: startSeconds)
        playheadSeconds = effectiveEnd
    }

    private func setIn(at seconds: Double) { updateIn(seconds); refreshPreview() }
    private func setOut(at seconds: Double) { updateOut(seconds); refreshPreview() }

    private func clearMarkers() {
        startSeconds = 0
        endSeconds = nil
        playheadSeconds = min(playheadSeconds, duration)
        refreshPreview()
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let milliseconds = Int((seconds * 1_000).rounded())
        let totalSeconds = milliseconds / 1_000
        return String(format: "%d:%02d.%03d", totalSeconds / 60,
                      totalSeconds % 60, milliseconds % 1_000)
    }
}
