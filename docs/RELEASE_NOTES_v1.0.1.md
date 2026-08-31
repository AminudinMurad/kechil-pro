# Kechil PRO v1.0.1 (build 2)

Kechil PRO v1.0.1 is the first follow-up to the initial public release. It brings
the media workflows to a consistent batch model, measures real output sizes as
settings change, tightens the compact MacBook layouts, and adds a Klik PRO-style
GitHub release check in Settings.

## Downloads

This is one universal macOS app for Apple Silicon and Intel Macs running macOS 13
(Ventura) or later. The DMG is the recommended Finder installation path; the ZIP
contains the same app as an alternative.

| Package | Download | Size | SHA-256 |
| --- | --- | ---: | --- |
| Recommended DMG | [Kechil-PRO-v1.0.1-macos-universal.dmg](https://github.com/AminudinMurad/kechil-pro/releases/download/v1.0.1/Kechil-PRO-v1.0.1-macos-universal.dmg) | 5,161,305 bytes | `a5dfd77361dbedf5bc08ef1090706619da0b9292f774c46bc376d14c8bd72452` |
| App ZIP | [Kechil-PRO-v1.0.1-macos-universal.zip](https://github.com/AminudinMurad/kechil-pro/releases/download/v1.0.1/Kechil-PRO-v1.0.1-macos-universal.zip) | 4,476,106 bytes | `f7f5af08798561959d236412c854fedeb235b88c7c2528a08f0f02959bb11a2f` |

Download the matching `.sha256` sidecar beside each archive and verify it before
opening the app:

```bash
shasum -a 256 -c Kechil-PRO-v1.0.1-macos-universal.dmg.sha256
shasum -a 256 -c Kechil-PRO-v1.0.1-macos-universal.zip.sha256
```

The package is ad-hoc signed for local distribution. It is not signed with an
Apple Developer ID and is not notarised, so macOS may require the normal manual
approval flow for a downloaded app. The release does not claim notarisation.

## What changed

### Real output-size estimates

- Clean measures the same verified cleaner or explicitly unchanged-file path that
  the action will prepare.
- Image Optimize fully encodes the selected image with the current crop, resize,
  output format and quality settings. Changing a setting remeasures the estimate;
  it does not replace a prepared queue output until Optimize Selected or Optimize
  All is pressed.
- Image Watermark fully encodes the current image watermark output for its estimate.
- Video Watermark encodes a real short sample with the selected codec, audio,
  container and quality settings, then projects that measured rate over the full
  duration.
- Selecting another source immediately returns its own original dimensions until a
  new preview or output has rendered. A previous item's crop dimensions are never
  reused as the new source's dimensions.

### Consistent batch workflows

- Every tool has independent Images and Videos routes, queues, and Selected/All
  actions.
- Plain click, Command-click and Shift-click provide familiar macOS multi-selection.
- Save Selected writes one ready output directly. With multiple ready outputs it
  asks once for a folder and writes separate collision-safe files, preserving each
  format and extension; it does not force a ZIP extraction step.
- Save All writes every ready output in the queue to the chosen folder. Originals are
  never overwritten, and save actions never process pending settings.
- Clean no-match actions are labelled **Re-Save Selected** and **Re-Save All** so the
  app does not claim that metadata was removed when no selected metadata matched.
- Save, Save Selected and Save All share the same green action treatment and compact
  sizing across toolbar, result headers and queue rows.

### Compact workspace and media safety

- Image and Video Optimize use the same queue-first layout with aligned output
  controls and a shorter preview/trim region for compact 13-inch windows.
- Empty Image Optimize and Image Watermark settings columns remain hidden until a
  source is queued, matching the Video routes.
- Video Clean re-probes exporter results, including no-match inputs that must remain
  unchanged and saveable. Clean output labels distinguish metadata removal from
  unchanged-file preparation.
- Watermark and Optimize outputs pass through the supported metadata-removal path
  before the final save; Clean keeps byte-preserving paths where technically safe.

### Klik PRO-style release checking

- Settings now includes **Automatically check for updates**, enabled by default and
  independently switchable.
- At launch, the app reads the public GitHub latest-release endpoint and compares its
  version with the installed app. It never downloads an update automatically.
- The Updates button reports **Update ready**, **You're up to date**, or a connection
  error. Opening the release page is always a user action.
- The check sends no media, account information, telemetry or licensing data. The
  existing sandbox network-client entitlement is used only for explicit direct-media
  URL imports and this public release lookup; there is no network-server entitlement.

## Verification

The final source gate and release package checks passed on 31 August 2026:

| Area | Result |
| --- | --- |
| Full `tools/check.sh` gate | Passed with warnings-as-errors Swift type-check |
| Shared action contracts | 29 assertions passed |
| Update version comparison | 6 assertions passed |
| Queue selection | 9 assertions passed |
| Real media interactions | 117 assertions passed across image/video Clean, Optimize, Watermark, playback, saving and source preservation |
| Native UI snapshots | 39 PNG snapshots rendered and inspected, including compact layouts and Settings |
| DMG | `hdiutil verify` valid; read-only mount and strict/deep signature verification passed |
| ZIP | `unzip -tqq` passed; archive contains no Finder metadata; extracted app signature passed |
| Architecture | Universal `x86_64 arm64` |
| Entitlements | App Sandbox and outbound network client present; inbound network server absent |
| Package sidecars | Both SHA-256 sidecars match the published archives |

The release source and package are intended to be reproducible with the repository's
documented build scripts. The vendored libwebp 1.6.0 source is checked against its
tracked hash manifest before compilation.

## Privacy and known boundaries

Processing and final saving stay on the Mac. Direct HTTP(S) downloads happen only
after the user supplies an explicit media URL and are held in a temporary local file.
Kechil rejects YouTube, Facebook and Instagram page or delivery URLs and does not
scrape webpages or reconstruct protected streams.

Clean removes and verifies metadata within its supported scope; it does not make a
file untraceable. C2PA findings are evidence only: this release does not validate
certificate chains, trust roots, revocation, signatures or asset bindings. Invisible
in-pixel watermarks such as SynthID are not metadata and are not removed. Some image
containers may require re-encoding, and video Clean does not claim frame identity
merely because a container rewrite succeeds.

## Build from source

Requires a full Xcode installation on macOS 13 or later:

```bash
tools/check.sh
UNIVERSAL=1 SIGNED=1 tools/build-app.sh
tools/make-dmg.sh
tools/make-zip.sh
```

Kechil PRO has no Xcode project or package-manager dependency. WebP encoding is
linked from the pinned source under `vendor/libwebp`.

## Licence and support

Kechil PRO is released under the GNU GPL-3.0. See [LICENSE](../LICENSE) and
[NOTICE.md](../NOTICE.md). Support links are available through the repository's
Sponsor button and the in-app About/support card.
