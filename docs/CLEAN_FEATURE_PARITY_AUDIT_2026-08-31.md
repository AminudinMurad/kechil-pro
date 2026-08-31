# Image and video Clean: website parity and correctness audit

Reviewed: 31 August 2026. Reference: AI Remover Pro. App: Kechil PRO working tree at the time of the audit, including existing uncommitted changes.

Implementation note: the audit below records the pre-fix research baseline. Milestones
0–1 were subsequently implemented in the same working tree; see
[`CLEAN_IMAGE_VIDEO_IMPLEMENTATION_PLAN.md`](</Users/aminudin/Documents/Business/Products/Kechil PRO/docs/CLEAN_IMAGE_VIDEO_IMPLEMENTATION_PLAN.md>)
and the current regression gate for the verified follow-up. No release package was
created as part of that follow-up.

## Conclusion

Kechil has adopted the main intake controls and removal choices, but has not yet matched the reference's depth of inspection, explicit removal planning, or evidence-rich results. The largest newly identified omissions are on the image side: a real metadata viewer, advanced output naming, optional metadata/date/location writing, and reusable configurations. The more urgent work is correctness: some currently visible cleaning controls are backed by narrower implementations than their labels suggest.

This section is a research snapshot, not release evidence. At the time of this audit
no app source was changed and no app build or DMG was produced; later implementation
work is recorded separately in the implementation plan linked above.

## Evidence and limits

- **Live UI exercised:** image Clean, image metadata viewer, and video Clean, using synthetic files only. Advanced image panels were opened and inspected. No account was created, no personal media was used, and no location search was submitted.
- **Published capability:** specialist image pages and the video checker describe additional formats and cases. Those claims are not equivalent to testing all those cases.
- **Source-confirmed:** the current Swift implementation and relevant tests were inspected. Source-path risks below are explicitly distinguished from runtime reproductions.
- **Not performed:** independent analysis of browser-generated output bytes, website network tracing, HEIC/animation/large-file round trips, account-backed profile operations, or a fresh app runtime benchmark/test run.

### What the live checks established

