# Kechil PRO — full next-work plan for image and video Clean

Prepared: 31 August 2026
Status: Milestones 0–2 implemented in the working tree; current release evidence is
maintained in `docs/DEVELOPMENT_HANDOFF.md` and the v1.0.0 release notes.
Scope: Clean → Images and Clean → Videos, plus their shared intake, settings, reporting and saving behaviour

## 1. Intended outcome

Make Clean a dependable local workflow in which users can inspect a file, understand the proposed removal, clean only what they selected, verify the result, and save a new copy with an accurate receipt.

The [feature audit](</Users/aminudin/Documents/Business/Products/Kechil PRO/docs/CLEAN_FEATURE_PARITY_AUDIT_2026-08-31.md>) contains the website observations, current-source evidence and limitations behind this plan. The [previous next-agent plan](</Users/aminudin/Documents/Business/Products/Kechil PRO/docs/NEXT_AGENT_PRODUCT_IMPROVEMENT_PLAN.md>) remains a useful detailed video-engine reference. This document supplies the combined image/video execution order and resolves stale assumptions in that older plan.

Success is not merely having matching selection cards. Every visible cleaning option must have a defined scope, a tested implementation, a preservation policy and a truthful result.

Current delivery status: milestones 0–2 are implemented in the working tree. The
expanded `tools/check.sh` gate passes, including bounded PNG AI decoding, mixed-field
protection, orientation/pixel/frame preservation checks, video no-op/scope-isolation
checks, structural C2PA evidence, cancellation propagation and final-save byte
identity. Image and video imports now stop after inspection, cached selection changes
create plans only, and cleanup requires an explicit action. The deeper raw container
reader/patcher, complete preservation verification, performance profiling and optional
writing/naming work remain future milestones. The earlier milestone package was not
the release record; the verified v1.0.0 universal artifacts are recorded separately
in the development handoff and release notes.

## 2. Boundaries and defaults

1. Keep processing and saving on the Mac. Existing direct-URL downloads remain deliberate user actions; do not add uploads, telemetry, accounts or remote processing.
2. Never overwrite originals. Do not mutate an imported source during inspection or cleaning.
3. Preserve the existing six routes. Inspection belongs inside Clean, not a new top-level tool. Do not modify Optimize, trim or Watermark pipelines as part of this project unless a shared component genuinely requires it.
4. Preserve the recent full-area click targets, explicit clipboard icon, matching button sizes, consistent font hierarchy, wrapped descriptions, top-aligned icons and centred empty-state layouts.
5. Do not add an Offline badge or automatically insert “Processed by Kechil” metadata.
6. Preserve colour rendering, displayed orientation and every frame/page by default. If privacy and rendering requirements conflict, explain the exact tradeoff before allowing the operation.
7. No silent image re-encoding, format conversion or frame flattening in Clean. An unsupported safe-clean case should remain inspectable and return a useful explanation. A separately authorised conversion can use Optimize later.
8. No video re-encoding in Clean. A remux fallback may be offered only when explicitly selected, correctly labelled and verified to the extent actually supported.
9. C2PA presence is not proof of AI generation. Readable claims are not validated signatures. Do not promise SynthID removal or control of another platform's labels.
10. Keep the current product version/build unless separately requested. Test compilation is part of implementation; installation, distribution packaging, signing/notarisation and a new DMG are separate authorised release steps.
11. Preserve unrelated dirty-worktree changes. Do not commit, reset or discard existing work as a side effect of implementing this plan.

## 3. Delivery sequence

