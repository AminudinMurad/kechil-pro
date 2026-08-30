# Kechil PRO media feature implementation plan

> Implementation status (2026-08-30): the six-route architecture, video Clean, video
> Optimize, shared image/video Watermark, live previews and automated real-pipeline
> fixture are implemented. See `docs/DEVELOPMENT_HANDOFF.md` for exact shipped behavior,
> verification and intentional limits. App bundle/DMG creation and manual rendered UI
> QA were not performed in this pass.

Status: implementation handoff and design specification. This document describes the
work required; it does not itself enable video processing and it does not authorize a
build or a version/build-number change.

## 1. Product decision

Kechil PRO will have three primary tools. Every tool has two explicit media modes:

```text
CLEAN
  Images
  Videos

OPTIMIZE
  Images
  Videos

WATERMARK
  Images
  Videos
```

The six routes are separate workspaces, not one mixed queue with a hidden media flag.
Switching a route changes the accepted file types, settings, queue, preview, output
extension and status language. A queue never contains both an image and a video, and a
video operation never silently falls back to an image operation.

The existing image workflows remain the reference behaviour:

- Clean removes supported image metadata and verifies the result.
- Optimize currently crops, resizes, converts and removes metadata from image outputs.
- Watermark currently applies a text or logo watermark while using the Optimize image
  renderer, but has no live preview. The preview work in this plan is a required fix,
  not an optional enhancement.

Video processing must be local, sandboxed and offline. Use the macOS media frameworks
already available in the deployment target; do not add a command-line media dependency,
network service, telemetry, or an external upload path.

## 2. Non-negotiable product and engineering rules

1. Keep `CFBundleVersion` at `1` unless the owner explicitly instructs otherwise.
   Feature work, test builds and DMG rebuilds do not imply a build-number increment.
2. Do not build or package while implementing this plan unless a separate instruction
   explicitly requests it. `tools/check.sh` is the source/test gate; a DMG is a later
   release action.
3. Never modify the source file in place. All operations write a new temporary output,
   verify it, and only then expose it to Save or Save All.
4. Never claim that Clean is lossless unless the output was proven to preserve the media
   samples/frames. Container rewriting, remuxing and re-encoding are distinct outcomes
   and must be labelled separately in the UI.
5. Never claim that metadata is gone based only on an export API returning success.
   Re-open and probe the output. Unknown or unverified metadata produces a partial or
   warning state, never a green clean state.
6. Keep processing off the main actor. The UI must remain usable while a large video is
   being analysed, rendered or written.
7. Preserve audio, colour, orientation, timing and track structure by default. A setting
   that intentionally changes one of these must be visible and reflected in the output
   report.
8. Use system frameworks only: AVFoundation, Core Media, Core Video, VideoToolbox,
   Core Image, Core Graphics, Core Animation, AppKit and SwiftUI as needed. Do not
   assume `ffmpeg` exists on the user's Mac.
9. Keep the implementation vendor-neutral. Do not add third-party assistant branding,
   attribution trailers, or hidden provenance about the implementation to source,
   UI, documentation or generated assets.
10. Any unsupported container, codec, track, colour mode or metadata carrier must be
    reported with an actionable explanation and leave the original untouched.

## 3. Current repository baseline

The next agent should read these files before changing code:

| File | Current responsibility | Required direction |
| --- | --- | --- |
| `Sources/ContentView.swift` | Window shell, route switch, global drop handling, header actions | Route by `ToolRoute`; keep six queues independent; make Add/Drop media-aware. |
| `Sources/ToolSidebar.swift` | Three category groups and image task rows | Replace task list with the six explicit tool/media routes. |
| `Sources/ToolTabStrip.swift` | Legacy top-tool enum/strip; strip is no longer in the shell | Retain only if compatibility is useful, or remove after all references are gone. |
| `Sources/ScrubModel.swift` | Image Clean queue, metadata scan, image thumbnails, save | Preserve as the image Clean implementation or rename behind a compatibility type; extract shared queue/save helpers. |
| `Sources/MetadataStripper.swift` | Byte-level JPEG/PNG/WebP image metadata removal | Do not make it parse video; add a separate video metadata path. |
| `Sources/ImageIOStripper.swift` | ImageIO fallback for HEIC/TIFF/AVIF/GIF/BMP | Keep image-only and preserve its lossless/re-encoded reporting. |
| `Sources/TransformModel.swift` | Image Optimize model plus optional watermark settings, in-memory output `Data` | Split image Optimize and image Watermark settings; video jobs must use temporary URLs, not `Data`. |
| `Sources/TransformPipeline.swift` | Image crop/resize/encode and watermark drawing | Extract a shared watermark layout/rendering layer and a preview entry point. |
| `Sources/TransformToolView.swift` | Image Optimize controls and queue | Add an image preview/selected-item detail without changing current image output semantics. |
| `Sources/WatermarkToolView.swift` | Image watermark controls and queue | Add live preview, direct placement feedback, stale-preview handling and media-neutral labels. |
| `Sources/InspectorPanel.swift` | Image Clean detail/thumbnail/findings | Generalise to a media inspector, with a video poster/player and track/metadata details. |
| `Sources/DashboardHeader.swift` | Image-only Clean KPI tiles and metadata chart | Make labels/media counts dynamic; use a separate video summary model where the metrics differ. |
| `Sources/AppSettings.swift` | Security-scoped default image save folder | Rename the preference/UI to default save folder and use it for all six routes. |
| `Sources/App.swift` | `WindowGroup`, fixed-width dashboard commands | Keep macOS 13 compatibility and fixed 940-point content width. |
| `tools/build-app.sh` | Direct `swiftc` build with AppKit/ImageIO | Add the required media framework link flags. |
| `tools/check.sh` | Type check, deterministic image tests, identity/icon checks | Add media model/pipeline checks without requiring a network or `ffmpeg`. |
| `App/Info.plist` | Image document types, version `1.0.0`, build `1` | Add supported movie UTIs; leave version and build unchanged. |
| `App/KechilPRO.entitlements` | App Sandbox and user-selected read/write only | Keep network entitlements absent. |

