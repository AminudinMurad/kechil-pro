# Kechil PRO v1.0.2 (build 3)

Released 10 September 2026.

Kechil PRO v1.0.2 makes image resizing more predictable and saved filenames more
useful, while retaining local processing and original-file protection.

## What changed

- **Locked aspect ratio for image resize.** Image Optimize now includes a
  **Width × Height** resize mode. The aspect-ratio lock is on by default, so changing
  width recalculates height and changing height recalculates width from the cropped
  image. Unlock it when independent dimensions are required.
- **Custom converted-image filename text.** Settings can replace the existing
  `-kechil` appendage, reset it to the default, and preview the resulting filename.
  Unsafe path characters are sanitised.
- **Actual saved resolution in filenames.** Enable **Append saved resolution to
  filename** to add the actual finished image or video's `WIDTHxHEIGHT` value to
  Optimize and Watermark outputs. Kechil reads the final file dimensions; users do
  not enter a fixed resolution.
- **Reachable Settings on compact displays.** The expanded panel scrolls so every
  preference remains available at the minimum supported workspace height.

## Downloads

- [Universal DMG](https://github.com/AminudinMurad/kechil-pro/releases/download/v1.0.2/Kechil-PRO-v1.0.2-macos-universal.dmg) — 5,211,363 bytes<br>
  SHA-256: `361383ca42e08dc3d341f77ca9b035a829d1001ad1b9cd96a49813845a3a5b69`
- [Universal ZIP](https://github.com/AminudinMurad/kechil-pro/releases/download/v1.0.2/Kechil-PRO-v1.0.2-macos-universal.zip) — 4,516,668 bytes<br>
  SHA-256: `3fa52b711a2edf0e3a03c680dc0997d864512a0db8b9b58254bbdcf3006aba18`
- [DMG checksum sidecar](https://github.com/AminudinMurad/kechil-pro/releases/download/v1.0.2/Kechil-PRO-v1.0.2-macos-universal.dmg.sha256)
- [ZIP checksum sidecar](https://github.com/AminudinMurad/kechil-pro/releases/download/v1.0.2/Kechil-PRO-v1.0.2-macos-universal.zip.sha256)

The DMG is the recommended installation. Open it and drag **Kechil PRO** to
**Applications**. The ZIP contains the same universal app bundle.

## Verification

- App version/build: `1.0.2 (3)`
- Architectures: `x86_64 arm64`
- 121 real-media interaction assertions passed, including final output-resolution
  naming for image and video Optimize and Watermark.
- Eight dedicated converted-filename naming assertions passed.
- 40 native SwiftUI snapshots rendered. The new aspect-lock and Settings filename
  controls were visually inspected.
- DMG verification, its read-only mounted app, ZIP integrity and its extracted app
  passed strict/deep signature, sandbox entitlement, architecture and version checks.
- Originals are never overwritten and existing destination files remain protected.

## Signing and privacy boundary

This package is **ad-hoc signed** for local distribution. It is not signed with an
Apple Developer ID and is not notarised by Apple. On first launch, Control-click the
app in Finder and choose **Open**. If macOS still blocks it, use **System Settings →
Privacy & Security → Open Anyway** only for a copy downloaded from this official
release.

Media processing remains on the Mac. The sandbox permits user-selected files and
outbound client access only for a direct media URL the user explicitly supplies; it
does not permit an inbound network server. Kechil does not upload media, use telemetry
or download updates automatically.

## Build from source

A full Xcode installation is required:

```bash
tools/check.sh
UNIVERSAL=1 SIGNED=1 tools/build-app.sh
tools/make-dmg.sh
tools/make-zip.sh
```

See the [installation guide](INSTALL.md), [changelog](../CHANGELOG.md), and
[development handoff](DEVELOPMENT_HANDOFF.md) for more detail.
