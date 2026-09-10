# Changelog

All notable changes to Kechil PRO are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [1.0.2] — 2026-09-10

### Added
- Image Optimize now has a **Width × Height** resize mode with a default-on aspect
  ratio lock. Editing either dimension updates the other from the cropped image ratio;
  unlocking permits independent output dimensions.
- Settings now offers a persistent custom appendage for converted image filenames,
  retaining `-kechil` as the default, plus a reset action and live filename examples.
- Settings can optionally append the verified output resolution, such as
  `-1920x1080`, to image and video outputs from Optimize and Watermark.

### Changed
- Converted filename text is bounded and sanitised so path separators cannot become
  part of an output path. Existing originals and destination files remain protected.
- The expanded Settings panel now scrolls within a compact height so every preference
  remains reachable on the smallest supported MacBook display.

## [1.0.0] — 2026-08-31

### Changed
- The app is now a three-tool local-processing media utility: Clean, Optimize and Watermark.
  Each tool has separate Images and Videos routes and independent queues. Clean alone
  carries the direct-container, decoded-pixel-identity promise for supported images;
  optimize and watermark operations re-render pixels by design and remove metadata
  from their newly encoded outputs.
- The dashboard reports Generative AI evidence rather than treating every Content
  Credentials carrier as an AI declaration. Findings distinguish declared, stated and
  inferred evidence, and computational capture is not misclassified as Generative AI.
- Product identity is now **Kechil PRO**, with bundle identifier
  `pro.kechil.app` and executable `KechilPRO`. A previously installed build is a
  separate app rather than an upgrade; the only thing this orphans is the remembered
  dashboard window size — nothing about any image was ever stored.
- `tools/check.sh` now asserts that `CFBundleExecutable` and `build-app.sh`'s
  `BIN_NAME` are the same string, and that the entitlements file the build signs
  with exists. A mismatch there builds, signs and verifies cleanly and then fails
  to launch, which is exactly the failure a rename invites.
- `tools/make-dmg.sh` reads the executable name out of `Info.plist` instead of
  hardcoding it, so `lipo -archs` cannot silently point at a path that a future
  rename has moved.
- `tools/check.sh` also re-renders the app icon and requires `assets/icon-master.png`,
  `assets/icon.png` and all ten representations inside `assets/AppIcon.icns` to come
  back byte-identical, so the tracked artwork can never drift from the Swift that
  generates it. The 1024pt representation is normalised to BMP before comparison,
  because `iconutil` rewrites PNG metadata while preserving pixels.

### Added
- Image Optimize now offers a **Custom size** crop with independent pixel width and
  height, a shaded live retained-area guide, and safe per-source clamping for batches.
- Video Optimize replaces numeric Start/End trim fields with draggable **In** and
  **Out** markers, playhead-based marker buttons and a full-source default when no
  markers are set.
- Image Clean now places the four scoped choices beneath one **Remove** heading, using
  the non-redundant card labels **All metadata**, **AI metadata**, **EXIF** and **GPS**.
  Switching a choice re-runs the current queue from the original files, keeps unrelated
  metadata where the container supports it, and re-reads the output to report any
  selected-scope data that remains. Video Clean retains its five multi-select groups.
- Clean and Watermark now show a live selected-media size card when settings change.
  Clean measures the same cleaner or unchanged-copy path, Image Watermark fully encodes
  the current image settings, and Video Watermark encodes a real short sample before
  projecting it across the duration. The card replaces the estimate with the prepared
  output's measured bytes after export.
- Media queues now support standard macOS multi-selection: Command-click toggles rows
  and Shift-click selects a range, while the last clicked row remains the preview
  primary. Clean, Optimize and Watermark Selected operate on the selected set. Save
  Selected saves all selected prepared outputs into one chosen folder as separate,
  collision-safe files, and Save/Save Selected/Save All use one shared green action
  style and width. Optimize rows show the newly selected source's original dimensions
  until its current preview/output exists.
- The workspace toolbar and empty routes now include **Paste URL**. They accept a
  direct HTTP(S) image/video URL, a Finder `file://` URL or an absolute local path.
  Remote sources are downloaded into Kechil's sandboxed temporary folder before
  entering the same local processing queue; media is never uploaded.
- A header settings gear with the MacBook dashboard-size selector, a persistent
  security-scoped default media save folder, version/build/copyright information and a
  Klik PRO-style About card. The card identifies the GPL-3.0 license and includes an
  Updates placeholder; a separate support card links to GitHub, GitHub Sponsors,
  Ko-fi and PayPal. No updater, telemetry, inbound server access or upload path is added.
- A fixed-width tool sidebar for Clean, Optimize and Watermark. Each group exposes
  Images and Videos with synchronized workspace mode switching and per-route queue counts.
- Video Clean for MOV, MP4 and M4V: local metadata inspection, pass-through container
  rewrite, output re-probe, explicit verification scope, queue cancellation and URL-backed
  temporary outputs that are copied only when the user saves.