Current constraints that affect the design:

- The deployment target is macOS 13.0 and the app is compiled from `Sources/*.swift`,
  not an Xcode project.
- The content width is fixed at 940 points and the window can resize vertically only.
- The existing sidebar is 160 points wide. A six-route hierarchy will need a slightly
  wider, still fixed sidebar so labels do not truncate.
- Image Clean intentionally keeps decoded pixel identity where possible. Optimize and
  Watermark intentionally re-render pixels and remove metadata from their outputs.
- The existing image models process one item at a time and publish progress/status on
  the main actor. Video work should follow that bounded-memory rule.
- Image outputs are currently held as `Data` until saving. This is acceptable for small
  rasters but is not acceptable for multi-hundred-megabyte videos.

## 4. Information architecture and route contract

### 4.1 Route types

Introduce a small, stable routing model. Keep implementation names independent from
display copy:

```swift
enum MediaKind: String, CaseIterable, Hashable {
    case image
    case video
}

enum KechilTool: String, CaseIterable, Hashable {
    case clean
    case optimize
    case watermark
}

struct ToolRoute: Hashable, Identifiable {
    let tool: KechilTool
    let media: MediaKind

    var id: String { "\(tool.rawValue).\(media.rawValue)" }
}
```

`ToolRoute` is the single source of truth for:

- sidebar selection and selected content;
- the media type accepted by Open/Drop;
- the model/queue used by the route;
- header title and Add button label;
- output filename suffix and extension;
- accessibility labels and empty-state copy.

Do not use a boolean such as `isVideo` scattered through views. A route switch should
be exhaustive, so adding a new mode cannot silently use image behaviour.

### 4.2 Sidebar

Use one fixed sidebar, approximately 184–192 points wide, with three disclosure groups.
Each group has a tool icon, a clear uppercase section title and two rows:

```text
TOOLS

  CLEAN
    Images       3
    Videos       0

  OPTIMIZE
    Images       2
    Videos       1

  WATERMARK
    Images       0
    Videos       0
```

The number is an optional in-memory queued-item badge; it is not persisted history. A
selected row uses the existing accent-tinted rounded background and a text/icon state,
not colour alone. A route with active processing shows a small progress glyph or “…”
state, but remains selectable so the user can inspect another queue.

Do not show “coming soon” after a route is implemented. Before implementation, a
disabled row may say “Not available yet” and must explain why in its help text. Once the
video model is live, the row must accept files and show its real empty/loading/error
states.

### 4.3 Mode control inside the workspace

The selected route is also visible at the top of each workspace as a compact segmented
control:

```text
Clean                         [ Images ] [ Videos ]
Remove metadata from selected media locally.
```

The control is synchronised with the sidebar. Its purpose is discoverability and fast
keyboard switching; it does not create a second queue. Switching mode preserves the
other mode's in-memory queue and settings and never moves files between them.

### 4.4 Route-specific intake

| Route | Open/drop label | Accepted inputs | Output default |
| --- | --- | --- | --- |
| Clean · Images | “Add Images…” | Current image set: JPEG, PNG, WebP, HEIC/HEIF, TIFF, GIF, BMP, AVIF, DNG | Same extension with `-clean` suffix |
| Clean · Videos | “Add Videos…” | `.mov`, `.mp4`, `.m4v` and their public movie UTIs | Same container where safe, otherwise an explicitly selected fallback |
| Optimize · Images | “Add Images…” | Current image set | WebP, as today |
| Optimize · Videos | “Add Videos…” | Supported movie inputs | MP4/H.264/AAC Balanced preset |
| Watermark · Images | “Add Images…” | Current image set | Same selected image output format, `-watermarked` suffix |
| Watermark · Videos | “Add Videos…” | Supported movie inputs | MP4/H.264/AAC, static watermark across the full duration |

When a drop contains a mixture, accept only the current route's type and show one
non-blocking banner: “3 videos skipped — this workspace accepts images.” Include a
“Switch to Videos” action when the skipped type is supported. Never route files based on
their extension alone; use UTType and an AVAsset/image probe.

## 5. Shared media data and job lifecycle

### 5.1 Asset descriptor

Add a media-neutral descriptor populated during analysis:

```swift
struct MediaAssetDescriptor: Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL
    let kind: MediaKind
    let fileSize: Int64
    let contentTypeIdentifier: String?
    let displayWidth: Int?
    let displayHeight: Int?
    let duration: CMTime?
    let frameRate: Double?
    let videoCodec: String?
    let audioCodec: String?
    let hasAudio: Bool
    let isHDR: Bool
    let preferredTransform: CGAffineTransform?
}
```

Do not make the descriptor hold decoded frames or full video data. Keep URLs and small
metadata values only. For security-scoped URLs, retain access for the operation's
duration and release it in a `defer` block.

### 5.2 Job states

Use one shared state vocabulary so the six workspaces behave consistently:

```text
queued → analysing → ready
ready → processing → completed
processing → cancelling → cancelled
analysing/processing → failed
completed → saved
```

Each item exposes:

- phase (`Analysing`, `Reading`, `Rendering`, `Writing`, `Verifying`, `Saving`);
- fraction in `0...1` when measurable;
- a short user-facing status;
- an actionable error code and detail;
- output URL (temporary until saved), output size and output descriptor;
- verification result and whether frames/pixels were re-encoded.

The queue model owns cancellation. A view must not cancel a task by dropping a SwiftUI
view or replacing a model. Switching routes leaves jobs alive and lets the sidebar show
their state.

### 5.3 Memory and temporary files

- Images may continue using in-memory `Data` for now, but the new shared save abstraction
  should also understand a temporary URL so the implementation can migrate large image
  outputs later.
- Videos always write to a unique file inside an app-container temporary directory.
  Create the directory on demand with restrictive permissions, keep it out of the user's
  selected save folder, and delete it on save, removal, cancellation, failure or app
  termination where possible.
- Never keep multiple full-resolution decoded video frames. Use a pixel-buffer pool and
  bounded one-job-at-a-time processing by default.
- Before starting an export, compare an estimated output size (or a conservative input
  multiple) with available volume capacity. If space is uncertain, warn before work and
  never delete the original to make room.

