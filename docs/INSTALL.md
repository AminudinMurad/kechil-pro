# Installing Kechil PRO

## Requirements

macOS 13 (Ventura) or later, on Apple Silicon or Intel.

## From a disk image

Verify the sidecar before opening the release, then drag the app to Applications:

```bash
shasum -a 256 -c Kechil-PRO-vX.Y.Z-macos-universal.dmg.sha256
open Kechil-PRO-vX.Y.Z-macos-universal.dmg
```

An ad-hoc build is not notarised. Only bypass Gatekeeper for a copy you trust; a public
release should be Developer ID signed and notarised.

## From source

A full Xcode installation is required for SwiftUI macros. Then run:

```bash
tools/check.sh
UNIVERSAL=1 SIGNED=1 tools/build-app.sh
tools/install-app.sh
tools/make-dmg.sh
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

This writes nine PNGs to `build/ui-snapshots/`, including the 940 × 650 minimum-height
layout. Set `SKIP_APP_BUILD=1` only when the current host-architecture build objects are
already known to be current.

## Privacy check

The sandbox allows only user-selected read/write files and no network entitlement:

```bash
codesign -d --entitlements - "build/Kechil PRO.app"
```

## Using the tools

- **Clean:** choose Images or Videos, inspect the supported metadata findings, then save
  individual or batch cleaned copies. JPEG/PNG/WebP image outputs preserve decoded pixels;
  supported video containers use a verified pass-through rewrite when available.
- **Optimize:** crop/resize/convert images, or trim/crop/resize/compress videos. Video
  target MB mode explains whether it protects quality by lowering resolution or keeps
  resolution at the cost of visual quality. Size is an estimate, never an exact-byte claim.
- **Watermark:** preview text or a logo before export, then position, colour, rotate,
  scale or tile it. Video marks are static across the full duration. Image presets retain
  settings only; they do not retain logo bytes, file paths or batch history.

Originals are never modified in place. Completed output data is released after saving.
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
