# Kechil PRO development handoff

Updated: 2026-08-31

## 2026-08-31 local follow-up: Image Optimize live size and crop-row alignment

This working-tree follow-up is intentionally local and has not been committed or
pushed. Image Optimize now uses the same full `TransformPipeline` render and encoder
as its live preview to populate an **Optimized output estimate** card. Crop, resize,
format and quality changes cancel stale work, remeasure the selected source, and show
the new encoded byte count without changing the prepared queue output. The queue row
therefore remains the last committed result until Optimize Selected or Optimize All is
pressed. The estimate is explicitly labelled as measured and not saved yet.

The empty Image Optimize and Image Watermark routes still show only their upload/drop
surface; settings columns appear after at least one source enters the queue. The custom
crop `×` now aligns with the numeric input controls rather than the labels above them.

The authoritative real-media interaction suite passes 117 assertions, including the
new Optimize measurement and remeasurement checks. The 39 native UI snapshots render
successfully; the populated Optimize view, custom crop row, and empty Optimize and
Watermark routes were visually inspected. No release package or public GitHub state
was changed by this follow-up.

## 2026-08-31 live Clean and Watermark size estimates

Clean and Watermark now expose a selected-source output-size card before saving. Image
Clean measures the same selected-scope cleaner used by export; when no selected field
matches, it measures the exact unchanged-copy path. Image Watermark fully encodes the
selected image with the current format, WebP and quality settings. Video Clean measures
the same pass-through export path, and Video Watermark encodes a real short sample with
the current codec, audio, container and quality settings before projecting the sample
rate over the full duration.

Changing the selected file or any relevant setting cancels stale work and starts a new
measurement. The original source is never modified and setting changes do not create a
saved output. Once an operation prepares an output, the card switches to that output's
measured byte count and labels the basis clearly. The shared presentation lives in
Sources/MediaSizeEstimate.swift and Sources/MediaSizeEstimateView.swift; the model and
pipeline integrations are in ScrubModel, VideoCleanModel, TransformModel,
VideoWatermarkModel, VideoCleanPipeline and VideoWatermarkPipeline.

The focused real-media interaction suite passes 117 assertions, including exact Clean
bytes, real image encoding, real video sampling, settings-change remeasurement and
source-preservation checks. The visual renderer now produces 39 native SwiftUI
snapshots, including a dedicated estimate-card state set; the relevant Clean and
Watermark states were inspected before release packaging.

## 2026-08-31 explicit batch actions and logo defaults

Implemented All/Selected processing and Save Selected across all six routes.
Selected now supports standard macOS queue selection: click one row, Command-click
to toggle, or Shift-click a range. The last clicked row remains the preview primary,
while Selected processing captures the selected IDs and current settings before work
starts; changing the selection mid-run cannot expand the target. Button names are
Clean, Optimize or Watermark Selected/All, with no Apply prefix. Clean's no-match
actions remain Prepare Copies / Prepare Selected Copy. Save Selected writes one
prepared output directly or, for multiple selected prepared outputs, asks once for a
folder and writes separate collision-safe files. Save, Save Selected and Save All
share one green style and exact width; Clean has equal-width queue footers and
Optimize/Watermark have fixed settings footers, so their processing actions remain
visible while scrolling.

Optimize image and video rows show the selected source's original dimensions until
that item's current preview/output is rendered, so selecting another queue item cannot
leave the previous item's crop dimensions on screen.

Logo defaults are 90% opacity, 0-degree rotation, 40% scale, Centre placement,
2.5% safe margin for images and videos. Text defaults remain unchanged. Session
profiles preserve edits when switching kinds; saved image presets still override.

Post-layout `tools/check.sh` passes, including 117 real-media interaction assertions,
9 shared selection assertions and 29 shared action-state checks. All 39 native
snapshots render; six-route
headers/footers, disabled/busy states, dark appearance and logo defaults were
inspected. Compact Video Optimize now scrolls its preview/trim region to reserve
visible space for the output header and queue. See
`docs/qa/BATCH_ACTIONS_QA_2026-08-31.md` for evidence and current package status.

The old batch-crop DMG failed its pre-rebuild sidecar check and was backed up.
The current replacement is `releases/Kechil-PRO-v1.0.0-macos-universal.dmg`,
SHA-256 `0ddf449f7e3d56b19b9a0ea71e863e69529bee79a9247e0e775987fef3536516`,
5,050,763 bytes, version/build 1.0.0 (1), x86_64 arm64. Its sidecar and disk-image
checks pass; mounted read-only app signature/entitlements pass. It is ad-hoc signed,
not notarised. It is publicly released at
https://github.com/AminudinMurad/kechil-pro/releases/tag/v1.0.0; no application was
installed or replaced during this package verification. The historical checksum
below is not the current release verification record.

The matching universal ZIP is `releases/Kechil-PRO-v1.0.0-macos-universal.zip`,
4,383,928 bytes, SHA-256
`de35f12354cef7d25a4a75deaafe54cd5bf2426d1dd2624616e6cede8de31a5f`. Its sidecar,
`unzip -tqq`, archive metadata check and embedded app signature all pass; it contains
only `Kechil PRO.app`.