### 5.4 Shared save service

Extract `MediaSaveService` from the duplicate image model code. It must:

1. honour `AppSettings.defaultSaveDirectory` (rename the UI copy from “image save” to
   “default save folder”);
2. choose a collision-safe name without replacing an existing file;
3. atomically move a temporary output where possible, falling back to a verified copy;
4. preserve the output extension selected by the job;
5. update the row only after the destination exists and can be reopened;
6. report permission, disk-full and destination errors without losing the temporary
   output until the user dismisses or retries.

## 6. Clean · Videos implementation

### 6.1 Supported scope for the first release

Start with file-based QuickTime/MPEG-4 movies (`MOV`, `MP4`, `M4V`) containing one
primary video track and zero or more audio tracks. Support H.264 and HEVC video and
AAC/ALAC audio where the current Mac can decode/pass through them. Probe capability at
runtime instead of assuming every Mac has the same hardware encoder.

Initially reject or clearly mark as partial:

- MKV, AVI, WebM and transport streams;
- image sequences and live camera inputs;
- encrypted/DRM assets;
- assets with unsupported timed text, multi-angle, spatial/multiview or unusual media
  groups until they have a preservation test;
- malformed or truncated files.

The support matrix belongs in the UI's help text and in `README.md` after the feature is
implemented. Do not label a format supported merely because `AVURLAsset` can open it.

### 6.2 Video metadata inventory

Create `VideoMetadataProbe.swift`. It must inspect, at minimum:

- asset-level metadata from every available metadata format;
- metadata on every video and audio track;
- common QuickTime/MPEG-4 identifiers for title, author, description, location,
  creation date, software/encoder, camera/device, artwork, keywords and copyright;
- timed metadata tracks and chapter/marker metadata;
- known provenance/content-credential carriers and UUID boxes;
- whether the asset is fragmented, has edit lists, variable frame timing, HDR colour
  metadata, or non-default track transforms.

Represent findings as typed records, not only strings:

```swift
struct VideoMetadataFinding: Identifiable, Sendable {
    enum Scope { case file, track(Int), timedTrack(Int) }
    enum Category { case location, descriptive, device, timestamp, artwork,
                    timed, provenance, technical, unknown }
    let id: UUID
    let scope: Scope
    let category: Category
    let identifier: String
    let displayName: String
    let valueSummary: String
    let removable: Bool
}
```

Values shown in the inspector must be redacted or shortened where necessary; never log
full metadata values to a file. The user can select/copy a value from the inspector if
it is useful for diagnosis.

### 6.3 Cleaning strategy and honesty model

Implement `VideoCleanPipeline.swift` with an ordered strategy:

1. Open the URL as an `AVURLAsset` and asynchronously load the tracks, duration,
   metadata formats, natural/display size and preferred transforms.
2. Record the input descriptor and metadata report before touching the source.
3. Attempt a metadata-only/pass-through export to a temporary URL. Set output metadata
   explicitly to an empty allowlist, apply the export metadata filter where appropriate,
   and keep the original media tracks. Choose a file type compatible with the input.
4. Re-open the temporary URL. Verify it is playable, has the expected video/audio track
   count, has a duration within one source time scale tick, and has no removable finding
   or known unsupported carrier.
5. Compare sample/frame identity for fixtures and for the pass-through path's declared
   invariants. At minimum compare codec, dimensions, track transforms, sample count and
   presentation timestamps. If the path cannot prove frame identity, label it
   “Container cleaned; frame identity not verified”, not “lossless”.
6. If metadata remains, try a second sanitizer path. This may be an explicit ISO BMFF
   atom rewriter for supported MOV/MP4 structures or an AVAssetReader/AVAssetWriter
   remux. The rewriter must update offsets safely or preserve box size by neutralising
   private boxes; never delete bytes without accounting for chunk offsets.
7. If only a re-encode can remove the remaining carrier, expose the output as
   “Re-encoded to remove metadata” with a warning that video frames changed. Do not
   silently lower quality or alter audio.
8. Re-probe the final output and attach a verification report. If the report is partial
   or still contains a known carrier, show a warning and do not use the green clean
   badge.
9. Move/copy the verified output through `MediaSaveService` only when the user saves.

The result type should make the trade-off explicit:

```swift
enum VideoCleanVerification {
    case containerOnlyFramesUnverified
    case samplesPreserved
    case reencoded
    case partial(remaining: [VideoMetadataFinding])
}
```

The product promise is “remove the metadata we can identify and verify”, not “make a
video anonymous”. Pixel-embedded marks, steganography and content that is part of the
encoded picture are outside Clean.

### 6.4 Clean video UI

The workspace uses a left summary/list and a right inspector, matching the current image
Clean layout:

- KPI row: `Videos`, `With metadata`, `Total duration`, `Audio tracks`, `Cleaned`.
- Rows show poster frame, filename, duration, dimensions, codec and a status badge.
- The inspector shows a poster frame or a paused video preview, source facts, detected
  metadata by category, removed fields, verification state and Save Clean Copy.
- The primary status line says “Cleaning 2 of 8 videos…” and includes Cancel.
- A row with a re-encoded output uses an orange warning badge and a plain-language
  explanation; it must not be visually identical to pass-through cleaning.
- If a video has no supported removable metadata, say “No supported metadata found”; do
  not imply that every possible hidden signal was tested.

## 7. Optimize · Videos implementation

### 7.1 MVP controls

Keep the first version useful and explainable. The Video Optimize controls are grouped
as follows:

| Group | Controls | Default |
| --- | --- | --- |
| Trim | Start and end time, editable timecode fields, playhead buttons | Full duration |
| Frame | Crop preset (Original, 1:1, 4:5, 16:9, 9:16), focus X/Y, output resolution, no upscale | Original frame and size |
| Video | Codec (H.264; HEVC when supported), frame rate (Original/24/30/60 when valid), quality or target bitrate | H.264, Original FPS, Balanced |
| Audio | Keep audio, AAC bitrate (128/192/256 kbps), remove audio | Keep, 192 kbps |
| Output | MP4 or MOV, fast-start where supported, output suffix | MP4, `-optimized` |

