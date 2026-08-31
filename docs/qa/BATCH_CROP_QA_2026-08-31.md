# Batch crop, resize and playback QA — 2026-08-31

## Scope and behavior

This delivery continues the requested Image Optimize batch crop/upscale work,
checks the existing video playback controls, and moves Resize's unit labels after
the value boxes to match Crop. Version remains 1.0.0, build 1. No publication,
upload, tagging, version change or installation into Applications is part of this run.

- Custom crop enlargement defaults off. Native mode clamps each crop edge to its
  own source, so smaller results are explicitly permitted and described.
- Enabling **Enlarge smaller images to fill target** scales uniformly by
  `max(1, targetWidth/sourceWidth, targetHeight/sourceHeight)`, then crops exactly.
  It does not stretch or pad. Sources already covering the target are not enlarged.
- Resize's **Allow upscaling after crop** is independent. An exact crop target
  describes the intermediate crop, not necessarily the final resized export.
- The linked target ratio is captured once. Browsing a different batch member
  cannot silently rewrite the shared crop/resize target.
- The batch count and **Next crop** rows describe prospective settings; preview
  changes do not replace committed queue output. Apply snapshots settings once.
- Original mode shows the source without the crop overlay. Preview errors are
  visible. Resize labels use `Width [value] px`, `Height [value] px`,
  `Long edge [value] px`, and `Scale [value] %`.

## Automated evidence

`bash tools/check.sh` completed successfully, including source type checking with
warnings as errors, vendored-codec integrity, all existing image/video and Clean
regressions, and the new interaction gate. The new gate is also independently
repeatable with `bash tools/check-media-interactions.sh`.

**63 media interaction assertions passed**, covering:

- Actual encoded PNG outputs from landscape 1000×600, portrait 600×1000 and larger
  2000×1200 sources: both crop policies × both resize-enlargement settings.
- 1400×375 target and 200% Resize, with decoded dimensions checked against the
  reported result. JPEG and WebP also decode at the exact target.
- A synthetic circle remains round after enlargement; opaque fixtures have no
  transparent border or padding. Both focus extremes are covered.
- EXIF orientation is applied before the enlargement calculation.
- Width, Height and Long edge Resize modes respect their independent enlargement
  setting after the exact crop. Original/no-crop ignores a saved crop policy.
- Hosted SwiftUI selection changes preserve the linked batch target and a manual
  Resize target; linked edits use the captured ratio.
- Live previews respond to crop-policy changes without replacing output data.
  Apply to All keeps its original snapshot even if controls change mid-run.
- All three originals remain byte-for-byte unchanged. A corrupt fourth file
  becomes an isolated error, not a saveable output, without erasing successes.
- A real AVPlayer loads the bundled MOV. Play advances, pause holds, scrubbing
  and skipping seek correctly, mute/unmute work, and Clear releases the player.

The export matrix initially caught a real Core Image composition bug: cropping at
a fractional origin, normalizing, recropping and then resizing 200% produced a
749-pixel result instead of 750. The implementation now aligns the custom crop
origin before one crop operation. The exact-dimension and border assertions pass
with that fix.

Full run output: `build/qa-2026-08-31/checks.log`. Test-generated originals and
exports: `build/check-20260831-144911/media-interactions/fixtures/`.

## Visual evidence

`SKIP_APP_BUILD=1 bash tools/render-ui-snapshots.sh` completed successfully using
current host build objects. It generated **25 native SwiftUI snapshots**, plus
findings-filter and compact-scroller assertions.

Inspected snapshots under `build/ui-snapshots/`:

- `optimize-image-custom-crop.png`: native crop, smaller-image count and per-row
  predictions, Scale with `%` after the field.
- `optimize-image-crop-fill-target.png`: enabled crop enlargement, mixed batch,
  fixed target and Width with `px` after the field.
- `optimize-image-crop-fill-compact.png`: wrapped control text remains readable;
  lower controls and queue remain available through their scroll regions.
- `optimize-image-crop-original.png`: no crop overlay/dimming; original source
  dimensions are clearly distinguished from the prospective crop.
- `optimize-video-trim-compact.png`: the persistent play/pause, skip, scrub and
  mute bar sits between the preview and trim controls.

Snapshot rendering is visual regression evidence, not a full interactive
performance benchmark. Runtime interaction and packaging results are recorded below.

## Packaged app and live click-through

Built with `bash tools/make-dmg.sh`, retaining **1.0.0 (1)**:

- Artifact: `releases/Kechil-PRO-v1.0.0-macos-universal.dmg`
- Sidecar: `releases/Kechil-PRO-v1.0.0-macos-universal.dmg.sha256`
- Size: **4,678,567 bytes**.
- SHA-256: `95adf2275ab6888479c20d17013e3a82848b907d5e717037983aa157bd35ac78`
- Architectures from the executable inside the mounted DMG: **x86_64 arm64**.
- `hdiutil verify` and the sidecar checksum both passed.
- Read-only mounted app passed `codesign --verify --deep --strict`, including a
  second verification after the live test.
- Entitlements: app sandbox, user-selected read/write files, outbound network
  client. No inbound network-server entitlement.
- The mounted executable and build executable had identical SHA-256:
  `24f333153974c41acd650ae2854b721a36272181b67c753d42fc5a09c9410f04`.
- The mounted volume contained only the app and the Applications shortcut.

The app was launched directly from the read-only test mount, and its running
executable path was verified. No copy was installed into Applications.

Live click-through with synthetic fixtures confirmed:

1. Import and automatic WebP conversion work in the sandboxed packaged app.
2. Custom crop 1400×375 plus crop enlargement changes the prospective label to
   **enlarge 1.40×**, keeping the earlier 1000×600 output until Apply.
3. Width mode visibly shows **Width [1,400] px**. Apply updates the committed queue
   result to **1400 × 375**.
4. Video Optimize opens the bundled five-second MOV and shows the persistent
   transport bar beneath the preview. Play advances and changes to Pause, Mute
   changes to Unmute, and scrubbing sets both playback and trim-preview positions
   to **0:02.500**. The automated gate separately verifies pause/skip behavior.

Evidence captures: `build/qa-2026-08-31/packaged-crop-width-unit.jpeg` and
`build/qa-2026-08-31/packaged-playback.jpeg`. Build log:
`build/qa-2026-08-31/package.log`.

After testing, the app was quit and the test volume ejected. The generated
`build/Kechil PRO.app` was moved to the recoverable
`~/.Trash/Kechil PRO QA 20260831-1502.app` and unregistered there; source files and preferences
were preserved. Final checks found no running KechilPRO process, no app in the
standard system/user Applications locations or build location, and no Spotlight
bundle-ID match. The release DMG and sidecar remain available.

## Remaining acceptance boundaries

- Actual processing and AVPlayer checks ran on this Apple Silicon Mac. Intel
  architecture inclusion does not establish runtime QA on a physical Intel Mac.
- Enlargement is ordinary image resampling, not AI detail recovery, and may soften
  a low-resolution original.
- This is not a broad performance-profile pass or the separately planned deeper
  Video Clean ISO-BMFF milestone.
- Ad-hoc local testing builds are not Developer ID signed or notarized releases.
