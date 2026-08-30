import SwiftUI

/// Familiar dual-handle video trim control. The playhead can set either marker and
/// the same handles can be dragged directly. Boundary handles represent no marker,
/// which keeps the default export range equal to the complete source.
struct VideoTrimRangeControl: View {
    let duration: Double
    @Binding var startSeconds: Double
    @Binding var endSeconds: Double?
    @Binding var playheadSeconds: Double
    let refreshPreview: () -> Void

    private let horizontalInset: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(rangeTitle, systemImage: isFullSource ? "arrow.left.and.right" : "scissors")
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer()
                Text("\(Self.time(startSeconds)) – \(Self.time(effectiveEnd))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let width = max(1, geometry.size.width - horizontalInset * 2)
                let startX = horizontalInset + width * CGFloat(startSeconds / duration)
                let endX = horizontalInset + width * CGFloat(effectiveEnd / duration)
                let playheadX = horizontalInset + width * CGFloat(clampedPlayhead / duration)

                ZStack(alignment: .leading) {
                    Capsule().fill(Color(nsColor: .separatorColor).opacity(0.7))
                        .frame(width: width, height: 8)
                        .offset(x: horizontalInset, y: 19)
                    Capsule().fill(Color.accentColor.opacity(0.48))
                        .frame(width: max(2, endX - startX), height: 8)
                        .offset(x: startX, y: 19)

                    Rectangle().fill(Color.orange.opacity(0.9))
                        .frame(width: 1.5, height: 27)
                        .position(x: playheadX, y: 23)

                    marker("IN", systemImage: "chevron.right", x: startX, isStart: true,
                           geometryWidth: geometry.size.width)
                    marker("OUT", systemImage: "chevron.left", x: endX, isStart: false,
                           geometryWidth: geometry.size.width)
                }
                .coordinateSpace(name: "trimTimeline")
            }
            .frame(height: 46)

            HStack(spacing: 6) {
                Button("Set In") { setIn(at: playheadSeconds) }
                Button("Set Out") { setOut(at: playheadSeconds) }
                Spacer()
                Button("Clear markers", action: clearMarkers)
                    .disabled(isFullSource)
            }
            .controlSize(.small)

            Text(isFullSource
                 ? "No trim markers set. Export uses the full source duration."
                 : "Drag the In and Out handles, or set either marker at the orange playhead.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }

    private func marker(_ label: String, systemImage: String, x: CGFloat,
                        isStart: Bool, geometryWidth: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color.accentColor, in: Capsule())
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.accentColor)
            RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor)
                .frame(width: 4, height: 15)
        }
        .frame(width: 34, height: 45)
        .contentShape(Rectangle())
        .position(x: min(max(17, x), max(17, geometryWidth - 17)), y: 22)
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trimTimeline"))
            .onChanged { drag in
                let usable = max(1, geometryWidth - horizontalInset * 2)
                let seconds = Double((drag.location.x - horizontalInset) / usable) * duration
                if isStart { updateIn(seconds) } else { updateOut(seconds) }
            }
            .onEnded { _ in refreshPreview() })
        .accessibilityLabel("\(label) trim marker")
        .accessibilityValue(Self.time(isStart ? startSeconds : effectiveEnd))
    }

    private var effectiveEnd: Double {
        VideoTrimRangePolicy.effectiveEnd(endSeconds, duration: duration)
    }

    private var clampedPlayhead: Double { min(max(0, playheadSeconds), duration) }
    private var isFullSource: Bool {
        VideoTrimRangePolicy.isFullSource(start: startSeconds, end: endSeconds)
    }
    private var rangeTitle: String { isFullSource ? "Full source" : "Trimmed range" }

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