Do not expose an exact target file-size field in the first video implementation. A video
size target needs a measured two-pass policy and can produce misleading promises when a
codec, VFR source or hardware encoder behaves differently. Add it later only after a
bounded bitrate-search contract and fixtures exist.

No keyframe animation, multi-clip editing, transitions, filters, frame interpolation or
audio mixing is in the MVP. These can be separate roadmap items.

### 7.2 Pipeline selection

Implement `VideoOptimizePipeline.swift` with a capability-driven decision tree:

1. If no frame, codec, audio or trim setting changes, use the clean/pass-through path
   and report that only the container/metadata was rewritten.
2. If the requested trim is compatible with a pass-through export, use
   `AVAssetExportSession`; otherwise use a sample reader/writer path and label the
   output re-encoded.
3. If crop, resize, frame-rate conversion or watermarking changes frames, read video
   samples through a video-composition output or track output, render into a bounded
   `CVPixelBufferPool`, and append them to an `AVAssetWriterInputPixelBufferAdaptor`.
4. Copy or re-encode audio according to the selected policy, preserving presentation
   timestamps and keeping A/V duration drift below the documented tolerance.
5. Set output colour properties from the source when the chosen codec supports them.
   Preserve HDR only when the pipeline can prove the transfer function, primaries,
   matrix and bit depth are retained; otherwise show an SDR conversion warning before
   starting.
6. Finish writing to a temporary URL, close all inputs, re-open the asset, and verify
   duration, dimensions, tracks, codec, audio presence, frame timing and metadata.

The implementation must use the source track's presentation timestamps rather than
assuming a constant frame rate. Variable-frame-rate input is a normal case. When the
user chooses a new frame rate, retime explicitly and describe the change in the output
details.

### 7.3 Quality and output semantics

Every completed row reports:

- source and output container/codec;
- source and output dimensions and display orientation;
- duration before and after;
- source and output file size and average bitrate where measurable;
- audio policy and track count;
- whether frames were re-encoded;
- whether metadata was stripped and verified.

“Smaller” is not a guarantee. If the selected settings produce a larger file, report the
actual result rather than silently changing quality. If the codec is unavailable, disable
the choice before processing and explain how to choose a supported one.

### 7.4 Optimize video preview

Optimize should show the selected source poster and a lightweight preview of the crop,
resize and trim settings. It is not necessary to export a complete preview movie for
every slider movement. Use `AVAssetImageGenerator` at the current playhead time, with a
debounced request and cancellation of stale requests. Show a badge when the poster is a
source frame rather than a final encoded frame.

The preview must respect the source's preferred transform, letterbox instead of stretch,
and show the crop rectangle and output dimensions. A “Preview frame” button can render a
single representative output frame using the same render function as export.

## 8. Watermark architecture for images and videos

### 8.1 Existing defect to fix first

`Sources/WatermarkToolView.swift` currently displays controls and a queue thumbnail but
does not show the watermark on a source image before export. `TransformPipeline` draws
the watermark only during processing. This leads to uncertain placement, scale and
rotation, especially on portrait images and transparent logos.

Do not fix this by re-running the full batch on every slider event. Build a shared
watermark renderer and a fast preview path.

### 8.2 Shared watermark configuration

Replace the current implicit image-only settings with a serialisable, media-neutral
configuration. Preserve old image preset values through a versioned migration:

```swift
struct RGBAColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

enum WatermarkSource: Codable, Equatable {
    case text(String)
    case logo // logo bytes are supplied for the current session, never stored in a preset
}

struct WatermarkConfiguration: Codable, Equatable {
    var source: WatermarkSource
    var textFontName: String
    var textPointScale: Double
    var textColor: RGBAColor
    var opacity: Double
    var rotationDegrees: Double
    var scalePercentOfShortestEdge: Double
    var anchor: WatermarkPosition // add Codable/Equatable conformance to the existing enum
    var marginPercent: Double
    var tiled: Bool
    var tileGapPercent: Double
    var shadowEnabled: Bool
    var shadowOpacity: Double
}
```

Keep logo bytes and logo file paths out of `UserDefaults`, as the existing preset
contract does. Add explicit `Codable`/`Equatable` conformances to the existing
`WatermarkPosition` enum (or use a raw-value bridge) so the configuration remains
portable across image and video routes.
Presets may store text, font, colours, placement, tile and output settings. A logo
preset must prompt the user to choose the logo again.

### 8.3 Watermark layout engine

Create `Sources/WatermarkLayoutEngine.swift`. It is the single source of truth for image
preview, image export, video preview and video export. Given a display canvas and a
configuration, it returns:

- the watermark's unrotated bounds;
- its anchor centre and safe margin;
- its rotation transform;
- tile centres/pattern bounds when tiled;
- the final alpha/colour and text metrics.

Use a normalised coordinate space first (`0...1` in displayed, orientation-corrected
coordinates), then map to pixels/points. Scale is based on the shortest displayed edge,
matching the current image pipeline. Clamp the anchor so the unrotated mark remains in
the safe area; account for rotated bounds when warning about clipping. Use one documented
coordinate convention (origin at top-left in UI space, converted once for Core Graphics)
so video overlays do not appear upside down.

### 8.4 Watermark renderer

Create `Sources/WatermarkRenderer.swift` with two entry points:

```swift
static func renderOverlay(configuration: WatermarkConfiguration,
                          canvasSize: CGSize,
                          logo: CGImage?) throws -> CGImage

static func drawOverlay(_ overlay: CGImage,
                        into context: CGContext,
                        at canvasRect: CGRect)
```

Render text with Core Text/Core Graphics into a transparent bitmap, not a separate
SwiftUI-only text view. Render a logo with its alpha intact. Apply opacity once at the
overlay level, preserve colour space, and use a subtle optional shadow/outline for text
legibility. Tiled mode must use a deterministic gap and phase so preview and export are
identical.

Image export should use the existing orientation-corrected `CIImage` path, then composite
the shared overlay, encode in the selected output format and run the existing metadata
stripper. The output report must say that pixels were re-rendered.

