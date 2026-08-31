# Kechil PRO

[![Latest release](https://img.shields.io/github/v/release/AminudinMurad/kechil-pro?display_name=tag&sort=semver)](https://github.com/AminudinMurad/kechil-pro/releases/latest)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](docs/INSTALL.md)
[![No AI co-author metadata](https://github.com/AminudinMurad/kechil-pro/actions/workflows/no-ai-coauthor-metadata.yml/badge.svg)](https://github.com/AminudinMurad/kechil-pro/actions/workflows/no-ai-coauthor-metadata.yml)

A private, local-first macOS image and video utility for cleaning metadata,
optimising and resizing media, applying visible watermarks, and estimating real
output sizes as settings change.

A native macOS media utility with three tools. Every tool has separate Images
and Videos modes with independent queues:

- **Clean** — remove EXIF, GPS, IPTC, XMP, C2PA/Content Credentials, maker notes,
  text and timestamps.
- **Optimize** — crop, resize, optimise and convert images; trim, crop, resize,
  change codec/frame rate/audio, or target an estimated maximum size for videos.
- **Watermark** — batch text or logo watermarks with live image/video preview,
  colour, shadow, safe margin, nine positions, tiling, opacity, rotation and scale.

Kechil never uploads media. It can download one direct image or video URL supplied by
the user into a temporary local file; processing and final saving happen on the Mac.
The sandbox allows outbound client access for those explicit fetches, but no inbound
server access. There is no telemetry, licensing call or background upload.

The dashboard uses a fixed-width three-tool sidebar. Clean, Optimize and Watermark each
expand to Images and Videos, and switching modes preserves their separate queues. The
settings gear includes fixed-width dashboard-height presets, a sandbox-safe
default media save folder, version/copyright information and an inactive update
placeholder. Setting a default folder makes Save All write there directly with
collision-safe filenames.

Queue rows use standard macOS multi-selection: click one row, Command-click to
toggle rows, or Shift-click to select a contiguous range. The last clicked row
remains the preview primary, while Clean/Optimize/Watermark Selected acts on the
whole selected set. Save Selected saves one prepared output directly; with several
selected prepared outputs it asks once for a folder and writes each file separately
with collision-safe filenames, preserving each output's format and extension.
Save, Save Selected and Save All share the same green action treatment and width.

## Download v1.0.0

The initial public release is a universal macOS build for Apple Silicon and Intel:

- [Download the DMG](https://github.com/AminudinMurad/kechil-pro/releases/download/v1.0.0/Kechil-PRO-v1.0.0-macos-universal.dmg)
- [Download the ZIP](https://github.com/AminudinMurad/kechil-pro/releases/download/v1.0.0/Kechil-PRO-v1.0.0-macos-universal.zip)
- [Read the complete release notes](https://github.com/AminudinMurad/kechil-pro/releases/tag/v1.0.0)

Both archives have SHA-256 sidecars. This first package is ad-hoc signed for local
distribution and is not notarised; see [INSTALL.md](docs/INSTALL.md) for the
Gatekeeper and checksum steps.

Every empty route and the workspace toolbar include **Paste URL**. The field accepts a
direct `http(s)` image/video URL, a local `file://` URL or an absolute path. The
clipboard is read only when its icon is clicked. Remote sources are downloaded to a
temporary local file before entering the same on-device processing queue.

Kechil intentionally rejects YouTube, Facebook and Instagram page or delivery URLs.
It does not scrape webpages, accept social-account cookies or reconstruct protected
playback streams. Export media you own through YouTube Studio, Google Takeout or Meta
Accounts Center, then add the resulting local file to Kechil.

The About card links to the GPL-3.0 terms and provides GitHub, GitHub Sponsors,
Ko-fi and PayPal links for supporting open-source development. The Updates button
is currently a placeholder and performs no network request.

## Clean is lossless where that is technically possible

For JPEG, PNG and WebP, **Clean** changes the container only: compressed pixel data is
copied verbatim, not decoded and re-encoded. `Tests/verify_algorithm.py` asserts both
metadata removal and byte-identical decoded pixels across 42 checks, including
progressive JPEG metadata, post-EOI data, JFXX/MPF carriers and unknown PNG/WebP
chunks.

Other containers use ImageIO. When its verified output requires re-encoding, the UI
labels that fact instead of making the Clean tool's lossless claim.

Video Clean rewrites supported MOV/MP4/M4V containers without re-encoding when the
system exporter permits it, then reopens and re-probes the copy. It reports
“Container cleaned; frames not re-encoded” because media playback, timing, dimensions,
tracks and supported metadata are verified, while encoded-frame identity is not claimed.

Optimize and Watermark intentionally re-render pixels. Their outputs are always passed
through metadata removal before saving.

Clean shows a selected-source output-size estimate once inspection and the requested
scope are ready. It measures the same cleaner or unchanged-copy path used by Clean.
Image Watermark fully encodes the selected image with the current settings, while Video
Watermark encodes a real short sample with the current codec, audio and quality settings
and projects that result across the duration. Changing settings cancels stale work and
remeasures the selected source; after export, the card changes to the prepared output's
measured byte count. No output is saved merely by changing a setting.

Video target-size mode budgets bitrate from the selected trim duration, audio rate and
container reserve. Smart can lower resolution when the requested size would otherwise
cause severe artifacts; Keep Resolution retains dimensions and accepts lower visual
quality. The UI labels the result as an estimate because codec rate control and source
complexity can change final bytes.

Optimize queue rows report each source's original dimensions until that item's current
preview/output has actually been rendered. Selecting another image or video therefore
shows that item's own source dimensions immediately instead of retaining the previous
crop result.

## AI provenance: evidence, not a trust verdict

Kechil PRO reads common provenance carriers and reports standard IPTC Digital Source
Type declarations, C2PA/JUMBF claims, XMP, prompts, models, edit history and common
generator fields. Findings are marked as declared, stated or inferred. It deliberately
does not mistake `computationalCapture` (for example phone HDR) for Generative AI.

This is **not** C2PA cryptographic validation: signatures, trust chains, revocation and
asset bindings are not validated. Brotli-compressed assertions may be located without
being decoded.

Invisible in-pixel watermarks such as SynthID are not metadata and are not removed.

## Build and verify

Requires macOS 13+ and a full Xcode installation. There is no Xcode project or package
manager dependency; WebP support uses the pinned, vendored libwebp source in
`vendor/libwebp`.

```bash
tools/check.sh                    # type-check plus all deterministic checks
tools/build-app.sh                # native build
UNIVERSAL=1 SIGNED=1 tools/build-app.sh
tools/make-dmg.sh                 # fresh signed universal DMG + SHA-256 sidecar
tools/make-zip.sh                 # signed universal app ZIP + SHA-256 sidecar
```

`tools/check.sh` verifies every vendored libwebp source-file hash before it compiles.
`tools/make-dmg.sh` refuses to package a signed build without sandboxing and the
outbound client entitlement, or if an inbound network-server entitlement is present.

The resulting app is at `build/Kechil PRO.app`; releases are in `releases/`.

## Release caveat

Default signing is ad hoc for local QA. A public release still needs a Developer ID
identity and notarisation.

## Project layout

```
Sources/    SwiftUI app, image/video clean, optimize and watermark pipelines
Tests/      deterministic Swift and Python correctness tests
vendor/     pinned libwebp 1.6.0 source and SHA-256 manifest
tools/      check, build, package and generated-artwork tools
App/        bundle metadata and sandbox entitlements
```

GPL-3.0 — see [LICENSE](LICENSE). Third-party notices are in [NOTICE.md](NOTICE.md).