| Milestone | Deliverable | Depends on | Completion gate |
|---|---|---|---|
| 0 | Reproducible fixture baseline and current-behaviour measurements | None | Failures, supported cases and unknowns documented without guessing |
| 1 | Safety and truthful-reporting fixes | 0 | Existing modes cannot silently over-delete, flatten, re-encode or claim unsupported verification |
| 2 | Typed inspection and explicit review workflow for both media types | 1 | Import inspects only; selections update a cached plan; Clean is explicit |
| 3 | Deterministic cleaning and preservation verification | 2; video/image engine work can run independently | Planned changes verified; unselected and protected data preserved; saved output matches verified artifact |
| 4 | Complete inspector, receipts and responsiveness pass | 2–3 | Clear findings/statuses, bounded work, working cancellation and usable compact layouts |
| 5 | Naming previews, local profiles and optional archive export | 4 | Collision-safe output; predictable settings; no private-value persistence by surprise |
| 6 | Optional image metadata/date/location writing | 3–5 | Explicit writes round-trip correctly; unsupported formats cannot claim success |
| 7 | Acceptance QA and release handoff | Required milestones above | Automated, manual, performance and package evidence kept distinct |

Milestones 0–4 form the essential Clean upgrade. Milestones 5–6 are advanced productivity work and must not delay correcting misleading cleaning behaviour.

## 4. Milestone 0 — fixtures, baselines and acceptance contracts

### Work

- Record current source revision/dirty files, OS/toolchain, hardware and test commands. Preserve existing user changes.
- Turn every source concern in audit section 3 into a small deterministic fixture or an explicitly tracked unknown. Do not label a source concern a reproduced failure until it is exercised.
- Reuse the synthetic MOV fixture. Keep its unsigned/test status visible; do not treat it as genuine platform credentials.
- Add synthetic image fixtures with known camera fields, GPS, copyright, colour profile, orientation and mixed AI/non-AI XMP. Avoid storing personal metadata in repository fixtures.
- Record metadata before/after and the preservation facts relevant to each format. Generate fixtures reproducibly where possible, with a manifest of expected fields and media properties.
- Measure current import, selection changes, clean, verify and save latency. Profile main-thread stalls and memory allocation before claiming a cause for sluggishness.
- Confirm current semantics of All, AI, EXIF and GPS. Define camera/capture fields separately from location even when both share an EXIF carrier.

### Tests to add first

1. PNG compressed/uncompressed AI metadata and ComfyUI JSON without a literal brand name.
2. Mixed XMP containing AI information plus copyright/caption/location.
3. Actual scoped ImageIO copies for JPEG, PNG and supported HEIC/other formats.
4. Multi-frame/page fallback and orientations 1–8.
5. MOV credentials-only removal with a normal title mentioning an AI vendor.
6. Empty video selection and no-matching-metadata input.
7. Raw video dates, raw XMP and metadata outside the current prefix/suffix sample.
8. Saved file identity, source changes during work and cancellation.

### Gate

A fixture manifest explains what is known, what fails, what is unsupported and what has not been tested. Passing title/enum matcher tests alone is not accepted as evidence of real metadata removal.

## 5. Milestone 1 — make the current modes safe and honest

### Image work

- Extract a bounded PNG text decoder/classifier shared by the probe and cleaner. Support `tEXt`, `zTXt` and compressed/uncompressed `iTXt`, including graph keys and parameter records. Bound decompressed bytes, nested data and displayed values.
- Use the same semantic classification when detecting and planning removal. Do not remove unrelated text because it happens to contain a vendor name.
- Correct ImageIO copy/exclusion behaviour using actual API-supported options and round-trip tests. Preserve unselected metadata deliberately.
- Remove silent fallback to single-frame re-encoding. Inspect frame/page count before any path is selected; check metadata across the supported frames rather than only index zero.
- Preserve ICC and displayed orientation. Identify retained rendering fields in the result instead of calling them both preserved and removed.
- Treat a shared carrier as a scope boundary: if removing an AI field would destroy an unselected copyright field in the same packet, perform a supported field-level rewrite or report that precise removal is unsupported.

### Video work

