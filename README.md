# Kechil PRO

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
is currently an offline placeholder and performs no network request.

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

Video target-size mode budgets bitrate from the selected trim duration, audio rate and
container reserve. Smart can lower resolution when the requested size would otherwise
cause severe artifacts; Keep Resolution retains dimensions and accepts lower visual
quality. The UI labels the result as an estimate because codec rate control and source
complexity can change final bytes.

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
