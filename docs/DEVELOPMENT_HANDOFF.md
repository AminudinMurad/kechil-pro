# Kechil PRO development handoff

Updated: 2026-08-30

## Next major improvement plan

The next agent must follow `docs/NEXT_AGENT_PRODUCT_IMPROVEMENT_PLAN.md` for the
evidence-based Video Clean upgrade. It covers the mandatory reference baseline,
deterministic ISO-BMFF inspection, exact offsets/sizes and byte counts, AI-source
evidence, inspect-before-clean UX, bounded-memory patching, media-range verification,
performance budgets, test fixtures, milestones, and definition of done. Do not begin
by restyling the current flat findings list; the parser/report contract is the first
implementation dependency.

## Release identity and non-negotiable rules

- Product: **Kechil PRO**
- Bundle identifier: `pro.kechil.app`
- Executable: `KechilPRO`
- Version: `1.0.0`
- Build: `1`
- Do not change the version or build number unless Aminudin explicitly requests it.
- Do not overwrite source media. Every result is a new copy.
- Network client access is limited to a user-requested direct image/video fetch. Do not
  add uploads, telemetry, remote processing, a network server, FFmpeg, package-manager
  dependencies or an updater without another explicit product decision.
- Do not add implementation attribution or automated-author trailers.
- The window content width remains fixed at 940 pt and remains vertically resizable.

The universal sandboxed app was built, installed at `/Applications/Kechil PRO.app`,
strictly signature-verified and launched without changing version/build. No DMG was
rebuilt during this pass.

## Current product structure

The app has six independent routes. Each route owns its own queue and settings:

1. Clean · Images
2. Clean · Videos
3. Optimize · Images
4. Optimize · Videos
5. Watermark · Images
6. Watermark · Videos

`Sources/MediaContracts.swift` owns `MediaKind`, `KechilTool` and `ToolRoute`.
`Sources/ContentView.swift` owns the six models and routes all Add, Clear, Save All and
window-wide drop actions. `Sources/ToolSidebar.swift` exposes the three primary tools,
their image/video subroutes, queue counts and the persistent local-processing promise.

## Implemented video Clean

Key files:

- `Sources/VideoMetadataProbe.swift`
- `Sources/VideoCleanPipeline.swift`
- `Sources/VideoCleanModel.swift`
- `Sources/VideoCleanView.swift`
- `Sources/VideoQueueItem.swift`

Behavior:

- Accepts MOV, MP4 and M4V.
- Reads source dimensions, duration, frame rate, transform, codecs, audio presence and
  supported metadata without logging full private values.
- Uses an AVFoundation pass-through container rewrite with an empty metadata list and
  the system sharing filter.
- Reopens and re-probes the temporary output before it can be saved.
- Verifies dimensions, audio presence, duration and supported removable metadata.
- Describes the result as container-cleaned with encoded-frame identity unverified;
  it never makes an unsupported lossless-video claim.
- Uses URL-backed temporary output, sequential bounded processing, cancellation and
  collision-safe saving.
- Video Clean now exposes five independent removal groups — Content Credentials,
  descriptive metadata, XMP, location and container dates — with all groups selected
  by default. Selection changes always re-run from the original source; the legacy
  four-preset API remains available for compatibility.
- When readable provenance values are available, the inspector shows a red AI source
  signal card with an expandable Evidence disclosure. Evidence is bounded and may
  include identifiers, claim text, generator IDs or a short printable payload excerpt;
  binary signatures are never dumped and no cryptographic trust claim is made.
- Empty routes include Upload file / Paste URL tabs. Switching to Paste URL no
  longer reads the macOS pasteboard automatically: an explicit clipboard icon performs
  that work off the main actor, so a slow cross-process pasteboard provider cannot
  freeze tab switching. The video form follows the reference wording with “Fetch
  video” and one-direct-video-URL guidance; images use the equivalent “Fetch image”.
  Direct HTTP(S) media is downloaded to Kechil's temporary folder, while local
  `file://` URLs and absolute paths enter the same queue without a copy. Media is never
  uploaded, and all processing and final saving stay on this Mac.

Intentional limit: when metadata remains after the safe pass-through path, the row is
reported as partial. There is no unsafe atom surgery or silent quality-changing fallback.

## Implemented video Optimize

Key files:

- `Sources/VideoOptimizeSettings.swift`
- `Sources/VideoTranscodeEngine.swift`
- `Sources/VideoOptimizeModel.swift`
- `Sources/VideoOptimizeView.swift`

Behavior:

- Trim start/end, crop aspect and focus, Original/Smart/2160p/1080p/720p/480p,
  no-upscale, H.264/HEVC, Original/24/30/60 fps, MP4/MOV, keep/remove audio and AAC
  96/128/192/256 kbps.
- Quality mode calculates an explainable average bitrate from output pixels, frame rate
  and the selected quality.
- Target-size mode uses decimal MB, reserves 3% for container overhead, subtracts the
  audio budget and derives the video bitrate from the trimmed duration.
- Smart can reduce resolution when the requested target would otherwise be severely
  compressed. Keep Resolution retains dimensions and accepts lower visual quality.
- Target MB is described as an estimate. Source complexity and codec rate control can
  move the final byte count; the actual result is always shown.
- Reader/writer rendering respects preferred transforms, uses presentation timestamps,
  crops without stretching, resizes into a bounded pixel-buffer pool, encodes AAC when
  audio is retained, clears writer metadata and re-probes the output.
- Source and output descriptors are stored separately, so applying again always starts
  from the original source contract.