- Add an empty-selection/no-match guard. No selection must not trigger a remux.
- Stop labelling every selected input finding “removed”. Use output evidence to distinguish removed, retained, still present and unverified.
- Separate credentials, explicit AI-generation claims and validation status in the evidence UI.
- Eliminate value-only overreach in credentials cleaning. A descriptive title mentioning OpenAI/C2PA must survive when only credential carriers are selected.
- Limit claims for exposed XMP/dates until raw parsing and targeted patches are implemented. Do not describe incidental exporter behaviour as deterministic scope coverage.
- Make current remux verification wording match actual checks; audio presence is not exact track identity.

### Gate

All new safety fixtures pass. Unsupported exact-scope operations are blocked or visibly partial. No output is reported fully clean solely because an exporter returned success. No unselected-field loss, silent re-encoding or frame loss is accepted.

## 6. Milestone 2 — inspection, planning and deliberate actions

Implementation status: complete in the current working tree, subject to the final
human interaction matrix in Milestone 7. `CleanContracts.swift` supplies the shared
identity/plan/check/receipt concepts while the image and video models retain separate
metadata taxonomies. Run identifiers and cancellation forwarding prevent stale image
or video work from republishing after Clear/cancel. Nineteen real SwiftUI snapshots
include the two ready-for-review states; visual inspection also verified that video
results are not labelled “No longer detected” before a receipt exists.

### Shared contracts

Add a small media-neutral contract layer, provisionally `CleanContracts.swift`. Reuse current models rather than creating a second image or video application model.

| Contract | Required content |
|---|---|
| Source identity | Stable file identity, size, modification information and a fingerprint appropriate to the verification path |
| Metadata entry | Stable carrier/tag/box identity; group; frame/track/path; bounded readable value; source of evidence; removable/rendering/unsupported role; reason |
| Inspection coverage | Formats/regions/fields checked, limits reached, malformed/opaque areas and interpretation warnings |
| Clean plan | Inspected source identity; selection revision; concrete actions; expected preserved data; unsupported requests; operation path and warnings |
| Verification check | What was tested, expected/actual result, strength of evidence, pass/fail/not-checked outcome |
| Receipt | Before/after summaries; removed/kept/remaining/unsupported/written entries; preservation checks; verified artifact identity; final save result |

Keep image selection and video selection types separate. Share lifecycle/report concepts, not incompatible metadata taxonomies. Stable entry IDs must include source location/ordinal where necessary; duplicate values are not duplicate fields.

Credential policy applies to every mutation, not only writing: deleting or rewriting metadata can affect a retained credential's asset binding. Preserving credential bytes does not prove the modified file still validates. Warn about the conflict and report binding validity as unverified unless it was actually checked.

### Queue lifecycle

`Queued → Inspecting → Ready for review → Cleaning → Verifying → Ready to save → Saving → Saved`

Failures, cancellation, unsupported requests and partial outcomes must be explicit. A no-change result is not a newly cleaned output. A changed source or changed selection invalidates its old plan/output.

- Import local files, folders or fetched URLs into inspection only.
- Cache inspections. Toggling a card updates a removal plan and counts; it does not reread and regenerate the entire queue.
- Keep one plan/selection revision per item. Ignore late results from cancelled or superseded work.
- Start with batch-wide quick choices and make per-file overrides explicit. A batch summary must reveal mixed selections.
- Allow re-inspection if the file changed externally. Revalidate identity before execution and detect changes during reads/verification; never apply offsets from a stale source.
- Store output artifacts in private temporary files rather than retaining an entire image batch as output `Data`.
- Preserve the selected route/input mode and valid queue state when switching tabs. Do not trigger clipboard reads, downloads or processing on navigation.

### UI actions

- Before clean: `Clean selected` and a review summary of intended changes.
- During work: visible phase/progress and `Cancel`.
- After verified success: `Save clean copy…` / `Save all ready…`.
- Partial/unsupported: show the exact limitation; never use the same success state as a verified clean.
- A result with remaining selected metadata cannot use the ordinary verified-save action. Any later “save partial copy anyway” feature must be a separate explicit action, not an automatic fallback.
- No selected scope or no matching data: explain why no operation is needed.
- Preserve a deliberate `Save unchanged copy…` action for inspected media with no requested changes, especially an already-clean URL download held in temporary storage. Verify copy identity, keep original protection, and label it unchanged—not newly cleaned. A no-op must not prevent a user from saving their download.
- Keep `Fetch image` / `Fetch video` as explicit intake actions; fetching does not silently invoke Clean in the new review workflow.

