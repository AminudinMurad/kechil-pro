# Batch actions and logo defaults QA — 2026-08-31

## Scope

Follow-up to the batch-crop delivery: prominent green Save All in the toolbar and
results headers, multi-file Save Selected, explicit Clean/Optimize/Watermark All and
Selected, fixed processing footers, and image/video logo watermark defaults. Version/
build remain 1.0.0 (1). The public GitHub release was published after the final
source gate; no application was installed or replaced, and no originals were
changed.

Queue selection follows macOS conventions: a plain click selects one row,
Command-click toggles a row, and Shift-click selects a range. The last clicked row
remains the preview primary, while Selected processing captures the selected IDs and
settings before work starts; changing the selection cannot change the running target.
All continues to use the whole queue. Clean All processes all inspected files still
waiting for cleanup; already-prepared Clean outputs are not unnecessarily regenerated.
Existing Clean metadata-scope changes still invalidate old results and require a fresh
review.

Save Selected uses the existing per-item save service, with readiness checked before
opening a destination dialog. For multiple selected prepared outputs, one folder
dialog is used and each file is written separately with a collision-safe filename;
unready selected files are skipped and the button reports the ready count. Save All
and Save Selected are unavailable while processing; a selected set with no prepared
output cannot be saved even if other queue members are ready. Saving does not process
pending settings. Image
Optimize/Watermark keep their existing automatic initial conversion on import.

Save, Save Selected and Save All use the same green treatment and exact width across
the toolbar, result headers, inspectors and queue rows. Optimize image/video rows
show the selected source's original dimensions until its current preview/output is
actually rendered.

For no-matching-metadata Clean inputs, the truthful action remains Prepare Copies
or Prepare Selected Copy. Originals are not described as cleaned when nothing changes.

Clean and Watermark also expose a selected-source size card before saving. Clean
measures its same-path cleaner or unchanged-copy result; Image Watermark fully
encodes the current settings; Video Watermark encodes a real short sample and
projects it across the full duration. A prepared output replaces the estimate with
its measured bytes, and changing settings never writes an output.

Logo defaults for images and videos: opacity 90%, rotation 0 degrees, scale 40%,
Centre placement, safe margin 2.5%. Text defaults remain unchanged. Session-only
appearance profiles preserve edits when toggling Text/Logo; explicit saved image
presets override defaults, and no logo bytes/paths are stored in presets.

## Verification status

The final full `tools/check.sh` run passed, including **115 media interaction
assertions**, **9 shared selection assertions** and **29 shared action-state
assertions**. The final run includes the exact-width and multi-selection changes. A
visual review identified
an offscreen Video Clean footer at minimum height. The revised layout constrains
that split pane and places Optimize/Watermark actions outside scrolling settings.
Video Optimize reserves room for the output header and queue by allowing its
preview/trim region to scroll at compact heights.

All **39 native SwiftUI snapshots** rendered successfully after the layout fixes.
The six ready routes, image/video Clean review footers, processing state, dark
action states, both logo-default forms, and the dedicated live size-estimate states
were visually inspected. Optimize and Watermark Selected/All actions are visible
at minimum window height without scrolling the settings. Video Clean's footer now
stays inside the window. Compact Video Optimize keeps its output header and queue
visible; lower trim details are reachable by scrolling the preview region.

Final logs: `build/qa-batch-actions-2026-08-31/checks.log` and `snapshots.log`.
Screenshots: `build/ui-snapshots/batch-*.png`.

The replacement package was built and fully verified after the final source gate:

- Artifact: `releases/Kechil-PRO-v1.0.0-macos-universal.dmg`
- Sidecar: `releases/Kechil-PRO-v1.0.0-macos-universal.dmg.sha256`
- SHA-256: `0ddf449f7e3d56b19b9a0ea71e863e69529bee79a9247e0e775987fef3536516`
- Size: `5,050,763` bytes
- ZIP: `releases/Kechil-PRO-v1.0.0-macos-universal.zip`
- ZIP SHA-256: `de35f12354cef7d25a4a75deaafe54cd5bf2426d1dd2624616e6cede8de31a5f`
- ZIP size: `4,383,928` bytes; `unzip -tqq` and archive metadata checks pass.
- Version/build: `1.0.0 (1)`; executable architectures: `x86_64 arm64`
- `hdiutil verify` and the sidecar both pass.
- The mounted, read-only app passes strict/deep signature verification. It has
  app sandbox, user-selected read/write and outbound network-client entitlements;
  no network-server entitlement. The volume contains only `Kechil PRO.app` and
  the Applications shortcut.

It is ad-hoc signed, not notarised, and publicly published at
https://github.com/AminudinMurad/kechil-pro/releases/tag/v1.0.0. No app was
installed or replaced during this package verification. A temporary generated build
copy was moved to Trash after verification; the already-running Applications copy
was intentionally not touched because it has a live queue.

The public source repository is https://github.com/AminudinMurad/kechil-pro. The
remote `main` branch and peeled `v1.0.0` tag matched the release source commit at
publication. GitHub checksum sidecars were downloaded and compared byte-for-byte
with the local sidecars, and the no-AI co-author metadata workflow passed.

The pre-existing DMG failed its old sidecar
check at the start of packaging: actual SHA-256
`6de95473d9468f1ee88317d0649341a4dffd1ea94b5da343e47b3bb73893c0c1`,
while its earlier sidecar recorded
`95adf2275ab6888479c20d17013e3a82848b907d5e717037983aa157bd35ac78`.
The cause was not established. The old pair was preserved under
`build/qa-batch-actions-2026-08-31/previous-package/`. Never use the earlier crop
QA report's checksum as evidence for the replacement build.

## Evidence and boundaries

- Model tests use real image/video files and output encoding, not placeholder rows.
- Tests cover captured Selected IDs, unchanged other image outputs, unchanged
  other prepared video output bytes/URLs, All behavior, no selection, busy states,
  no-logo guards, selected-save readiness, per-kind logo appearance restoration,
  exact Clean estimates, full image Watermark encoding, and real video Watermark
  sample remeasurement.
- Snapshot fixtures use synthetic presentation-only results; their placeholder
  output bytes/URLs are never saved or processed. Native renders cover all six
  routes, minimum window height, unavailable/processing states, dark appearance,
  and logo defaults. They do not replace real-media processing checks.
- This is not a broad responsiveness benchmark, physical Intel runtime test,
  or deeper ISO-BMFF cleanup milestone. A local ad-hoc-signed package is not a
  Developer ID signed/notarized public release.
