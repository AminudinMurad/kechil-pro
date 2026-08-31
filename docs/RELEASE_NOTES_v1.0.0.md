# Kechil PRO v1.0.0

Kechil PRO is a private, local-first macOS utility for cleaning image and video
metadata, optimising media, applying visible watermarks, and measuring realistic
output sizes as settings change. This is the initial public release.

## Downloads

The release is a universal build for Apple Silicon and Intel Macs running macOS 13
(Ventura) or later.

| Package | Download | Size | SHA-256 |
| --- | --- | ---: | --- |
| Recommended DMG | [Kechil-PRO-v1.0.0-macos-universal.dmg](https://github.com/AminudinMurad/kechil-pro/releases/download/v1.0.0/Kechil-PRO-v1.0.0-macos-universal.dmg) | 5,050,763 bytes | `0ddf449f7e3d56b19b9a0ea71e863e69529bee79a9247e0e775987fef3536516` |
| App ZIP | [Kechil-PRO-v1.0.0-macos-universal.zip](https://github.com/AminudinMurad/kechil-pro/releases/download/v1.0.0/Kechil-PRO-v1.0.0-macos-universal.zip) | 4,383,928 bytes | `de35f12354cef7d25a4a75deaafe54cd5bf2426d1dd2624616e6cede8de31a5f` |

Download the matching `.sha256` sidecar beside each archive and verify it before
opening the app:

```bash
shasum -a 256 -c Kechil-PRO-v1.0.0-macos-universal.dmg.sha256
shasum -a 256 -c Kechil-PRO-v1.0.0-macos-universal.zip.sha256
```

The app bundle is ad-hoc signed for this initial local distribution. It is not
Developer ID signed or notarised, so macOS may require the user to approve the
trusted download through the normal Finder/Open workflow. The release does not
claim notarisation.

## What is included

### Clean

- Separate Images and Videos queues with inspect-first review.
- Image scopes for All metadata, AI metadata, EXIF and GPS.
- Video scopes for Content Credentials, descriptive metadata, XMP, location and
  container dates.
- JPEG, PNG and WebP cleaning that copies compressed pixel data without decoding and
  re-encoding; preservation checks cover orientation and protected pixel samples.
- Verified ImageIO handling for supported additional image containers, with explicit
  limitation reporting where re-encoding or multi-frame preservation needs care.
- MOV, MP4 and M4V pass-through container cleaning when the system exporter supports
  it, followed by output re-probing and truthful verification labels.
- No-match inputs produce explicitly labelled unchanged copies rather than claiming
  metadata was removed.

### Optimize

- Image crop, resize, conversion and WebP quality/method controls.
- Independent custom crop width and height, crop focus, linked target ratio and a
  separate policy for enlarging smaller images to fill a target.
- Image output formats including WebP, JPEG, PNG, HEIC, AVIF, TIFF and GIF where the
  system encoder supports them.
- Video trim with In and Out markers, crop focus/aspect, resolution and no-upscale
  controls, frame-rate selection, H.264/HEVC, audio policy, MP4/MOV output and
  quality or target-size modes.
- Video target-size estimates budget bitrate from duration, audio and container
  overhead. Smart mode may reduce resolution to protect quality; Keep Resolution
  makes the trade-off explicit.

### Watermark

- Text or logo watermarks for images and videos.
- Colour, shadow, opacity, rotation, scale, safe margin, nine positions and tiling.
- Preview/output comparison for images and full-duration static overlays for videos.
- Image Watermark fully encodes the current image for its live estimate.
- Video Watermark encodes a real short sample with the current codec, audio and
  quality settings, then projects that measured rate over the complete duration.
- Watermark presets retain settings only; logo bytes, paths, queued files and output
  history are not stored.

## Batch workflow

All six routes have independent queues and explicit Selected/All actions. Queue rows
support normal macOS multi-selection: click one row, Command-click to toggle, or
Shift-click a range. The last clicked row remains the preview primary while Selected
processing captures the complete selected set and its settings.

Save Selected saves one prepared output directly. When several outputs are selected,
Kechil asks once for a destination folder and writes each prepared file separately,
keeping its format and extension and avoiding filename collisions. Save All follows
the same collision-safe rules. Save, Save Selected and Save All use the shared green
action treatment; dimensions show each source's original values until its current
preview/output has been rendered.

## Privacy and security boundary

- Processing and final saving happen on the Mac; media is never uploaded.
- Direct HTTP(S) downloads happen only after the user supplies an explicit URL and
  are held in a temporary local file.
- YouTube, Facebook and Instagram page or delivery URLs are rejected. Kechil does
  not scrape webpages, accept account cookies or reconstruct protected streams.
- The signed app has App Sandbox, user-selected read/write access and outbound
  network-client access for explicit direct-media downloads. It has no inbound
  network-server entitlement, telemetry, analytics, licensing request or background
  update check.
- Originals are never overwritten. Saving uses separate collision-safe destinations.
- Invisible in-pixel watermarks such as SynthID are not metadata and are not removed.

## Verification

The release source passed the complete local gate:

- Swift warnings-as-errors type-check: passed.
- Shared batch-action checks: 29 assertions passed.
- Shared multi-selection checks: 9 assertions passed.
- Real-media image/video interaction checks: 115 assertions passed.
- Native SwiftUI snapshot renderer: 39 PNG snapshots rendered; action, selection,
  crop-dimension and live-estimate states were visually inspected.
- Vendored libwebp 1.6.0 source manifest: passed.
- DMG `hdiutil verify`: passed.
- DMG and ZIP SHA-256 sidecars: passed.
- Universal executable architectures: `x86_64 arm64`.
- Mounted DMG app: deep/strict code-signature verification passed.
- Mounted entitlements: sandbox and outbound client present; inbound server absent.

## Build from source

Requires a full Xcode installation on macOS 13 or later:

```bash
tools/check.sh
UNIVERSAL=1 SIGNED=1 tools/build-app.sh
tools/make-dmg.sh
tools/make-zip.sh
```

The repository has no Xcode project or package-manager dependency. WebP encoding is
linked from the pinned libwebp source under `vendor/libwebp`, and the source hash is
checked before the correctness gate.

## Known boundaries

Clean removes the metadata Kechil detects and verifies within its supported scope; it
does not make a file untraceable. C2PA findings are evidence only: this release does
not validate certificate chains, trust roots, revocation, signatures or asset
bindings. Some image containers may require a re-encoded path, and video Clean's
frame identity is not claimed merely because its container rewrite succeeds. The UI
labels those limitations rather than silently broadening the guarantee.

## Licence and support

Kechil PRO is released under the GNU GPL-3.0. See [LICENSE](../LICENSE) and
[NOTICE.md](../NOTICE.md). Support links are available through the repository's
Sponsor button and the in-app About/support card.