### Gate

Inspection does not create modified output. Card/tab clicks perform no expensive cleaning work. Batch and per-file state remain correct through cancellation, selection changes, route changes and source invalidation.

## 7. Milestone 3 — deterministic engines and verified preservation

### 7.1 Image engine

- Retain existing byte-preserving JPEG/PNG/WebP algorithms and their regression coverage. Refactor carefully rather than replacing working paths.
- Introduce set-based image selection behind the existing four quick presets. Add the useful AI + GPS combination first. Expose additional IPTC/XMP/comment/date/device/credential controls only after the corresponding exact-scope implementation passes fixtures.
- Separate identifying data from rendering essentials in the planner. Explain the meaning of All in the interface; a preserved orientation/profile cannot disappear from the receipt.
- Verify expected selected fields after output parsing and compare unselected fields where preservation is promised. A partial parser cannot certify complete absence.
- For byte-level paths compare encoded payloads and format structure. Also test displayed orientation, colour, frame/page count, animation timing and loop behaviour.
- Investigate a metadata-only HEIC/HEIF path with container-specific item/extent semantics. Reuse safe BMFF primitives where useful, but do not treat HEIC metadata item extents as ordinary movie metadata boxes.
- Define support independently for each operation and format: inspect, full clean, selective clean, write and preservation. Accepted filename extensions alone are not a support contract.
- For AVIF, GIF, TIFF, BMP or RAW-related inputs, either demonstrate the exact path or keep the unsupported operation inspectable with a clear message. Do not promise universal metadata cleaning merely because ImageIO opens the input.

### 7.2 Video structural reader

Build `ISOBaseMediaReader.swift` using bounded random-access reads:

- Parse 32-bit, extended 64-bit and zero-to-parent-end sizes with overflow and parent-bound checks.
- Skip `mdat` payload while inventorying structure. Do not decode arbitrary movie bytes as text.
- Recognise UUID types and versioned headers; apply explicit depth, node and value limits.
- Use schema-aware child offsets. `meta`, `stsd`, sample entries, `keys` and `ilst` have different header/count/layout rules; a generic recursive container list is insufficient.
- Distinguish ISO FullBox and supported QuickTime variants without reading arbitrary opaque payloads as child boxes.
- Produce stable box paths/IDs, offsets, sizes, warnings and coverage. Retain unsupported structures as opaque records.
- Count boxes, metadata blocks, selected logical changes, removable payload bytes and physical patch bytes separately. Derive counts from the parsed file; do not tune them merely to reproduce the website's numbers.
- Merge AVFoundation semantic information with structural evidence without confusing or double-counting their origins.

Typed readers must cover known credentials/JUMBF, descriptive keys, XMP carriers, location fields and `mvhd`/`tkhd`/`mdhd` creation/modification fields. Dates require version-0/version-1 widths, raw values and explicit zero/invalid handling; duration and timescale are not date fields.

A generic UUID or JUMBF carrier is not automatically C2PA. Recognise the actual credential identity and keep unrelated carriers intact. Encrypted, malformed, externally referenced or unusual fragmented/spatial layouts require their own supported contract; never silently remux them to get past a parser limitation.

### 7.3 Video removal planning and patching