### 8.5 Image watermark preview UX

Make the right side of Watermark · Images a preview-first pane:

```text
┌──────────────────────────────┐
│ [Original] [Watermarked]     │  before/after toggle
│                              │
│        image canvas           │  fit, letterbox, checkerboard for alpha
│     watermark overlay         │  drag to reposition
│                              │
│  1 / 12       Reset placement │
└──────────────────────────────┘
┌──────────────────────────────┐
│ Queue                         │
│ selected file + status rows   │
└──────────────────────────────┘
```

Required behaviours:

- Selecting a queue row immediately updates the preview. If no row is selected, show a
  clear “Add images to preview” state.
- Changing text, logo, colour, opacity, scale, rotation, anchor or tile settings updates
  the preview after a short debounce (100–200 ms). Cancel any stale render.
- Allow direct drag placement on the canvas. The drag updates the normalised anchor and
  the placement picker updates with it. Provide Reset Placement.
- Keep a 3×3 anchor picker for keyboard and exact placement. A selected cell has a label,
  not only a coloured dot.
- Offer `Original`/`Watermarked` comparison and a zoom or “Fit” control. The comparison
  is a preview only and never alters the source.
- Show a small “Preview” vs “Export” note only when the preview is downscaled; the
  geometry, alpha and colour must still be generated by the same renderer.
- Disable Apply/Save when a logo source is required but missing, and say exactly what is
  missing beside the control.
- On queue changes, keep the current settings but select the newly added item only when
  there is no current selection; do not unexpectedly jump while the user is editing.

### 8.6 Video watermark export

Create `Sources/VideoWatermarkPipeline.swift`. MVP behaviour is a static watermark across
the selected time range; no keyframe animation. The pipeline should:

1. Probe the source and resolve its displayed orientation, render size, frame timing,
   colour properties and audio tracks.
2. Build one transparent watermark overlay bitmap at the output render size using the
   shared renderer. For a tiled mark, build a deterministic pattern layer rather than
   creating one layer per frame.
3. For a static overlay with compatible settings, use an `AVMutableVideoComposition` and
   `AVVideoCompositionCoreAnimationTool` with a video layer and watermark layer. Set the
   animation layer frame and transform from the orientation-corrected render size.
4. For crop/resize plus watermark, use the same video composition or a reader/writer
   compositor that applies the crop transform and overlay in one pass. Do not resize in
   the UI only and then export a different geometry.
5. Preserve audio samples unless the user selected Remove audio, and keep audio/video
   presentation timestamps aligned.
6. Export to a temporary MP4/MOV, explicitly clear output metadata, re-open and verify
   playability, track timing, overlay presence on representative frames and metadata
   removal.
7. Mark the result re-encoded. A watermarked video cannot honestly be called pass-through
   even if no resize or codec setting changed.

### 8.7 Video watermark preview UX

Use a native playback preview in the same right-hand pane:

- poster/preview area with letterboxed video and the same overlay layer;
- play/pause, current time, duration and a scrubber with timecode labels;
- mute/unmute and a frame-step button where supported;
- Original/Watermarked toggle;
- watermark drag placement while paused; dragging updates the normalised anchor;
- a “Preview frame” action that generates a frame at the current playhead through the
  shared renderer;
- an explicit “Watermark applies for the full selected range” label;
- trim handles or trim fields from Optimize reused only if the route shares a selected
  time range model, never by reaching into another route's queue.

For playback, use `AVPlayer`/`AVPlayerLayer` for time control and a transparent overlay
layer for the watermark. For still frame verification, use `AVAssetImageGenerator` or a
video-output pixel buffer. Keep the overlay geometry in the same displayed coordinate
space as export. When the player is replaced, remove observers and overlay layers to avoid
retaining old assets.

## 9. UI/UX handoff specification

### 9.1 Visual tokens

Stay consistent with the current Klik-inspired shell and fixed-width dashboard:

| Token | Recommendation | Use |
| --- | --- | --- |
| Content width | 940 pt fixed | All routes; only height resizes |
| Sidebar width | 184–192 pt fixed | Six explicit route rows |
| Outer content padding | 16 pt | Workspace panes and headers |
| Card radius | 9–12 pt | Settings, preview, queue cards |
| Control spacing | 8–12 pt | Labels, fields and grouped controls |
| Section spacing | 14–16 pt | Scrollable settings column |
| Primary heading | 15 pt semibold | `Clean`, `Optimize`, `Watermark` title |
| Body | 11.5–12.5 pt | Explanatory copy and row details |
| Caption | 10–10.5 pt | Codec, duration, helper/error detail |
| Accent | System accent blue | Selection and primary actions |
| Positive | Adaptive green | Verified/saved state only |
| Caution | Adaptive orange | Re-encoded, partial or HDR conversion |
| Critical | Adaptive red | Failed verification, permission or data-loss risk |

Do not increase the fixed width to fit a new control. Use vertical scrolling, compact
two-column fields where readable, and an inspector/preview pane. Verify every route at
the 13-inch M1 preset (`940 × 770`) as well as the taller presets.

### 9.2 Shared workspace anatomy

Every route should have the same mental model:

1. Workspace title and Image/Video mode control.
2. One-sentence scope/guarantee copy.
3. Settings or summary column on the left.
4. Preview/queue/inspector column on the right.
5. A bottom status line with progress, cancellation and actionable errors.
6. Add, Clear and Save actions with labels matching the selected media kind.

Use `ScrollView` only around content that can exceed the fixed height. Do not nest
independent vertical scroll views around the entire window and a queue unless the user
can still reach the Save action with a keyboard.

### 9.3 Clean route

Clean does not need a large settings panel. Use the freed space for the selected-media
inspector. The summary should distinguish:

- detected metadata;
- removed metadata;
- still-present/unknown metadata;
- pass-through/container-only result;
- re-encoded result;
- verification incomplete.

The “Clean All” action is disabled while the queue is empty or already processing. Clear
asks for confirmation only when there are unsaved outputs; an empty queue clears without
an alert.

### 9.4 Optimize route