The public source repository is https://github.com/AminudinMurad/kechil-pro. The
remote `main` branch and peeled `v1.0.0` tag were verified against the release
source commit `00794b11774a33ab72c06c9a0cb8897b5d8dc8cc` at publication. GitHub
contains the DMG, DMG checksum sidecar, ZIP, and ZIP checksum sidecar; the
published sidecars are byte-identical to the locally verified sidecars. The
no-AI co-author metadata workflow also passed on the publication push.

## 2026-08-31 batch crop and playback verification

Image Optimize now separates custom-crop enlargement from post-crop Resize.
**Enlarge smaller images to fill target** uses one uniform scale to cover both
target dimensions, then crops exactly. Default-off keeps native pixels and
explicitly reports smaller results. The shared target and linked ratio remain
stable when selecting another batch item. The UI shows affected-image counts,
per-row **Next crop** predictions, independent Resize enlargement, and `px`/`%`
after numeric fields. Original mode hides the crop overlay. Live preview does not
change committed output; Apply to All uses an immutable settings snapshot.

Real output testing found and fixed a Core Image fractional-crop composition bug:
a crop followed by a 200% resize could lose one border pixel. Aligning the custom
crop origin before the single crop operation keeps exact dimensions through later
resizing, including edge focus and rotated sources.

`bash tools/check.sh` passes, including 63 new real export, hosted SwiftUI,
mixed-batch, source-preservation, error-isolation and AVPlayer assertions.
`tools/render-ui-snapshots.sh` renders 25 snapshots. Crop enlargement on/off,
Original, compact crop, resize unit placement and compact playback controls were
visually inspected. This is not a full responsiveness benchmark or Intel runtime
acceptance. See `docs/qa/BATCH_CROP_QA_2026-08-31.md` for release verification.

Historical batch-crop release: `releases/Kechil-PRO-v1.0.0-macos-universal.dmg`, **1.0.0 (1)**,
**x86_64 arm64**, SHA-256
`95adf2275ab6888479c20d17013e3a82848b907d5e717037983aa157bd35ac78`.
Sidecar, disk-image integrity, mounted-app signature and sandbox entitlements pass.
The app was click-tested directly from the read-only DMG (exact crop Apply, trailing
Resize unit, playback and scrubbing). It remains ad-hoc signed, not notarized.
The test app is closed, the DMG ejected, and the generated build app moved to Trash
to avoid another searchable duplicate. No application was installed in this run.

## 2026-08-31 inspect-first Clean delivery

Milestones 0–2 from `docs/CLEAN_IMAGE_VIDEO_IMPLEMENTATION_PLAN.md` are now
implemented in the working tree. In addition to the safety foundation, image and
video Clean now follow an explicit inspect → review → clean → verify → save lifecycle.
Import creates no modified output. Selection changes update cached plans without
re-reading media, no-match inputs can prepare clearly labelled unchanged copies, and
partial results cannot use the ordinary verified-save action.

The shared lifecycle contract records source identity, selection revisions, plans,
verification checks and receipts. Image inspection/cleaning runs off the main actor;
cancellation is forwarded into detached work, and run identifiers prevent a cleared
or superseded job from publishing stale state. Both media models revalidate the
source before and after cleanup. Final saves use a bounded streaming byte comparison
against the verified temporary artifact, including replacement saves, before the row
can be marked Saved.

The underlying Milestones 0–1 delivery includes bounded PNG `tEXt`/`zTXt`/`iTXt`
decoding shared by provenance inspection and AI cleanup, mixed-field fail-closed
handling, display-orientation preservation, explicit multi-frame/HEIC preservation
limits, video no-op copies, structural C2PA detection/evidence, and credentials-only
scope isolation for ordinary descriptive text. Checks cover JPEG orientations 1–8,
PNG compressed text, mixed rights fields, animated/multipage limits, C2PA evidence,
unchanged video copies, cancellation propagation and final-save byte identity.

`bash tools/check.sh` passes with warnings treated as errors. This is source/test
evidence. A signed host-architecture development app was built as part of UI snapshot
generation, but no universal release app or DMG was packaged at that milestone. Twenty-two real SwiftUI
snapshots were rendered and inspected, including image/video ready-for-review states.
The deeper raw ISO-BMFF inventory and patcher, complete preservation receipts,
measured responsiveness pass and optional metadata writing remain future milestones.

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

An earlier universal sandboxed app was installed at `/Applications/Kechil PRO.app`.
That installation note is historical: the user subsequently requested removal of
duplicate installations. Do not reinstall or create a second app copy merely for
testing; use the current release verification record above for delivery status.

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
- Image Optimize custom crop width and height are independent, batch-stable target
  pixels. Preview and export share `ImageCropGeometry`; Keep native size clamps each
  source independently, while Enlarge smaller images to fill target uniformly scales
  a smaller source before cropping to the exact target.
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