- Use current `VideoCleanSelection` with its five groups, not the legacy four-preset video API in older plan snippets.
- Map supported selected entries to exact field or carrier edits. Never zero a complete mixed `meta`/`ilst` container merely because one child matches.
- Build a sorted, validated, non-overlapping patch plan. Detect conflicting/overlapping parent-child operations and reject ambiguous plans.
- Protect media bytes, structural indexes, codec configuration and all unselected fields.
- Copy/clone to a private temporary file. Use APFS copy-on-write where available; otherwise use cancellable chunked copying. Preflight disk space and identity.
- Replace safe removable carriers with same-sized free space and erase their old payload. Zero only defined timestamp fields inside required headers.
- Patch in bounded chunks using file handles; remove whole-movie `Data`/`[UInt8]` allocations from the production path.
- Close/synchronise before verification. Delete only task-owned incomplete output on failure/cancellation.
- Default to unsupported if exact safe edits cannot be expressed. A user-selected remux fallback gets its own plan, preservation checks and limited-result label. It must not be offered as verified byte preservation.

### 7.4 Verification and final saving

For patched video, require selected fields absent, planned replacements exact, file length/ranges unchanged and bytes outside allowed patch ranges identical. Stream media-range hashes/comparisons; reuse passes where possible instead of repeatedly scanning a movie.

Check exact track identities/counts, media types, codec descriptions, timing, dimensions, transforms and relevant colour/HDR properties. Clarify what is structural comparison, decode/playback compatibility or actual playback testing. Never claim a full playback test merely because an asset opens.

For remuxed video, byte offsets/file length may differ. Do not reuse patch-path guarantees; compare supported encoded samples if implemented, otherwise report identity as unproven. Never silently re-encode.

For both media types, bind verification to an immutable temporary artifact. Save atomically with original/collision protection. Re-read/hash the final saved file to establish it matches the verified artifact; if identity differs, verification must fail or be rerun. The heading “saved copy verified” is allowed only after this gate.

### Gate

The removal plan explains every changed region/field. Unselected metadata and protected media are demonstrably preserved for the chosen path. Raw timestamp/XMP checks use real fixtures, not fabricated matcher inputs. Final-file verification is distinct from temporary-output verification.

## 8. Milestone 4 — inspector, receipts and responsiveness

### Inspector layout and copy

- Preserve the existing two-level tool sidebar and top media switch. Do not add duplicate inspection routes.
- Keep quick removal cards compact but readable. Icons and title/description stacks align to the top; allow extra text rows rather than shrinking fonts or truncating useful descriptions.
- Present: file/preview → inspection summary → planned changes or result → grouped metadata → advanced technical evidence.
- Images: searchable camera/exposure/date/location/authorship/rights/AI groups; complete bounded values available on demand; optional map opening, never automatic map requests.
- Videos: supported metadata blocks with path/offset/size, readable evidence, exact change counts and a collapsible raw tree. Do not make raw boxes the default reading experience.
- Show Before / Planned / After without implying that the unchanged original has been modified.
- State removed, kept, still present, unsupported, unverified and intentionally written data separately. Use text/icons as well as colour.
- Add original/output sizes and precise preservation wording. Keep technical verification detail expandable.
- Add a playable before/after video view only after the cleaning contract is stable; media playback must not start by itself.
- Offer local report export/copy. Default to a privacy-safe summary; including original GPS, names or prompts must be deliberate. Do not automatically retain report history.

### Performance and cancellation

- Instrument inspect, plan, copy, patch, verify and save. Keep synchronous I/O, decompression, parsing and hashing off the main actor.
- Bound concurrent inspection; start with at most two lightweight inspections and one large clean/verify job, then adjust from measurements.
- Stream large outputs and hashes. Throttle progress updates so per-chunk work does not force constant full-window redraws.
- Cancel the underlying exporter when applicable, not only the surrounding Swift task. Check cancellation between bounded parser/read/write/hash work units.
- Prevent cancelled jobs from republishing stale output. Clean up only their private temporary artifacts, never originals or another job's output.
- Check declared URL size when available and always enforce a received-byte budget, including after redirects and when the header is absent or incorrect. Keep direct media validation; do not turn the URL field into a general webpage/video-platform downloader.
- Check disk space and report insufficient capacity before a large copy where possible. Do not equate an arbitrary file-size cutoff with a memory-safety implementation.