Keep image controls familiar but rename the workspace consistently to Optimize. Add a
selected-output preview for image and video. Controls changed after a render show a
small “Settings changed — Apply to All to update the queue” indicator; never silently
re-render a large batch because a slider moved.

For videos, group controls in the order users make decisions: Trim → Frame → Video →
Audio → Output. Hide advanced codec fields until Custom is selected. Explain disabled
choices inline rather than presenting a picker that fails later.

### 9.5 Watermark route

Put the preview above the queue, not after a long list of controls. The controls should
be ordered: Source → Appearance → Placement → Output. “Apply Watermark to All” is the
primary action; it remains disabled until there is a source item and a valid text/logo.

Use the same labels for images and videos wherever the behaviour is the same. Add
“Static for full video” beside the video controls so the lack of keyframes is explicit.

### 9.6 Empty, loading, progress and error states

Define copy before implementation:

| State | Required UI |
| --- | --- |
| Empty | Media-specific icon, “Drop images/videos or choose files”, accepted extensions, privacy/offline note, Choose button |
| Analysing | Poster placeholder or skeleton, “Reading video details…”, per-item spinner |
| Processing | Phase label, `n of m`, determinate progress when possible, Cancel button |
| Completed | Output facts, verification badge, Save/Save All |
| Cancelled | “Cancelled; original is unchanged”, Retry action |
| Unsupported | Format/codec/track explanation, no output, “Choose another file” |
| Permission | Explain that the file/folder must be selected again; do not retry in a loop |
| Disk full | Preserve temp output if possible, show destination and required/available estimate |
| Verification partial | Orange warning, list what was checked and what was not |
| Output failure | Error detail, Retry, keep source untouched |

Never use a generic “Something went wrong” when the media framework supplies a useful
failure reason. Keep technical details expandable so the normal path remains readable.

### 9.7 Keyboard and accessibility

Implement and test these shortcuts in the active workspace:

- `⌘O`: open files for the current route;
- `⌘Return`: apply current settings to all queued items;
- `⌘S`: save selected output, or Save All when no single output is selected;
- `Space`: play/pause the selected video when focus is in the preview;
- Left/Right arrows: move the video playhead by one frame or a small time step;
- `Escape`: cancel an active export or close a transient error banner;
- `Delete`: remove selected queue item after the same unsaved-output confirmation used by
  the Clear action.

Every icon-only control needs a VoiceOver label and help text. Sliders expose their
current value and unit. The video scrubber exposes current time, duration and a value
that can be adjusted with arrows. Focus order is: route/mode → settings → preview
controls → queue → Save. Status changes announce through an accessible status element.
Do not use colour as the only signal for selected, warning, failed or verified states.
Respect Reduce Motion by removing animated preview transitions and use static state
changes instead.

## 10. File-level implementation sequence

The next agent should implement in this order. Each phase ends with the listed gate; do
not skip ahead when the gate fails.

### Phase 0 — contracts and capability spike

- [ ] Add `MediaKind`, `ToolRoute`, job-state and verification enums.
- [ ] Add a media capability probe that can distinguish the supported image set from
      MOV/MP4/M4V and reports the primary tracks without rendering.
- [ ] Confirm macOS 13 availability of the chosen AVFoundation concurrency/loading APIs.
- [ ] Add AVFoundation/CoreMedia/CoreVideo/VideoToolbox/QuartzCore/CoreImage framework
      flags to `tools/build-app.sh`; keep `tools/check.sh` type-checking every source.
- [ ] Add movie UTIs to `App/Info.plist` while keeping version `1.0.0` and build `1`.
- [ ] Record a small fixture matrix under `Tests/fixtures/` or generate deterministic
      fixtures with AVAssetWriter; do not rely on an installed `ffmpeg`.

Gate: source type-checks with warnings-as-errors, the current image checks remain green,
and a probe can explain why each fixture is supported or rejected.

### Phase 1 — six-route shell and queue isolation

- [ ] Rewrite `ToolSidebar.swift` around the six routes and add queue-count/progress
      badges.
- [ ] Update `ContentView.swift` to hold route-specific models and route file drops to
      the selected model only.
- [ ] Add the in-workspace Image/Video segmented control and dynamic Add labels.
- [ ] Extract `MediaSaveService`; update settings copy to “default save folder”.
- [ ] Add wrong-media drop feedback and unsaved-output confirmation on Clear.
- [ ] Keep video routes visibly disabled only until their real models are wired; do not
      leave a clickable placeholder that pretends to process files.

Gate: all six routes navigate correctly, image Clean/Optimize/Watermark behaviour is
unchanged, queues remain separate after switching, and the 940-point window has no
horizontal overflow at every dashboard preset.

### Phase 2 — video Clean

- [ ] Add `VideoMetadataProbe.swift`, typed findings and a media inspector.
- [ ] Add `VideoCleanItem`/`VideoCleanModel` with URL-backed outputs, cancellation and
      per-item progress.
- [ ] Implement the pass-through/export attempt, output re-probe and verification model.
- [ ] Implement the supported MOV/MP4 atom/remux fallback only after offset/edit-list
      invariants are covered by fixtures.
- [ ] Add video poster generation and a paused preview to the inspector.
- [ ] Add Save/Save All and collision-safe `-clean` names.
- [ ] Add clean-video copy that distinguishes samples preserved, container-only and
      re-encoded outcomes.

Gate: supported fixtures reopen, play and retain expected tracks/timing; removable
metadata is absent after verification; unsupported/residual cases are never reported as
fully clean; cancellation leaves no playable partial output and never changes the source.

### Phase 3 — video Optimize

- [ ] Add `VideoOptimizeSettings` with Codable defaults and validation.
- [ ] Add the trim/frame/video/audio/output controls and capability-driven disabled states.
- [ ] Implement the pass-through/export path for no-frame-change operations.
- [ ] Implement reader/writer + pixel-buffer-pool processing for crop/resize/codec/frame
      rate changes, preserving timestamps and audio policy.
- [ ] Add poster preview at the current trim/playhead position and a representative
      output-frame preview.
- [ ] Add output verification and human-readable result details.
- [ ] Defer target-size controls until a separate two-pass contract is approved.

