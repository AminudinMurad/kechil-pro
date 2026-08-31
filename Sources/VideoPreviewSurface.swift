import AVFoundation
import AppKit
import SwiftUI

/// A video surface without AVKit's automatic in-player control overlay. Playback
/// remains owned by the model and is driven exclusively by the inline transport bar.
struct VideoPreviewSurface: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> VideoPreviewSurfaceView {
        VideoPreviewSurfaceView()
    }

    func updateNSView(_ nsView: VideoPreviewSurfaceView, context: Context) {
        nsView.player = player
    }
}
final class VideoPreviewSurfaceView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        playerLayer.videoGravity = .resizeAspect
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override func makeBackingLayer() -> CALayer {
        AVPlayerLayer()
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