Proposed performance targets, to measure on recorded hardware rather than claim as achieved: cached selection/tab feedback under 100 ms; no main-thread stall over 50 ms during core interactions; cancellation UI acknowledgement within 250 ms under normal local-disk conditions. Parser memory must scale with bounded metadata inventory, and copying/verification buffers must not scale with movie size. Record actual values and explain misses before choosing final supported limits.

### Gate

Exercise empty, inspecting, ready, no-match, cleaning, verifying, partial, failed, cancelled, saved and externally changed-source states at normal and compact window sizes. Test blank-area clicks, keyboard navigation, focus, wrapped labels, long filenames and large evidence values. A screenshot/render check is not a substitute for interaction QA.

## 9. Milestone 5 — advanced output productivity

### Naming

- Add output naming settings with a live multi-file preview, optional prefix/suffix/sequence and the chosen token set.
- Validate names for macOS, preserve genuine extensions, prevent path traversal and apply deterministic collision handling without overwriting an existing file.
- Keep the current default save-folder setting and ordinary Save As. Filename templates must work for both Clean media types without changing their encoding.
- Define batch-token/date/index behaviour precisely so changing selection does not randomly rename already prepared outputs.

### Local profiles

- Save named cleaning/naming/preservation configurations locally with a versioned schema.
- Keep location/author/copyright values out unless the user elects to remember them. Do not save media, filenames or processing history into a profile.
- Support duplicate/rename/delete and a clear reset-to-default action. Make profile changes explicit for queued items rather than silently regenerating output.
- Preserve the current security-scoped save-folder access mechanism; profile portability must not bypass folder permissions.

### Optional ZIP

Offer a local archive of ready verified outputs if useful after native batch saving is dependable. Include only selected outputs; an audit report is opt-in. Handle cancellation, duplicate filenames and available disk space. This is a convenience feature, not core cleaning correctness.

### Gate

Previewed names match saved names, collisions are safe, settings survive relaunch correctly, and resetting a profile cannot erase media or private user directories.

## 10. Milestone 6 — optional image metadata writing

Implement only after the inspection/receipt model is reliable. Keep advanced writing disabled by default and visibly separate from removal.

- Add author/title/caption/copyright/keywords, accessibility text, credit/source and rights fields with explicit per-field write intentions.
- Add date/time controls distinguishing capture, digitised and modified embedded fields from filesystem creation/modification time. Preserve user-entered timezone meaning; do not silently reinterpret local time.
- Add manual coordinates first. Optional map/place lookup and current-location access need deliberate user actions and clear network/permission disclosures.
- Support JPEG/PNG/WebP writes only when the chosen field/carrier implementation passes tests. Do not advertise HEIC writing merely because HEIC cleaning works.
- Preserve unselected XMP namespaces and duplicate-language structures where supported. Escape text correctly, bound XML/JSON parsing and disallow external-entity expansion.
- Reinspect each output and report every field as written, not written, unsupported or conflicting. Adding licence metadata records terms; it does not enforce rights.
- Never add an app attribution automatically. Never claim that embedded accessibility text sets a webpage's HTML alt attribute or improves rankings by itself.
- If writing would invalidate a retained credential binding, disclose the conflict rather than implying that the old credential remains valid.

### Gate

Real format fixtures prove each field round-trips without changing protected image data. Unsupported fields are visible. Clean-only runs write nothing new. Private values are not persisted or included in report exports without the corresponding user choice.

## 11. Proposed source and test map

Names below are implementation proposals, not files claimed to exist already. Prefer focused extraction and reuse over creating overlapping frameworks.