- Video Optimize with trim, crop focus/aspect, resolution, no-upscale, H.264/HEVC,
  frame rate, audio policy/rate, MP4/MOV and quality or target-MB modes. The target-size
  policy reserves container/audio budget and can reduce Smart resolution to protect
  quality; Keep Resolution makes the opposite trade-off explicitly.
- A shared deterministic watermark layout and bitmap renderer used by image preview,
  image export, video preview and video export. Image and video views include
  Original/Watermarked comparison, text/logo sources, colour, shadow, safe margin,
  rotation, scale, nine anchors and tiled placement. Video playback shows the static
  full-duration overlay and export re-encodes through a verified URL-backed pipeline.
- Deterministic checks for the six-route contract, video trim/crop/target-size planning,
  and watermark anchors, rotation, tiling and Codable persistence.
- When a default save folder is configured, Save All writes there directly with
  collision-safe filenames; individual Save dialogs open in that folder.
- Top tool tabs and a batch Optimize workspace. It supports crop focus,
  long-edge/width/height/percentage resize, no-upscale, WebP/JPEG/PNG/HEIC/AVIF/TIFF/GIF
  output, WebP lossless/method settings, quality floor/ceiling and a bounded byte-target
  search that reports an unreconcilable quality constraint rather than silently lowering
  quality.
- Native WebP encoding through pinned vendored libwebp 1.6.0, built and linked per
  architecture without a package manager. `vendor/libwebp.sha256` verifies 339 source
  files before every correctness check.
- Batch text and logo watermarking: opacity, rotation, image-relative scale, nine anchor
  positions, tiled placement and reusable settings presets. Presets deliberately omit
  logo bytes, image paths, queued images and output history.
- `Sources/ProvenanceProbe.swift` and a 22-assertion Swift test suite for read-only AI
  provenance inspection across JPEG, PNG, WebP and BMFF/HEIF/AVIF C2PA carriers.
- `Tests/SizeTargetChecks.swift`, a deterministic seven-assertion check for target-size
  quality selection, conflict reporting and the eight-attempt bound.
- An app icon. A dark photo card holding a sun and two peaks, with the accent-blue
  spark straddling its top-right corner, on the same near-white squircle tile and
  PRO badge form as Klik PRO. It is generated by `tools/render-app-icon.swift` and
  rendered by `tools/render-artwork.sh` into `assets/`, so there is no binary in the
  repo that nobody can reproduce. The photo is a filled mass with the light shapes
  knocked out of it rather than an outlined frame, because a 26pt stroke on a 1024pt
  canvas is 0.8px at 32pt and disappears; the spark carries a tile-coloured halo
  because accent blue on the card's ink measures 4.1:1 and would otherwise mush into
  it.
- `Sources/BrandLockup.swift`, one view owning the shipped app icon, large Kechil
  wordmark, raised green PRO badge and bundle version. The dashboard follows Klik PRO's
  single-line brand hierarchy without placing a per-tool tagline below it.
- Byte-level metadata stripper for JPEG, PNG and WebP that removes EXIF, GPS,
  IPTC, XMP, C2PA Content Credentials, maker notes, embedded text and timestamps
  while copying compressed pixel data through verbatim — no decode, no
  re-encode, no quality loss.
- ImageIO-based path for HEIC, HEIF, TIFF, AVIF and GIF using
  `CGImageDestinationCopyImageSource`, which also avoids re-encoding.
- SwiftUI interface with window-wide drag and drop, folder support, batch
  processing, and a per-file report naming exactly which metadata blocks were
  found and removed.
- Dashboard summarising the whole queue before anything is saved: headline tiles
  for images, files carrying metadata, files carrying GPS coordinates, files
  carrying Generative AI evidence, and total bytes stripped.
- Category breakdown chart counting how many images carried each kind of
  metadata, with GPS location and Generative AI evidence flagged in status colour
  alongside an icon and a visible count, so nothing is signalled by colour alone.
- Category filter chips that narrow the file list. Tiles and chart keep
  describing the entire queue, so a filter can never make the summary understate
  what was found.
- Inspector pane for the selected image: preview, size before and after, whether
  the file was processed losslessly, and one plain-language line per kind of
  metadata removed explaining what it can reveal.
- Per-file save and batch save-to-folder with automatic collision-safe naming.
- Best-fit dashboard heights for five MacBook models, reachable from a tile picker in
  Settings and from Window ▸ Dashboard Height with ⌘1 to ⌘5. Width stays fixed at
  940 points while height remains resizable and is clamped to the visible screen.
  The window's position and height are remembered between launches; nothing about
  the images is.
- App Sandbox entitlements granting user-selected file access and outbound client
  access for an explicit direct-media fetch. The inbound network-server entitlement
  remains absent.
- `tools/build-app.sh` for building a signed `.app` without an Xcode project,
  including universal binary support.
- `tools/make-dmg.sh`, which packages a signed universal build as a checksummed
  disk image in `releases/`. It refuses to package a bundle missing the sandbox or
  outbound direct-download entitlement, and rejects an inbound network-server
  entitlement, so the app's privacy boundary is asserted at build time.