Gate: output plays in AVFoundation and QuickTime, A/V sync is within the documented
tolerance, resolution/trim/codec settings are applied exactly, and no job exceeds the
bounded memory/cancellation contract.

### Phase 4 — shared watermark renderer and image preview

- [ ] Extract `WatermarkConfiguration`, `WatermarkLayoutEngine` and `WatermarkRenderer`.
- [ ] Add migration from `kechil.watermarkPresets.v1` to the new common preset schema;
      keep logo bytes out of persisted data.
- [ ] Replace the image watermark screen's queue-thumbnail-only layout with a selected
      source preview, before/after toggle, fit/zoom, drag placement and reset.
- [ ] Route every control change through a debounced preview task; do not process the
      whole batch on slider changes.
- [ ] Make image export call the shared renderer, then metadata-strip and verify output.
- [ ] Add pixel-level tests comparing a preview render with an exported image render for
      anchors, rotation, opacity, alpha logos, tile mode and EXIF orientation.

Gate: a user can see exactly where a mark will land before Apply; preview and export
geometry match within the defined pixel tolerance; portrait/landscape/transparent-logo
cases are correct; existing presets still load without logo bytes.

### Phase 5 — video Watermark

- [ ] Add `VideoWatermarkSettings` and a URL-backed `VideoWatermarkModel`.
- [ ] Add AVPlayer preview with a shared overlay, scrubber, Original/Watermarked toggle,
      frame preview and static-full-range explanation.
- [ ] Implement the Core Animation composition path and reader/writer fallback where
      crop/resize requires it.
- [ ] Preserve audio, timestamps and colour properties within the supported matrix.
- [ ] Strip and verify output metadata; always label frames as re-encoded.
- [ ] Add representative-frame overlay verification against the preview renderer.

Gate: the watermark is visible in the first, middle and last representative frames,
placement is stable through portrait/landscape and trim ranges, playback remains in sync,
and the saved file reopens with no supported removable metadata.

### Phase 6 — polish, accessibility, documentation and release readiness

- [ ] Replace image-only copy in shared headers, settings, empty states and docs with
      media-neutral copy.
- [ ] Add all keyboard shortcuts, VoiceOver labels, reduce-motion handling and dynamic
      type/minimum-scale checks.
- [ ] Test fixed-width layout at all five dashboard presets and both light/dark modes.
- [ ] Add performance checks for a long 4K file, a portrait phone video, VFR input, no
      audio, HDR input and a large batch.
- [ ] Update `README.md`, `docs/INSTALL.md`, `CHANGELOG.md` and `NOTICE.md` only after
      behaviour is implemented and verified.
- [ ] Run source checks and manual QA. Build and DMG packaging remain separate owner-
      requested actions; do not change build `1`.

Gate: the definition-of-done checklist in Section 13 is complete and every known
limitation is visible in the product copy.

## 11. Testing plan

The current project uses standalone Swift executables rather than an XCTest target. Add
deterministic checks in the same style and keep framework-dependent integration checks
separate from pure parsing tests.

### 11.1 Pure and deterministic tests

Add these test executables/files:

| Test | Coverage |
| --- | --- |
| `Tests/MediaRouteChecks.swift` | Six routes, display labels, accepted media routing and no cross-queue selection. |
| `Tests/VideoMetadataChecks.swift` | Typed findings, removable/technical distinction, track/timed metadata, unknown-carrier state. |
| `Tests/VideoContainerChecks.swift` | BMFF box sizes/offsets, edit lists, fragmented/non-fragmented decisions, safe neutralisation. |
| `Tests/VideoCleanChecks.swift` | Fixture output opens, tracks/timing preserved, metadata absent, verification state honest. |
| `Tests/VideoOptimizeChecks.swift` | Trim bounds, dimensions, crop focus, frame-rate policy, audio policy, monotonic PTS and duration tolerance. |
| `Tests/WatermarkRendererChecks.swift` | Normalised anchors, rotation bounds, opacity, text metrics, alpha logo, tile phase and orientation. |
| `Tests/WatermarkPreviewChecks.swift` | Preview bitmap and exported representative frame use the same layout/render result. |

Keep tests independent of wall-clock time, network, user home folders and installed
third-party tools. If a fixture must be encoded by a hardware codec, check in a small
fixture plus a hash and make the test explain when that codec is unavailable rather than
silently passing.

### 11.2 Fixture matrix

At minimum test:

- landscape H.264/AAC MP4;
- portrait H.264/AAC MOV with a non-identity preferred transform;
- HEVC/AAC MOV or MP4 when available;
- video with no audio;
- variable-frame-rate video;
- short video with metadata at file and track scope;
- timed metadata/chapter fixture;
- a fixture containing a known UUID/provenance box;
- malformed/truncated container;
- SDR and an HDR sample when the host can create one;
- long path, Unicode filename, read-only source and a destination collision;
- image fixtures covering EXIF orientation, alpha PNG, transparent logo, all nine anchors
  and tiled mode.

### 11.3 Verification invariants

For every video output, assert as applicable:

- output URL exists and is readable;
- AVAsset loads and has the expected track policy;
- duration and selected trim range are within tolerance;
- dimensions and display transform match settings;
- presentation timestamps are monotonic and A/V drift is bounded;
- output metadata report matches the route contract;
- temporary files are removed after save/cancel/failure;
- the source file's size and hash are unchanged;
- cancelled jobs never surface a partial output as Save-ready.

For watermark previews, compare the same representative frame rendered in preview and
export. Allow only a documented tolerance for colour-space/codec conversion; placement,
rotation, alpha and tile geometry must be exact.

### 11.4 Manual QA script

On macOS 13 or newer, execute this after automated checks:

1. Open each of the six sidebar routes and confirm the title, mode and Add label agree.
2. Drop an image into a video route and a video into an image route; confirm skip copy
   and Switch action, with no queue contamination.
3. Clean a MOV and MP4 with metadata, inspect the before/after findings, save, reopen in
   QuickTime and confirm the original remains unchanged.
4. Optimize a landscape and portrait video with trim, crop and resize; play both and
   check orientation, duration and audio sync.