| Area | Existing files to adapt | Proposed additions |
|---|---|---|
| Shared lifecycle/evidence | `MediaContracts.swift`, existing queue models | `CleanContracts.swift`, shared receipt/status views |
| Image safety/engine | `MetadataStripper.swift`, `ScopedMetadataStripper.swift`, `ImageIOStripper.swift`, `ProvenanceProbe.swift` | Bounded shared PNG text/classification helper; image inspection/plan/verifier types as needed |
| Image workflow/UI | `ScrubModel.swift` including `ScrubItem`, `CleanPresetPicker.swift`, `InspectorPanel.swift`, `ContentView.swift` | Extracted grouped metadata/selection views if useful |
| Video inventory | `VideoMetadataProbe.swift`, `MediaCapabilityProbe.swift` | `ISOBaseMediaReader.swift`, `VideoInspectionReport.swift` |
| Video cleaning | `VideoCleanScope.swift`, `VideoCleanPipeline.swift`, `MediaContainerSanitizer.swift` | `VideoRemovalPlanner.swift`, `VideoTemporaryClone.swift`, `VideoFilePatcher.swift`, `VideoCleanVerifier.swift` |
| Video workflow/UI | `VideoCleanModel.swift`, `VideoQueueItem.swift`, `VideoCleanView.swift`, `VideoCleanScopePicker.swift` | Extracted inspector and structured result views |
| Save/naming/settings | `MediaSaveService.swift`, `AppSettings.swift`, `PasteURL.swift` where relevant | Verified-artifact identity; naming/profile/optional archive services |
| Optional writing | Image inspection/selection/save contracts | `ImageMetadataWriter.swift` and dedicated write/readback tests |
| Gates | Existing `Tests`, `Tests/UISnapshotRenderer.swift`, `Tests/verify_algorithm.py`, `tools/check.sh` | Real scoped-image, BMFF reader/planner/patcher/verifier, queue cancellation and final-save tests |

The old plan's broad recursive-box examples need schema-specific handling. Its four-preset video planner examples must be updated for the current five-group selection. Its performance numbers are targets, not achieved measurements. The audit's live fixture observations supersede its “screenshot only” verification status for that particular website UI exercise.

## 12. Acceptance and handoff checklist

### Automated

- Run `tools/check.sh` after parser, cleaner, verifier or pipeline changes and wire every new test into the gate.
- Keep Python/Swift byte-algorithm expectations aligned where both exist.
- Add malformed-size/overflow/depth/decompression-limit tests and ensure bounded failure.
- Test every supported scope independently and in combinations, with unselected data present.
- Test source changes, duplicate imports, cancellation, stale-result suppression and final-save mismatch.
- Test rendering/media identity, not merely file existence, UI labels or nominal dimensions.

### Manual and visual

- Check representative real-world files alongside synthetic fixtures; do not upload personal media for QA.
- Confirm top alignment, common font/button sizing, full clickable areas, wrapping and readable report hierarchy.
- Test direct-URL fetch, local file/folder intake, default-directory recovery, Save As and batch save.
- Profile large files and rapid tab/selection changes. Verify no accidental clipboard read, repeated cleaning or blocked UI.
- Check keyboard-only use, visible focus, accessibility labels and status messages that do not rely only on colour.

### Evidence to deliver per milestone

Changed files, tests run/results, current limitations, representative screenshots where UI changed, measured performance where relevant, and remaining human acceptance checks. Do not mark a milestone complete just because the code compiles.

### Release boundary

Update development handoff/feature support tables after the relevant milestone is implemented and verified. Package/install a new app or DMG only when requested. At release, separately verify universal architectures, bundle identity/version, entitlements, actual signing/notarisation status, package checksum and a launch/interaction smoke test. Do not call an ad-hoc-signed package notarised.

## 13. The first implementation task

Start with milestones 0–1 as a bounded delivery: build failing safety fixtures, unify image AI decoding/removal, guard unsupported re-encode/multiframe paths, prevent empty-scope video work, correct video selection isolation, and make result/AI labels truthful. Then run the existing and new gates and present the result before starting the broader inspect-first/UI engine refactor.

This first task improves the reliability of features already visible to the user. The later milestones then add the missing capabilities on top of a tested contract.
