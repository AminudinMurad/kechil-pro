# Installing Kechil PRO

## Requirements

macOS 13 (Ventura) or later, on Apple Silicon or Intel.

## From a disk image

Verify the sidecar before opening the release, then drag the app to Applications:

```bash
shasum -a 256 -c Kechil-PRO-vX.Y.Z-macos-universal.dmg.sha256
open Kechil-PRO-vX.Y.Z-macos-universal.dmg
```

The release also includes a ZIP containing the same universal app bundle and a
matching `.zip.sha256` sidecar. The DMG is the recommended Finder installation
path; the ZIP is useful when a direct app bundle is preferred.

An ad-hoc build is not notarised. Only bypass Gatekeeper for a copy you trust; a public
release should be Developer ID signed and notarised.

## From source

A full Xcode installation is required for SwiftUI macros. Then run:

```bash
tools/check.sh
UNIVERSAL=1 SIGNED=1 tools/build-app.sh
tools/install-app.sh
tools/make-dmg.sh
tools/make-zip.sh
```

Kechil PRO has no package-manager setup. WebP support comes from the included, pinned
libwebp 1.6.0 source tree; `tools/check.sh` verifies it before building.
`tools/install-app.sh` preserves an existing installed copy under
`build/install-backups/`, clears File Provider/Finder xattrs from the new copy and
strictly verifies the signature after installation.

For visual regression checks of every tool/media route and Settings without macOS
Screen Recording permission:

```bash
tools/render-ui-snapshots.sh
```

This writes 39 PNGs to `build/ui-snapshots/`, including the 940 × 650 minimum-height
layout, mixed-batch crop enlargement on/off, Original without a crop overlay,
compact playback controls, green Save All and Selected actions across all six routes,
light/dark action states, logo defaults, live Clean/Watermark size-estimate cards, and
separate Upload file / Paste URL placement checks. Set `SKIP_APP_BUILD=1`
only when the current host-architecture build objects are already known to be current.

`tools/check.sh` also runs `tools/check-media-interactions.sh`: real PNG/JPEG/WebP
exports, mixed-batch settings/preview behavior, Selected versus All processing on
all six routes, logo defaults, source preservation and AVPlayer transport checks.
The interaction checks can be run separately with
`bash tools/check-media-interactions.sh`.

## Privacy check

The sandbox allows user-selected read/write files plus outbound client access for a
user-requested direct-media download. It must not contain the inbound network-server
entitlement:

```bash
codesign -d --entitlements - "build/Kechil PRO.app"
```

## Using the tools

- **Clean:** choose Images or Videos, inspect the supported metadata findings, then save
  individual or batch cleaned copies. JPEG/PNG/WebP image outputs preserve decoded pixels;
  supported video containers use a verified pass-through rewrite when available. Once a
  source is inspected, the selected-file card measures the same Clean path (or the exact
  unchanged-copy path) and updates when the Remove scope changes.
- **Optimize:** crop/resize/convert images, or trim/crop/resize/compress videos. Video
  target MB mode explains whether it protects quality by lowering resolution or keeps
  resolution at the cost of visual quality. Size is an estimate, never an exact-byte claim.
- **Watermark:** preview text or a logo before export, then position, colour, rotate,
  scale or tile it. Video marks are static across the full duration. Image Watermark
  fully encodes the selected image for its live estimate; Video Watermark encodes a real
  short sample and projects the result across the duration. Image presets retain settings
  only; they do not retain logo bytes, file paths or batch history.

Originals are never modified in place. Completed output data is released after saving.

For a fixed-size image batch, choose **Crop → Custom size** and enter the target
width and height. **Enlarge smaller images to fill target** uniformly enlarges only
images that cannot cover both dimensions, then crops exactly; it does not stretch
or add padding. Leave it off to retain native pixels, accepting smaller crops.
The affected count and each row's **Next crop** prediction explain the current
settings before applying. **Link target ratio** captures the selected image ratio
once and keeps it fixed while browsing the batch.

**Resize → Allow upscaling after crop** is separate: it controls enlargement of the
already-cropped result. Resize can therefore change the final dimensions after an
exact custom crop. Pixel and percentage units appear after their value fields.
Selecting a different image does not replace the shared crop or resize target.
Control changes update only the preview; **Optimize Selected** processes the highlighted
image, while **Optimize All** commits one settings snapshot to the entire queue.
The Original view always shows the unmodified source.

### Processing and saving

Each tool has explicit **Clean**, **Optimize**, or **Watermark** actions for **Selected**
and **All**. Queue rows support standard macOS multi-selection: click one row,
Command-click to toggle, or Shift-click a contiguous range. The last clicked row is
the preview primary; Selected actions capture the selected IDs and current settings
before processing, so changing the selection during a run does not change its target.
Clean All prepares every inspected file still waiting for cleanup, including items
hidden by a findings filter. Clean's no-matching-metadata action is labelled
**Prepare Copies** or **Prepare Selected Copy** instead of claiming metadata was removed.

**Save All…** is green in the top toolbar and results header when prepared outputs
are available. **Save Selected…** saves the selected prepared output(s): one file is
saved directly, while multiple selected files are written separately into one chosen
folder with collision-safe filenames. Save, Save Selected and Save All share the same
green treatment and width. Saving does not process pending settings, and these actions
are disabled during processing. Clean has a fixed processing footer below its
image and video queues; Optimize and Watermark keep their processing buttons below
the scrolling settings. Image Optimize/Watermark retain their existing automatic
initial processing on import; use Selected or All to process later setting changes.

Optimize queue rows show each source's original dimensions until that item's current
preview/output has been rendered. Selecting another image or video therefore updates
the dimension label to that source immediately; the previous item's crop dimensions
are not reused.

Selecting Logo for the first time uses **90% opacity, 0° rotation, 40% scale,
Centre placement and 2.5% safe margin** for images and videos. Text keeps its previous
defaults. Each kind keeps its own appearance edits during the session; explicit saved
image presets still override these defaults. A logo file must be chosen separately.

Finder's Open With command sends supported images or videos to the corresponding media
mode of the active tool.
The header settings gear can remember a default output folder using a security-scoped
bookmark. Clear it in Settings to return Save All to asking for a destination each time.

## Uninstalling

Drag the app to the Trash. Window position and optional watermark preset settings are
stored in the app sandbox, but no image queue/history is recorded. To remove those
preferences too:

```bash
rm -rf ~/Library/Containers/pro.kechil.app
```