5. Add a text watermark to an image, drag it to all nine anchors, rotate/tile it and
   compare preview against the saved output.
6. Add a transparent logo watermark to a portrait image and confirm alpha, safe margin
   and orientation.
7. Add a watermark to a video, scrub first/middle/last frames, play the preview, export
   and compare representative frames.
8. Cancel a long video during analysis and during writing; confirm no partial Save item.
9. Test Save All with a configured default folder and existing filename collisions.
10. Repeat critical checks in light/dark appearance, VoiceOver and reduced motion.

## 12. Risks and explicit decisions

| Risk | Decision/mitigation |
| --- | --- |
| Pass-through export leaves track/timed metadata | Re-open and probe; use a second sanitizer or report partial/re-encoded. Never assume success means clean. |
| Atom deletion shifts `stco`/`co64`/edit-list offsets | Preserve box size by neutralising private payloads or implement offset rewriting with fixtures before shipping. |
| Hardware encoder/preset differs by Mac | Query compatible presets and VideoToolbox support at runtime; disable unavailable options. |
| HDR is accidentally converted to SDR | Inspect colour attachments; preserve only when proven; otherwise warn before export. |
| Preferred transform causes sideways video or misplaced overlay | Resolve displayed coordinates once and feed the same transform to preview/compositor/export. |
| VFR timestamps drift after resize or trim | Carry CMSampleBuffer PTS/duration; never derive timing only from frame index. |
| AVAssetReader/Writer blocks or leaks | Process off-main, use bounded queues, cancel both reader and writer, and delete temp output in `defer`. |
| Preview and export watermark differ | One layout engine and one bitmap renderer; add representative-frame comparison tests. |
| Slider changes trigger expensive batch work | Preview only the selected item with debounce; require Apply to All for queue rendering. |
| Six routes make the fixed window crowded | Keep sidebar fixed at ~184–192 pt, use two-column settings and vertical scrolling, test the 13-inch preset first. |
| Old watermark presets lack logo bytes/new fields | Version the schema and migrate defaults; ask the user to choose the logo again. |
| Large output exhausts memory/disk | URL-backed video outputs, pixel-buffer pool, one active export, capacity check and cleanup. |
| Privacy promise is weakened by diagnostics | No network entitlement, no telemetry, no full-value metadata logging, and only user-selected file access. |

Out of scope for this plan: cloud processing, online update implementation, live camera
capture, multi-clip timelines, keyframed/animated watermarks, invisible watermark
detection/removal, arbitrary container support and exact video target-size search.

## 13. Definition of done

The feature is ready for owner review only when all of the following are true:

- [ ] Clean, Optimize and Watermark each expose distinct Images and Videos routes.
- [ ] No route can receive the wrong media kind without an explicit skip message.
- [ ] Image behaviour and existing deterministic image checks remain unchanged.
- [ ] Video Clean removes and verifies the supported metadata scope and distinguishes
      pass-through, unverified and re-encoded results.
- [ ] Video Optimize applies the documented trim/frame/codec/audio/output settings and
      verifies playable output, timing and track policy.
- [ ] Image Watermark has a live, selected-item preview with before/after, drag placement,
      nine anchors, reset and preview/export parity.
- [ ] Video Watermark has playback/scrubbing preview and a stable static overlay across
      the selected range; saved output matches representative preview frames.
- [ ] Watermarked image and video outputs remove supported metadata and say that frames/
      pixels were re-rendered.
- [ ] All six queues support progress, cancellation, retry, Save and Save All without
      retaining full video data in memory.
- [ ] Empty, loading, unsupported, permission, disk-full, partial-verification and
      cancellation states have deliberate copy and accessible labels.
- [ ] The UI fits the fixed 940-point width at every dashboard-height preset and remains
      usable with keyboard, VoiceOver, dark appearance and reduced motion.
- [ ] `tools/check.sh` passes, including all new deterministic checks, with warnings
      treated as errors.
- [ ] `App/Info.plist` still reports version `1.0.0` and build `1` unless separately
      instructed; no DMG is produced as part of feature implementation.
- [ ] README/install/changelog documentation describes actual supported formats and
      limitations, with no stale “coming soon” language for shipped routes.

## 14. Apple API references

Use the current macOS SDK declarations and availability annotations as the final source
of truth during implementation. These references explain the intended building blocks:

- [`AVAssetExportSession` metadata](https://developer.apple.com/documentation/avfoundation/avassetexportsession/metadata)
  for output metadata and metadata filtering.
- [`AVAssetReader`](https://developer.apple.com/documentation/avfoundation/avassetreader)
  for bounded sample reading and cancellation.
- [`AVAssetWriterInputPixelBufferAdaptor`](https://developer.apple.com/documentation/avfoundation/avassetwriterinputpixelbufferadaptor)
  for writing transformed video pixel buffers through a pool.
- [`AVVideoCompositionCoreAnimationTool`](https://developer.apple.com/documentation/avfoundation/avvideocompositioncoreanimationtool)
  for offline Core Animation overlays in a video composition.
- [`AVAssetImageGenerator`](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator)
  for asynchronous poster and representative-frame generation.
- [`AVPlayerItemVideoOutput`](https://developer.apple.com/documentation/avfoundation/avplayeritemvideooutput)
  for obtaining preview pixel buffers when a player-backed frame is needed.

When an API is deprecated or has a newer concurrency spelling, prefer the spelling that
is available on macOS 13 and keep the deployment target explicit. Do not raise the
deployment target just to avoid implementing a compatibility wrapper.

## 15. Handoff checklist for the next agent

1. Read this document and the current source files in Section 3.
2. Start at Phase 0; do not implement video processing inside the existing image
   `TransformModel` or `MetadataStripper`.
3. Keep changes small enough that `tools/check.sh` can run after every phase.
4. At every output path, ask: can the result be reopened, can the claimed metadata
   removal be verified, and did we label re-encoding honestly?
5. At every UI change, test the 940-point fixed width and both media modes before adding
   another control.
6. Do not build a DMG, alter `CFBundleVersion`, or publish a release unless the owner
   explicitly requests that separate action.