- `tools/check.sh` combining a warnings-as-errors type-check with the algorithm
  correctness proof.
- `Tests/verify_algorithm.py`, which builds images carrying real metadata and
  asserts both that it is removed and that decoded pixels are byte-identical
  afterwards. 42 assertions across three formats.
- `Tests/PresetChecks.swift` assertions over the dashboard preset geometry: every
  preset recognises itself within Retina rounding tolerance, a real vertical drag
  does not, all presets remain 940 points wide, and height and model diagonal form a
  monotonic ladder without falling below the window minimum.

### Fixed
- The Tools sidebar is permanently expanded, uses a stronger section label and clearer
  child indentation, and Video Clean uses distinct metadata-group icons instead of a
  repeated checkbox glyph.
- Continuous sliders no longer display dense native step ticks as a thin dotted line.
  Their displayed/exported increments remain quantized without the unwanted marks.
- Image resize modes now initialise from the selected retained image dimensions;
  Percentage starts at 100% instead of every mode inheriting a 1600 px placeholder.

- Switching between Upload file and Paste URL no longer rebuilds the two empty-state
  control trees or moves their shared selector between the centre and top of the card.
  Both surfaces remain mounted, the inactive one is non-interactive and hidden from
  accessibility, and the selector stays pinned to one position without transition
  animation.
- Paste URL now rejects recognised YouTube, Facebook and Instagram page and delivery
  domains with official-export guidance. Kechil does not scrape platform pages, accept
  social-account cookies or reconstruct protected playback streams; ordinary direct
  image/video hosts and local files remain supported.
- Finder Open With events now add supported files to the matching Images or Videos mode
  instead of opening an empty dashboard.
- Saving now enforces the UI promise that queued originals are never overwritten, while
  still honouring a confirmed replacement of a different output file.
- Installed bundles are cleared of File Provider/Finder xattrs and deep signature-checked,
  preventing a valid build from becoming invalid when copied out of Documents.
- Workspace subtitles have enough room to remain readable, image Optimize directs users
  to switch media mode clearly, the Settings support card fills the panel width, and the
  manual-resize floor keeps the global header visible in split settings workspaces.
- Settings now expands to the complete card stack instead of placing an inner scroll bar
  beside the dashboard-size, save-folder, About and support sections.
- Closed verified metadata leaks in both the Swift stripper and the Python reference
  proof: progressive-JPEG/post-SOS metadata, data after EOI, JFXX thumbnails, MPF
  secondary images, deceptive APP0/APP2 segments, unknown PNG chunks, WebP C2PA and
  unknown WebP private chunks. The reference proof now has 42 assertions.
- HEIF/AVIF C2PA UUID boxes are neutralised without moving following media offsets and
  ImageIO outputs are re-inspected before the UI reports them clean.
- `tools/build-app.sh` could not build the app at all. It had never been run to
  completion: it lacked the toolchain detection `tools/check.sh` has, so it failed on
  SwiftUI macro expansion, and then `codesign` rejected the bundle with "resource
  fork, Finder information, or similar detritus not allowed" because `cp` carried
  extended attributes in from `App/`. The toolchain logic now lives in
  `tools/select-toolchain.sh` and is sourced by both scripts, and the bundle is
  cleaned with `xattr -cr` before signing.
- Metadata deletion on the HEIC, HEIF, TIFF, AVIF and GIF path silently did
  nothing. `kCFNull` arrives from ImageIO as an implicitly unwrapped optional, so
  placing it directly in the deletion dictionary boxed an optional that ImageIO
  does not recognise as its delete marker. It is now unwrapped through an
  explicitly typed constant.
- Thumbnail generation ran on a background thread through an API that is only
  safe on the main thread. Rebuilt on ImageIO, which is thread-safe, and it now
  also honours EXIF orientation so previews are no longer sideways.
- `tools/check.sh` failed with dozens of unexplained macro errors when the
  selected developer directory was Command Line Tools, which cannot expand
  SwiftUI's `@State`. It now finds a usable Xcode toolchain by itself, or fails
  with a message naming the actual cause.

- `docs/INSTALL.md` claimed the app writes nothing outside its own bundle. It now
  stores the dashboard window's position and size in its sandbox container, so the
  uninstall instructions say so and give the path. Nothing about the images scrubbed
  is recorded anywhere.

### Known limitations
- Invisible in-pixel watermarks such as SynthID are not metadata and cannot be
  removed by the Clean tool or any metadata stripper.
- Animated GIF may fall back to a re-encode; affected files are labelled
  "re-encoded" in the UI rather than reported as lossless.
- C2PA evidence extraction is not cryptographic validation of signatures, trust chains,
  revocation or asset bindings. Brotli-compressed assertion payloads may be located but
  are not decompressed.
- Real-device QA is still required for HEIC with GPS/XMP, signed C2PA assets, watermark
  appearance and all supported ImageIO encoders.