| Exercise | Observed result | Interpretation |
|---|---|---|
| Synthetic 64 × 64 JPEG with camera, date, GPS, IPTC and XMP data, opened in the [image viewer](https://airemover.pro/exif-viewer) | Grouped file/structure/camera/rights tables, GPS and an optional map link, plus an expandable 27-field decoded view. | A genuine read-only inspection UI exists. Kechil currently exposes only selected findings. |
| Same JPEG in [image Clean](https://airemover.pro/) | Processing began on import. The result separated detected/removed/written data and displayed input/output sizes. | Do not claim that the website's main image cleaner itself waits for an explicit Clean action. Its separate viewer provides inspection without cleaning. |
| Existing synthetic MOV fixture in [video Clean](https://airemover.pro/video-metadata-remover) | Before mutation: 30 boxes, 5 metadata blocks, 5 planned changes, 748 B; three date fields, one descriptive block and a UUID credential block. An explicit Remove action preceded the site's verified-result message and automatic download. | This reproduces the fixture observations in the earlier plan. The site's receipt was observed; its byte-preservation claims were not independently re-hashed here. |
| Advanced image panels | Naming preview, metadata and date forms, separate GPS-removal option, privacy settings, and sign-in-gated profile/location selectors. | Controls are reachable, but custom writes and signed-in profile persistence were not round-trip tested. |

The video fixture contains an explicitly synthetic, unsigned declaration naming OpenAI Sora. Its source label is not proof of authentic OpenAI credentials. Expanded evidence confirmed the Sora string was actually present; it was not inferred solely from the filename.

The image run also reported adding the site's processing attribution. That option was checked in the current browser state. This does **not** establish the default for a fresh browser. Kechil should not add its own branding to cleaned metadata unless deliberately requested.

## 1. Image features that are missing or only partially matched

Priority: **P0** correctness/safety; **P1** essential cleaning workflow; **P2** optional advanced capability. An entry marked “extension” is our recommendation, not a claim that the site has that exact feature.

| ID | Gap | Current Kechil behaviour and recommended change | Priority |
|---|---|---|---|
| I1 | Read-only, full metadata inspection | Import immediately probes and cleans; the inspector has selected findings, not the camera/exposure/date/IPTC/XMP tables seen in the website viewer. Add a read-only review stage inside Clean, with expandable groups and raw values. A searchable table would be a useful native extension. | P1 |
| I2 | Complete per-file change receipt | Existing before/removed/output sections are a foundation. Add explicit retained, remaining, unsupported and newly written states, with field-level differences where supported. Never equate a missing probe finding with exhaustive absence. | P1 |
| I3 | Combine AI removal and location removal | Image presets are exclusive. The site exposes a separate GPS-removal setting beside its cleaning mode; that combination was not output-tested here. Add a supported AI + GPS configuration. Arbitrary IPTC/XMP/date toggles would be a further app extension, not verified site parity. | P1 |
| I4 | Generation-workflow review and reliable scoped deletion | The [Stable Diffusion/ComfyUI page](https://airemover.pro/remove-stable-diffusion-metadata) describes prompts, negative prompts, seed, sampler, steps, CFG, model/VAE and workflow graphs. Kechil already recognises substantial provenance, but should present generation parameters coherently and ensure its cleaner uses the same decoded evidence as its probe. Compressed PNG deletion is a concrete source concern below; the site's compressed coverage was not proven. | P0/P1 |
| I5 | HEIC preservation contract | The [HEIC page](https://airemover.pro/remove-heic-metadata) claims same-length, in-place metadata changes without re-encoding. Kechil accepts HEIC but may fall back from ImageIO copying to re-encoding. Provide a tested metadata-only path or an explicit “re-encoding required” choice; allow users to refuse it. HEIC editing is not a verified website capability. | P0/P1 |
| I6 | Filename templates and inline batch naming | Kechil has Save As and collision-safe `-clean` names, but no template/preview system. Add templates, sequence start, separator and filename sanitisation, with a preview before saving. The site's exposed tokens are `{name}`, `{rand}`, `{index}`, `{domain}`, `{date}` and `{keyword}`. Preserve actual extensions. | P2 |
| I7 | Optional descriptive/rights metadata writing | Kechil removes metadata but does not provide editing fields. Add an optional advanced section for title, caption, creator, copyright, keywords, accessibility text, usage terms, licence URL, credit and source. Read back each requested field. These controls belong to image editing, not automatically to video Clean. | P2 |
| I8 | Capture-date/time controls | The site exposes capture/digitised/modified times, timezone/offset and a download-time option. Kechil has no such editor. If added, distinguish embedded dates from filesystem dates and show the exact fields that will change. Leave disabled for ordinary cleaning. | P2 |
| I9 | Location review and optional replacement | The [geotagging tool](https://airemover.pro/geotag-photos) describes batch coordinates, place lookup and credit fields. Kechil can detect/remove GPS but cannot edit location or offer a map review. Keep manual entry local; map/search/current-location actions must be explicit because external lookups or permissions are involved. | P2 |
| I10 | Reusable configurations | The site exposes account-backed profiles and saved locations. Kechil settings currently persist the save folder, not reusable cleaning/output configurations. Prefer **local** named presets; no account or cloud service is needed to meet the native use case. Remember coordinates and author values only by opt-in. | P2 |
| I11 | Archive export | The [EXIF page](https://airemover.pro/remove-exif) advertises individual downloads and batch ZIP. Kechil already saves batches to a folder. ZIP export is a convenience gap, not a reason to replace the existing native folder workflow. | P2 |
| I12 | Explicit orientation, colour and multi-frame policies | “Encoded pixels unchanged” is not sufficient to guarantee the same display. The EXIF page acknowledges orientation effects. The [WebP page](https://airemover.pro/remove-metadata-from-webp) describes ICC removal and conditional animation support. Kechil should expose preservation/limitation decisions and test them. Keep colour profiles by default rather than copying the site's broad profile removal. | P0/P1 |

The editing capabilities in I7–I9 are adjacent to cleaning. They should remain optional, collapsed advanced controls, so “remove my metadata” does not silently become “replace it with other metadata”. The geotagging page explicitly limits writing to JPEG/PNG/WebP despite inconsistent HEIC wording elsewhere in its steps.

### Image source evidence

- Presets and one active selection: [MediaContracts.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/MediaContracts.swift:20>) and [CleanPresetPicker.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/CleanPresetPicker.swift:25>).
- Immediate processing, original/output probes and automatic reprocessing: [ScrubModel.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/ScrubModel.swift:139>) and its [processing path](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/ScrubModel.swift:213>).
- Current report presentation: [InspectorPanel.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/InspectorPanel.swift:118>); only selected ImageIO fields are surfaced by [ProvenanceProbe.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/ProvenanceProbe.swift:314>).
- Byte-preserving JPEG/PNG/WebP policies: [MetadataStripper.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/MetadataStripper.swift:38>); fallback behaviour: [ImageIOStripper.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/ImageIOStripper.swift:58>).
- Current filename/save behaviour: [ScrubModel.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/ScrubModel.swift:264>); persistent settings: [AppSettings.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/AppSettings.swift:4>).

## 2. Video features that are missing or only partially matched

The five selection cards already exist. The gap is their implementation and evidence, not another set of cards. The [video checker](https://airemover.pro/video-metadata-checker) describes bounded structural inspection, readable evidence and byte locations; it does not claim certificate-chain validation.

| ID | Gap | Current Kechil behaviour and recommended change | Priority |
|---|---|---|---|
| V1 | Inspect → review → Clean | Intake and group changes immediately re-export the queue. Cache a read-only inspection first; changing a selection should update the removal plan, not start an export. Add explicit Clean Selected/Save actions. This could reduce unnecessary work, but is not a measured explanation of all reported lag. | P1 |
| V2 | Real container inventory | No report of box paths, byte offsets/sizes or media ranges. The probe samples text from the beginning/end of the file. Add a bounded structural ISO-BMFF parser and disclose unsupported/malformed regions. | P0/P1 |
| V3 | Raw movie/track/media timestamps | “Container dates” matches exposed string metadata; no explicit reader/zeroing path for numeric `mvhd`, `tkhd`, `mdhd` fields exists. Implement version-aware field edits. Do not remove the required header boxes. AVFoundation may alter some timestamps incidentally; that is not targeted coverage. | P0 |
| V4 | Raw XMP removal | Current support depends on what AVFoundation exposes. Add recognised XMP box/UUID identification and targeted removal, with before/after evidence. Do not promise every private carrier is understood. | P0 |
| V5 | Preservation verified from the original | The cleaner first remuxes through AVFoundation. Equal-size edits in the later C2PA sanitizer prove nothing about source-to-final offsets. Prefer clone-and-patch when safe, and label any remux fallback. Compare file/range structure. Media-byte hashes would strengthen verification beyond the site's observed receipt. | P0 |
| V6 | Accurate removed/retained/remaining statuses | The current UI labels selected input findings as removed even when some remain. Generate statuses from comparison, not selection. Show retained unselected fields and verified limitations. | P0/P1 |
| V7 | Provenance versus AI versus validated credentials | Current evidence UI treats generic C2PA/provenance text as AI. Separate “credentials found”, “explicit AI-generation claim”, “synthetic/unsigned declaration” where known, and “signature/trust not validated”. Show supporting fields without converting a claim into proof. | P0 |
| V8 | Resource preflight and reliable cancellation | All/credentials processing loads and copies the full exported movie in memory. Add streamed patching, disk-space checks, cancellation points and visible stages. The site publishes a size cap; the native app should use its own tested resource budget, not blindly inherit a browser limit. | P1 |
| V9 | Useful verification/result facts | Expose original/output size, selected change count, removable payload bytes, unchanged media evidence and limited coverage. Existing descriptor checks cover dimensions, audio presence and duration—not all tracks, codecs, HDR, captions or exact samples. | P1 |
| V10 | Saved-copy receipt | Verification currently covers the temporary output; save checks readability after copying. Verify the final file's identity or re-probe it before saying the saved copy was verified. A local JSON/TXT receipt and playable before/after preview are useful native extensions, not demonstrated site features. | P1/P2 |

### Video source evidence

- Automatic queue processing and selection changes: [VideoCleanModel.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/VideoCleanModel.swift:42>).
- Scope labels explicitly describe exposed XMP/date metadata: [VideoCleanScope.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/VideoCleanScope.swift:50>); matching remains string-based at [line 108](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/VideoCleanScope.swift:108>).
- Limited byte sample: [VideoMetadataProbe.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/VideoMetadataProbe.swift:272>).
- Export, sanitizer, remaining-finding comparison and descriptor checks: [VideoCleanPipeline.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/VideoCleanPipeline.swift:52>) and [verification](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/VideoCleanPipeline.swift:157>).
- Status and AI-evidence presentation: [VideoCleanView.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/VideoCleanView.swift:159>).
- In-memory structural sanitizer: [MediaContainerSanitizer.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/MediaContainerSanitizer.swift:34>).
- Final file copy/readability check: [MediaSaveService.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/MediaSaveService.swift:49>).

## 3. Correctness issues to investigate before adding more controls

These are source-established implementation risks, not newly reproduced app failures. They are distinct from claims about what the website handles successfully.

1. **AI PNG detection/removal disagreement.** The probe inflates compressed PNG text and recognises ComfyUI graph structure; scoped removal searches raw chunk bytes for a narrower fixed vocabulary. A recognised prompt can therefore survive AI-only removal. Use one bounded decoder/classifier for both planning and deletion. Evidence: [stripper](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/ScopedMetadataStripper.swift:149>), [decoder](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/ProvenanceProbe.swift:222>), [graph recognition](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/ProvenanceProbe.swift:463>).
2. **Image fallback can flatten multi-frame files.** The fallback reads index zero and creates a destination with one image. Preserve all frames/pages or block that path for multi-frame inputs. Evidence: [ImageIOStripper.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/ImageIOStripper.swift:110>).
3. **Scoped ImageIO EXIF/AI deletion needs real format tests.** Those paths use property-dictionary deletion options unlike the corrected GPS copy/exclusion path. Ordinary camera metadata in non-core formats also has limited probe coverage. Do not assume a no-match means nothing was present. Evidence: [ScopedMetadataStripper.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/ScopedMetadataStripper.swift:224>).
4. **JPEG orientation needs an explicit contract.** Broad removal deletes EXIF while retaining encoded samples. A rotated source may display differently. Test orientation values 1–8 and choose either minimal orientation retention or an explicitly disclosed pixel transform; do not promise both total EXIF absence and byte-identical encoded data without resolving this tradeoff.
5. **Video selection isolation is not assured.** Credentials-only filtering tries to retain ordinary titles, but the later sanitizer zeroes any `ilst` item containing a broad AI keyword. A title such as “OpenAI interview” can be affected despite descriptive removal being off. Evidence: [scope guard](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/VideoCleanScope.swift:120>) and [sanitizer](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/MediaContainerSanitizer.swift:83>).
6. **Clearing video selections still schedules an export.** Add a no-op guard and disable the Clean action when nothing is selected. Changing a choice should not rewrite the queue. Evidence: [VideoCleanModel.swift](</Users/aminudin/Documents/Business/Products/Kechil PRO/Sources/VideoCleanModel.swift:42>).
7. **Video scan and verification blind spots.** The current 4 MiB prefix/1 MiB suffix policy leaves the end of 4–5 MiB files unscanned and misses the middle of larger files. Text matching may also confuse payload text with metadata. All-groups remaining checks do not establish removal of every device/software/timed field. Use structural coverage and distinguish “unsupported” from “absent”.
8. **Preservation assertions exceed current checks.** Audio presence is not exact track preservation; duration and dimensions are not sample identity. Validate multi-audio, timed metadata, captions, transforms and HDR separately. The legacy async exporter also needs a tested immediate-cancel path; the synchronous sanitizer has no cancellation points.

## 4. What should not be counted as missing

Kechil already provides local file/folder and direct-URL intake, explicit clipboard paste, local processing, image/video saving, default save-directory settings, batch queues, original protection, four image presets, five video groups, useful provenance detection, output probing and partial-result warnings. The recent layout work should not be undone or re-listed as a feature gap.

The image byte-level implementation already addresses progressive-JPEG/trailing-payload and unknown PNG/WebP carrier cases in its broad clean path. That is not proof that every scoped path handles every case, but it would be inaccurate to say the broad algorithms are entirely missing.

Do not copy these behaviours automatically:

- **Unrequested branding or new metadata.** Keep clean outputs unbranded by default; no new “Offline” badge is needed.
- **Mandatory accounts/cloud profiles.** Local reusable settings satisfy the desktop requirement.
- **Removal of colour information merely because the site does it.** Kechil intentionally preserves rendering data in its byte-level paths. Make the privacy tradeoff explicit.
- **Claims of authentic AI detection, C2PA signature validation, SynthID removal or guaranteed platform-label removal.** The [credentials checker](https://airemover.pro/content-credentials-checker) is useful for readable claims, not a basis for inventing trust guarantees.
- **A separate sidebar item for every web landing page.** Keep inspection, selection, verification and saving within Clean → Images/Videos.
- **Adjacent visible-watermark repair, AI detection and watermark embedding.** These are not metadata cleaning parity and need a separate product decision.

## 5. Recommended implementation order and acceptance gates

### A. Fix truthfulness and safety first

Address image decoder/remover disagreement, multi-frame fallback, orientation policy, selection isolation, empty video selection and incorrect result/source labels. Add real fixtures before changing the engine. Prefer “unsupported” or “partial” to a misleading green result.

**Gate:** unselected metadata survives; supported selected metadata is absent; no-op inputs do not export; unsupported cases never claim complete cleaning; colour/orientation/frame policy is verified.

### B. Build the shared review workflow and structural video engine

Use `Inspect → Review selection → Clean → Verify → Save` for both media types. Expose a simple summary first and technical details on demand. Reuse the original inspection when toggling groups. Implement deterministic BMFF parsing, targeted timestamp/XMP/credential changes, and original-to-output preservation checks.

**Gate:** recognised raw fields carry path/offset/size evidence; selected changes are deterministic; retained metadata remains; the UI stays responsive while reviewing and cancelling; the final saved file corresponds to the verified output.

### C. Make reports genuinely useful

Add grouped image metadata, clear per-field/per-block before/after statuses, format/coverage notices and result sizes. Then consider local receipt export, copyable evidence and a playable video comparison. Report export and sample hashing are recommendations beyond the website behaviour verified in this audit.

**Gate:** a user can tell what was found, what was requested, what changed, what remained, what could not be checked and where the saved copy is—without reading raw parser output.

### D. Add advanced image productivity features

Start with naming previews and local profiles. Add explicit metadata/rights/date/location writing only after write/readback verification is reliable. Keep those options off for normal cleaning. ZIP export is lower priority than a dependable native batch-save flow.

**Gate:** valid extension/collision handling; requested fields round-trip; unsupported writes are reported per format; presets do not persist private values without consent; cleaning never adds attribution implicitly.

### Minimum regression matrix

| Image fixtures | Video fixtures | Workflow checks |
|---|---|---|
| JPEG orientations 1–8; progressive scans; ICC and embedded thumbnails | `mvhd`/`tkhd`/`mdhd` versions 0/1, zero/nonzero values | Inspecting creates no output; changing groups causes no export |
| PNG `tEXt`, `zTXt`, compressed/uncompressed `iTXt`; ComfyUI graph without a brand name | Standard/private XMP UUID/box placements; location copies | Empty scope, no matching data, partial clean, malformed/unsupported data |
| Animated PNG/WebP/GIF, multipage TIFF | C2PA-only, ordinary signed camera/editor claims, synthetic unsigned claims, descriptive AI-related words | Cancel during inspect, export, patch, verification and save |
| HEIC/HEIF and AVIF with EXIF/XMP/C2PA, mixed supported/opaque fields | Metadata at file start/middle/end; 4–5 MiB boundary; multiple `mdat` ranges | Save collisions, inaccessible default folder, final-file identity |
| Mixed clean/dirty files; mirrored GPS; EXIF/AI scope on ImageIO formats | Multiple audio tracks, captions/timed metadata, rotation, HDR; large/sparse files | Bounded memory, per-item progress, responsive navigation, truthful receipts |

The existing [next-agent plan](</Users/aminudin/Documents/Business/Products/Kechil PRO/docs/NEXT_AGENT_PRODUCT_IMPROVEMENT_PLAN.md:160>) already covers much of the structural video work. This audit extends that plan with image feature parity, optional editing/naming configurations, clearer preservation policies and source-level correctness checks. It does not claim those planned features are implemented.