HDR export is deliberately blocked. The current BGRA/sRGB path cannot prove transfer
function, primaries, matrix and bit-depth preservation, so silently converting HDR to
SDR would violate the product's honesty rules.

## Implemented Watermark for images and videos

Key files:

- `Sources/WatermarkLayoutEngine.swift`
- `Sources/WatermarkRenderer.swift`
- `Sources/WatermarkToolView.swift`
- `Sources/VideoWatermarkPipeline.swift`
- `Sources/VideoWatermarkModel.swift`
- `Sources/VideoWatermarkView.swift`

One serialisable, media-neutral configuration and one Core Graphics bitmap renderer
drive image preview, image export, video playback overlay and video export. Supported
controls are text/logo, text colour including alpha, shadow, opacity, scale, rotation,
safe margin, nine anchors and deterministic tiling/gap. Logo alpha is preserved. Logo
bytes and paths are never persisted.

Image Watermark has a selected-item Original/Watermarked preview, checkerboard canvas,
3×3 accessible anchor picker, drag-to-snap placement and older preset migration.

Video Watermark has native playback, scrubbing, Original/Watermarked comparison,
drag-to-snap placement, an explicit full-duration label, AAC keep/remove choice and
static overlay export across every frame. It reuses the verified reader/writer engine.
Animated/keyframed marks and invisible/steganographic watermarks are outside scope.

## UI and UX state

- Brand header contains Kechil PRO and Settings. The inaccurate Offline badge was
  removed when direct media fetching became an explicit product capability.
- Workspace header contains the active tool, image/video segmented switch and the only
  route-level Add, Clear, Save All and Paste URL actions. Paste URL accepts direct
  HTTP(S) media plus local `file://` URLs or absolute paths.
- Empty-route URL entry uses an in-field clipboard button and never auto-pastes on tab
  selection. Pasteboard reads are asynchronous and display a bounded progress state.
- YouTube, Facebook and Instagram page and delivery domains are rejected with guidance
  to use YouTube Studio, Google Takeout or Meta Accounts Center for owned media. There
  is no platform scraping, cookie ingestion, protected-stream reconstruction, `yt-dlp`
  or FFmpeg integration.
- Upload file and Paste URL share one top-pinned selector. Their lightweight surfaces
  remain mounted while the inactive surface is non-interactive and hidden from
  accessibility, avoiding a control-tree rebuild and layout jump on every switch.
- Image Clean mirrors Video Clean's section hierarchy with a shared Remove heading;
  its single-choice cards use the noun labels All metadata, AI metadata, EXIF and GPS.
- Image Optimize custom crop width and height are independent pixels. Preview and
  export share `ImageCropGeometry`; oversized values clamp independently per source.
- Resize mode defaults derive from the selected retained crop size (or 100% for
  Percentage). Do not restore the previous global 1600 px placeholder.
- Video Optimize trim uses the `VideoTrimRangePolicy` In/Out marker contract. Start 0
  plus End nil means the full source; handles retain a minimum 0.05 second range.
- Slider increments are quantized through bindings rather than SwiftUI's stepped
  initializer, because stepped macOS sliders render dense unwanted tick marks.
- The 190 pt sidebar contains three tool groups, six routes, queue counts and a local/
  originals-safe card. Groups are permanently expanded; image/video routes are
  explicitly indented children and do not use disclosure controls.
- Video Clean scope cards use each group's `symbolName` as their primary icon. The
  selected background and border communicate state without repeated checkbox glyphs.
- Settings panes use the order Source/Appearance/Placement/Output where applicable.
- Settings includes a persistent security-scoped Default save folder. Fetched sources
  remain temporary; processed outputs use the configured folder or a Save dialog.
- Preview sits above the queue. Rows use text and symbols in addition to colour.
- Empty, analysing, processing, cancelling, failed, completed and saved states remain
  distinct. Progress and Cancel are visible during video work.
- Settings says Default save folder and applies it to images and videos.

The final source hierarchy was reviewed against `docs/mockups/kechil-media-ui.png`.
`tools/render-ui-snapshots.sh` renders the six empty routes, Settings and compact-height
Clean/Optimize views from the real SwiftUI hierarchy without Screen Recording access.
Those renders were inspected at 940 × 900 and the minimum 940 × 650. Real-device MOV/M4V
acceptance remains a human pre-release step.

## Verification

Run:

```bash
tools/check.sh
```

The current gate passes and includes:

- Swift warnings-as-errors type-check for every source file on the macOS 13 target;
- six-route and queue-isolation assertions;
- video trim/crop/target-size policy assertions;
- shared watermark anchor/rotation/tile/Codable assertions;
- a generated two-second H.264 + PCM fixture that exercises real video Clean,
  metadata removal, crop, trim, tested 1 MB output budget, AAC encoding, video
  Watermark and representative first/middle/last watermark visibility;
- dashboard geometry, image target-size, provenance, bundle identity, generated icon
  and lossless image-strip checks;
- collision-safe save replacement and a hard guard preventing any queued original path
  from being selected as an output.

The signed sandboxed development build was also exercised against local HTTP fixtures:
one PNG and one MP4 were fetched through the real UI, entered their respective Clean
queues and completed processing. Each sandboxed temporary import matched its served
fixture byte-for-byte by SHA-256. The bundle carried the outbound network-client
entitlement and no inbound network-server entitlement.

## Remaining release acceptance

Test a real iPhone MOV, a landscape MP4, a portrait M4V, a transparent PNG logo and a
long target-MB encode. Only rebuild the DMG when explicitly requested. Never change the
version/build unless Aminudin explicitly requests it.
