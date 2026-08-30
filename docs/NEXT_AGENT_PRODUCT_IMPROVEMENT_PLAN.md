# Kechil PRO next-agent product improvement plan

Updated: 2026-08-30  
Primary focus: Video Clean inspection depth, safe removal, verification, performance,
and UI/UX clarity  
Product identity: Kechil PRO 1.0.0 (build 1)

## 0. Read this first

This is an implementation handoff, not a release authorization. The next agent must:

1. Read `docs/DEVELOPMENT_HANDOFF.md`, this document, `README.md`, and the relevant
   source/test files listed below before editing.
2. Keep `CFBundleShortVersionString` at `1.0.0` and `CFBundleVersion` at `1` unless
   Aminudin explicitly requests a change.
3. Never overwrite an original image or video.
4. Keep all media processing local and sandboxed. Do not add network access,
   telemetry, remote processing, package-manager dependencies, or FFmpeg.
5. Do not claim C2PA cryptographic validation unless certificate chains, signatures,
   asset bindings, and revocation are actually validated.
6. Do not claim that metadata cleaning removes in-pixel signals such as SynthID.
7. Do not package, install, notarize, or rebuild the DMG unless Aminudin explicitly
   asks for a build.
8. Run `tools/check.sh` after every parser, cleaner, verifier, or media-pipeline change.
9. Treat a passing automated gate as necessary but not sufficient. Render and inspect
   the affected UI and manually test representative real files before release.

## 1. Why this work is necessary

Kechil PRO already has a working six-route architecture and functional local media
pipelines. Its current Video Clean implementation detects and removes supported
metadata, reopens the result, checks playback-facing facts, and avoids claiming
cryptographic frame identity. That foundation is useful.

The product is nevertheless behind the reference workflow in one important area:
**inspection depth and evidence presentation**.

Kechil currently summarizes a video with a poster, basic technical facts, a small list
of findings, and a broad clean result. It automatically begins cleaning after intake.
The reference workflow first builds a structured container report, shows exactly what
is present and removable, lets the user review the planned change, performs the
operation only after an explicit action, and then verifies the output.

The objective is not to clone another website. The objective is to give Kechil PRO a
stronger native-macOS version of the same useful product qualities:

- inspect before changing;
- show evidence, not vague claims;
- distinguish a box, a metadata field, a removable change, and a byte count;
- identify likely AI-source signals with confidence and evidence;
- preserve encoded media ranges when a byte-preserving clean is possible;
- prove what was preserved and what was removed;
- keep memory usage bounded for large movies;
- make the workflow understandable without exposing raw parser complexity by default.

## 2. Evidence status and comparison boundary

The plan deliberately separates three evidence levels.

### 2.1 Confirmed from the current Kechil source and tests

The following is confirmed in the repository as of this handoff:

- `VideoMetadataProbe` reads AVFoundation file/track metadata and performs a bounded
  first-4-MiB/last-1-MiB text scan for selected marker strings.
- `VideoCleanPipeline` uses `AVAssetExportPresetPassthrough`, sets metadata according
  to the selected Clean preset, reopens the output, and verifies dimensions, audio
  presence, and duration.
- Broad/AI video cleaning then loads the entire exported movie with
  `Data(contentsOf:)`, recursively identifies selected C2PA/JUMBF boxes, and writes a
  full replacement `Data` object back to disk.
- `MediaContainerSanitizer` preserves box length when neutralizing supported C2PA
  carriers, which protects following byte offsets for those recognized cases.
- The current app does not expose a complete ISO-BMFF tree, exact box offsets/sizes,
  movie/track/media-header timestamps, exact removable payload bytes, media-data range
  hashes, or an inspect-first action gate.
- The current green result means playback-facing facts and supported metadata were
  rechecked; encoded sample bytes are not cryptographically compared.
- The bundled fixture is:
  `Test Samples/Kechil-OpenAI-Generative-ID-5s.mov`
  with SHA-256
  `0d071f95e21ad4ea31aee8635b9b81ac257b38f7ff48e347b43edefa953a29d4`.

### 2.2 Confirmed from the reference site's published pages

The live reference pages state that their video checker/remover:

- organizes MP4/MOV/M4V data into AI provenance, descriptive metadata, dates,
  media-data ranges, and a bounded raw box tree;
- reports readable values plus byte offsets and sizes;
- supports selected C2PA/Content Credentials, XMP, title, author, comments, encoder,
  location, and non-empty movie/track timestamps;
- replaces supported metadata boxes with same-size free space;
- inspects the output again;
- requires selected metadata to be absent, the file size to be unchanged, and every
  media-data range to retain the same offset and length before presenting the clean
  download;
- does not claim to remove SynthID and does not claim full certificate-chain validation.

Reference pages reviewed:

- <https://airemover.pro/video-metadata-remover>
- <https://airemover.pro/video-metadata-checker>
- <https://airemover.pro/content-credentials-checker>
- <https://airemover.pro/remove-ai-metadata>

### 2.3 Screenshot-derived observations that must be independently reproduced

Aminudin's captured test of the same Kechil fixture shows the reference workflow
reporting:

- `30 boxes checked`;
- `5 metadata blocks present`;
- `5 removable changes`;
- `748 B removable payload`;
- an `OpenAI (Sora)` source signal with expandable evidence;
- three date-bearing boxes: `mvhd`, `tkhd`, and `mdhd`;
- a descriptive `meta` block;
- a C2PA `uuid` block;
- exact offsets and sizes;
- a collapsed raw box tree;
- a separate **Remove metadata** action after inspection.

These numbers are a regression target for the exact fixture, but they must never be
hard-coded. The parser must derive them from bytes, and tests must fail if the parser
cannot explain how each count and byte total was produced.

### 2.4 Incremental implementation now present in the checkout

The current checkout includes a deliberately bounded first slice of this plan:

- `VideoCleanScope` and `VideoCleanSelection` expose five independently toggleable
  groups in the video Clean route: Content Credentials, descriptive metadata, XMP,
  Location and Container dates. All five are selected by default, and the pipeline
  still has a compatibility overload for the original four `CleanPreset` values.
- `VideoMetadataFinding` carries a short `VideoMetadataEvidence` list. The probe keeps
  identifiers and only readable, marker-bearing payload excerpts (maximum 4 KiB read,
  360 displayed characters); signatures and arbitrary binary are not shown.
- The video inspector renders an AI/source-signal card with a red critical accent and
  an expanded-by-default Evidence disclosure when readable provenance evidence exists.
  The vendor name is shown only when the evidence text contains it; filenames are not
  used as a source claim.
- Empty image/video Clean drop zones have Upload file / Paste URL tabs. The inline
  form accepts local `file://` URLs or absolute paths and deliberately rejects remote
  HTTP(S) downloads while the app remains offline.

This slice does not yet deliver the full inspect-first state machine, exact ISO-BMFF
box offsets/sizes, raw box tree, media-range hashing, or a cryptographically validated
C2PA result. Those remain the next implementation phases below. The UI therefore uses
careful language such as “readable AI provenance” and “carrier detected”.

The in-app browser controller was unavailable while this handoff was written, so this
document does not falsely claim a fresh interactive upload/click test. Phase 0 below
requires the next agent to repeat and record that interaction before feature coding.

## 3. Gap matrix

| Area | Kechil today | Required target | Priority |
| --- | --- | --- | --- |
| Workflow | Intake automatically starts cleaning | Inspect → review plan → explicit Clean → verify → save | P0 |
| Container inspection | AVFoundation metadata plus bounded string scan | Deterministic ISO-BMFF box inventory with paths, offsets, sizes, flags, and bounded values | P0 |
| Counts | Broad `findings.count` | Boxes checked, metadata blocks, selected changes, selected payload bytes | P0 |
| Dates | Only exposed when AVFoundation returns metadata | Parse `mvhd`, `tkhd`, `mdhd` creation/modification fields directly | P0 |
| AI provenance | Marker-based category and short summary | Source-signal model with vendor/generator, confidence, protocol, and evidence links | P0 |
| C2PA | Locates selected carriers; no trust validation | Structured carrier/claim inventory; explicitly separate presence, claim reading, and trust validation | P0/P1 |
| Raw structure | Not shown | Collapsible bounded raw box tree | P1 |
| Cleaning | AVFoundation pass-through then whole-file `Data` sanitizer | Copy/clone then random-access same-size patching for supported files | P0 |
| Memory | Full exported movie can be loaded more than once | Peak incremental memory independent of movie size | P0 |
| Verification | Duration, dimensions, and audio presence | File size, exact patched ranges, media-data offsets/lengths/hashes, track facts, and post-clean report | P0 |
| Receipt | Short green status paragraph | Before/after verification receipt with explicit evidence and limitations | P0 |
| Large files | Sequential work, but full `Data` load | Bounded I/O, disk-space preflight, cancellation, and measurable progress | P0 |
| UI hierarchy | Flat findings list | Summary tiles, source-signal alert, categorized cards, advanced tree, sticky primary action | P0/P1 |
| Batch | Queue works | Independent inspect/clean state per item plus inspect-all/clean-selected flow | P1 |
| Accessibility | Symbols/text are generally present | Full keyboard order, VoiceOver summaries, no colour-only state, stable scrollbars | P1 |

## 4. Product decisions to lock before implementation

### 4.1 Keep the three-tool, six-route architecture

Do not add a fourth top-level “Inspector” tool. Inspection is a stage inside Clean:

```text
Clean · Images: inspect → review → clean → verify → save
Clean · Videos: inspect → review → clean → verify → save
```

This preserves the product's existing information architecture while improving depth.

### 4.2 Use progressive disclosure

The default Video Clean inspector should answer four questions immediately:

1. What was found?
2. What will Kechil remove for the selected preset?
3. Will picture/audio bytes change?
4. Is the eventual output verified?

Offsets, fourCCs, flags, box paths, and the raw tree belong behind disclosure controls.
They are important evidence but should not dominate the first screen.

### 4.3 Do not copy unsupported reference features

Do not add accounts, cloud profiles, saved locations, online limits, remote downloads,
or multilingual UI as part of this milestone. Kechil's advantage is native offline
batch processing. Adapt inspection clarity and verification—not unrelated website
features.

## 5. Phase 0 — mandatory competitor and baseline test record

Before changing production code, create:

`docs/qa/VIDEO_CLEAN_REFERENCE_BASELINE.md`

The record must contain:

1. Date, macOS version, browser version, Kechil version/build, and fixture SHA-256.
2. Exact reference URL and exact Kechil route tested.
3. Screenshots for empty, analysing, inspected, cleaning, verified, and saved states.
4. Every reference count/value produced for the fixture.
5. The downloaded reference output's filename, byte size, SHA-256, playable status,
   duration, dimensions, track count, and whether the synthetic ID remains.
6. Kechil's equivalent before/after results using the same source.
7. A table classifying each observation as:
   - directly observed;
   - derived by a local parser;
   - stated by the reference site's documentation;
   - not verified.
8. A network observation. Do not claim “no upload” merely from site copy; inspect the
   browser's network activity during the fixture run if the testing surface permits it.

Do not paste private real-world media into the record. Use the synthetic fixture and
generated non-sensitive fixtures.

Phase 0 acceptance:

- the record exists;
- the reference output and Kechil output are saved outside the source fixture path;
- their hashes and sizes are recorded;
- no result is described as verified without a named verification method.

## 6. Phase 1 — deterministic ISO-BMFF inspection engine

### 6.1 Replace marker scanning with a real box reader

Add `Sources/ISOBaseMediaReader.swift` with a random-access parser built on
`FileHandle`. It must never read an `mdat` payload merely to find the next box.

Suggested core types:

```swift
struct BMFFBoxID: Hashable, Sendable {
    let path: [String]
    let siblingIndex: Int
}

struct BMFFBoxRecord: Identifiable, Hashable, Sendable {
    let id: BMFFBoxID
    let type: String
    let userType: UUID?
    let offset: UInt64
    let size: UInt64
    let headerSize: UInt64
    let payloadOffset: UInt64
    let payloadSize: UInt64
    let depth: Int
    let version: UInt8?
    let flags: UInt32?
    let isContainer: Bool
    let isMediaPayload: Bool
    let parseStatus: BMFFParseStatus
}

struct BMFFInventory: Sendable {
    let fileSize: UInt64
    let boxes: [BMFFBoxRecord]
    let warnings: [BMFFParseWarning]
    let bytesRead: UInt64
    let maximumDepthReached: Int
}
```

Parser requirements:

- 32-bit sizes, 64-bit extended sizes, and zero-to-end sizes;
- overflow-safe offset arithmetic;
- exact parent-bound enforcement;
- UUID user types;
- FullBox version/flags;
- known child containers including `moov`, `trak`, `mdia`, `minf`, `stbl`, `edts`,
  `dinf`, `mvex`, `moof`, `traf`, `mfra`, `udta`, `meta`, `ilst`, `ipro`, `sinf`,
  `schi`, `wave`, and format-specific metadata containers;
- correct `meta` child offset for ISO FullBox and QuickTime variants;
- configurable maximum depth and node count;
- clear partial-report warnings for malformed boxes;
- no recursive interpretation of opaque media payload bytes;
- cancellation checks between nodes;
- deterministic ordering and stable IDs.

Never use `String(decoding: wholeMovieData, as: UTF8.self)` to classify a movie.

### 6.2 Parse the five fixture metadata changes

Add typed readers for:

- `mvhd`: movie creation and modification times;
- `tkhd`: track creation and modification times;
- `mdhd`: media creation and modification times;
- QuickTime/ISO metadata under `udta/meta/ilst/keys` including title, description,
  author, comment, copyright, location, software/encoder, and relevant custom keys;
- C2PA/JUMBF carriers including the standard C2PA UUID and recognized `c2pa`/`jumb`
  forms.

Required date behavior:

- support version 0 and version 1 field widths;
- interpret the 1904 QuickTime epoch without silently converting invalid values;
- show both raw seconds and formatted local/UTC value in advanced evidence;
- make “zero/non-zero/removable” explicit;
- do not treat duration/timescale fields as removable dates.

### 6.3 Create a unified inspection model

Add `Sources/VideoInspectionReport.swift`:

```swift
struct VideoInspectionReport: Sendable {
    let descriptor: MediaAssetDescriptor
    let inventory: BMFFInventory
    let metadataBlocks: [VideoMetadataBlock]
    let sourceSignals: [MediaSourceSignal]
    let mediaRanges: [MediaDataRange]
    let rawTree: [BMFFTreeNode]
    let coverage: InspectionCoverage

    var boxesChecked: Int { inventory.boxes.count }
    var metadataBlocksPresent: Int { metadataBlocks.filter(\.isPresent).count }
}

struct VideoMetadataBlock: Identifiable, Sendable {
    let id: BMFFBoxID
    let category: VideoMetadataCategory
    let title: String
    let summary: String
    let offset: UInt64
    let size: UInt64
    let removablePayloadBytes: UInt64
    let scope: VideoMetadataScope
    let evidence: [VideoEvidence]
    let supportedAction: MetadataAction?
}
```

The report must merge—but not confuse—three sources:

- deterministic byte-level box data;
- AVFoundation semantic metadata;
- capability/playback facts.

When two sources describe the same field, retain provenance and deduplicate the UI
record using a stable identifier. Do not deduplicate based only on display text.

### 6.4 Phase 1 tests

Add `Tests/ISOBaseMediaReaderChecks.swift` and fixtures covering:

- the exact 5-second OpenAI synthetic MOV;
- `moov` before and after `mdat`;
- multiple `mdat` boxes;
- extended-size boxes;
- zero-size boxes;
- nested and top-level C2PA UUID boxes;
- version 0 and version 1 header dates;
- QuickTime `meta` with and without FullBox prefix;
- fragmented MP4 (`moof`/`traf`);
- malformed child size, overflow attempt, excessive depth, and truncated headers;
- opaque bytes containing the string `c2pa` inside `mdat` that must not be reported;
- a clean control video with no removable metadata.

For the exact fixture, assert derived—not hard-coded UI—results matching the recorded
baseline: box count, metadata block count, action count, payload bytes, box types,
offsets, and sizes.

## 7. Phase 2 — source-signal and provenance evidence

### 7.1 Add a vendor-neutral source-signal model

```swift
struct MediaSourceSignal: Identifiable, Sendable {
    enum Confidence { case declared, stated, inferred }
    let id: UUID
    let vendor: String?
    let product: String?
    let generator: String?
    let protocolName: String
    let confidence: Confidence
    let claim: String
    let evidence: [VideoEvidence]
    let limitations: [String]
}
```

For the fixture, `OpenAI (Sora)` must be derived from readable evidence and shown as
declared or stated according to its actual carrier. Do not infer “Sora” solely because
the filename or test ID contains `OpenAI`.

Evidence rows should include the originating box path, offset, size, field identifier,
and a safely bounded value excerpt. Binary blobs should be summarized, not dumped.

### 7.2 Separate four different claims

The UI and model must not conflate:

1. a C2PA carrier is present;
2. a readable manifest claims a generator/source type;
3. a signature is structurally present;
4. a signature/trust chain was cryptographically validated.

Kechil currently supports evidence levels 1 and selected parts of 2. Levels 3 and 4
must remain “not validated” until implemented and tested.

### 7.3 C2PA expansion boundary

P0: locate carrier, parse bounded readable claims, show protocol and limitations.  
P1: parse JUMBF structure and supported assertions/actions.  
Future-only: full trust-chain, certificate, revocation, and asset-binding validation.

Do not block the core cleaner on future trust validation.

## 8. Phase 3 — removal planning and bounded-memory patching

### 8.1 Replace automatic cleaning with an explicit plan

Add:

```swift
struct VideoRemovalPlan: Sendable {
    let sourceReportID: UUID
    let preset: CleanPreset
    let actions: [VideoRemovalAction]
    let selectedPayloadBytes: UInt64
    let requiresRemux: Bool
    let changesEncodedMedia: Bool
    let unsupportedFindings: [VideoMetadataBlock]
}

enum VideoRemovalAction: Sendable {
    case replaceBoxWithFree(box: BMFFBoxRecord)
    case zeroPayload(range: Range<UInt64>, reason: String)
    case zeroHeaderDate(box: BMFFBoxRecord, fields: [DateField])
    case preserve(block: VideoMetadataBlock, reason: String)
}
```

The preset selects actions; it does not immediately mutate the file. A user may expand
Advanced Selection and deselect an individual supported block. The default remains the
four simple presets already used by Kechil.

### 8.2 Add a safe temporary clone/copy service

Add `Sources/VideoTemporaryClone.swift`:

1. Preflight source size and available destination space.
2. Create the existing private temporary directory with mode `0700`.
3. Attempt an APFS clone/copy-on-write copy where supported.
4. Fall back to a chunked copy with cancellation and progress.
5. Verify destination size before patching.
6. Never patch the original URL.
7. Clean up on cancellation/failure; retain a verified result until saved or removed.

### 8.3 Add random-access patching

Replace the whole-file `Data(contentsOf:)` path with `FileHandle` range writes:

- validate the source report still matches the input file size and modification state;
- sort and validate non-overlapping patch ranges;
- reject any patch touching `mdat` or a protected structural field;
- replace removable leaf box types with `free` while preserving size;
- zero only defined timestamp fields inside required header boxes;
- synchronize and close the file before verification;
- record every range, original hash, replacement hash, byte count, and reason in an
  in-memory receipt;
- never log private field values.

The patcher must operate with memory proportional to the largest small metadata range,
not proportional to the movie size.

### 8.4 Keep AVFoundation as an explicit fallback

Use the byte-preserving patch path for recognized, safe ISO-BMFF layouts. Retain the
existing pass-through exporter only for cases where a supported metadata change cannot
be expressed as a safe same-size patch.

Fallback labels must be exact:

- `Encoded media preserved — container bytes patched`;
- `Container remuxed — encoded-frame identity not proven`;
- `Video re-encoded — picture bytes changed`;
- `Partial clean — selected metadata remains`.

Never show all four as the same green state.

## 9. Phase 4 — verification receipt

### 9.1 Verify bytes that matter

Add `Sources/VideoCleanVerifier.swift`. For the byte-patch path it must verify:

1. output file opens and plays through AVFoundation;
2. output file size exactly equals input file size;
3. every planned patch range contains the intended replacement;
4. every byte outside planned patch ranges is identical, or equivalently proven by a
   range-aware hashing algorithm;
5. every `mdat` range has the same offset, length, and SHA-256 digest;
6. track count, media types, duration, dimensions, transforms, codecs, and audio policy
   remain unchanged;
7. the output parser no longer finds selected metadata;
8. preserved/unselected metadata remains when a scoped preset is used;
9. no new unsupported parse warning appeared.

For large files, hash `mdat` ranges in bounded chunks. Do not load a media range into
one `Data` allocation.

### 9.2 Produce a structured receipt

```swift
struct VideoCleanReceipt: Sendable {
    let inputSHA256: String?
    let outputSHA256: String?
    let inputSize: UInt64
    let outputSize: UInt64
    let patches: [VerifiedPatch]
    let mediaRanges: [VerifiedMediaRange]
    let removedBlocks: [VideoMetadataBlock]
    let preservedBlocks: [VideoMetadataBlock]
    let remainingSelectedBlocks: [VideoMetadataBlock]
    let playbackChecks: [VerificationCheck]
    let outcome: VideoCleanOutcome
    let limitations: [String]
}
```

The UI may omit full-file hashes by default if expensive, but media-range hashes and
exact preservation checks are required before claiming encoded media was preserved.

### 9.3 Verification state rules

Green is allowed only when all required checks for the selected path pass.

- Red: selected metadata remains, output is unreadable, protected bytes changed, or a
  required invariant fails.
- Orange: report coverage is partial, fallback remux was used without sample identity,
  or unsupported metadata remains.
- Green: selected metadata is gone and the declared preservation contract is proven.

## 10. Phase 5 — Video Clean UI/UX redesign

### 10.1 Workflow states

Each queued video must move through visible states:

```text
Queued → Inspecting → Ready for review → Cleaning → Verifying → Ready to save → Saved
```

Adding a file stops at **Ready for review**. It does not silently clean.

### 10.2 Inspector layout

Use the current fixed 940-pt window and sidebar. Keep a two-pane workspace:

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ Clean  [Images | Videos]             Clear  Save All  Paste URL  Add     │
├──────────────────────────┬───────────────────────────────────────────────┤
│ queue + batch summary    │ selected video inspection                    │
│                          │ preview + source facts                        │
│                          │ 3 summary tiles                               │
│                          │ source-signal alert                           │
│                          │ categorized metadata cards                    │
│                          │ raw box tree disclosure                       │
│                          │ sticky Inspect/Clean/Save action              │
└──────────────────────────┴───────────────────────────────────────────────┘
```

The selected-video inspector should contain, in order:

1. paused player/poster with scrubber when available;
2. filename, container, file size, duration, dimensions, codecs, audio;
3. summary tiles:
   - metadata blocks present;
   - removable changes selected;
   - removable payload bytes;
4. AI/source-signal alert, using the critical red status token when a supported
   generative source is declared;
5. categorized cards:
   - Container dates;
   - Descriptive metadata;
   - Location;
   - Device and software;
   - AI and provenance;
   - Timed metadata;
   - Other/unsupported;
6. collapsed `Raw box tree (N)` disclosure;
7. sticky primary action:
   - `Inspecting…` disabled;
   - `Remove selected metadata` when reviewed;
   - `Save Clean Copy…` only after successful verification.

### 10.3 Metadata row design

Each row should show:

- human title first;
- short value/evidence summary;
- box fourCC/path in monospaced secondary text;
- exact offset and size in advanced text;
- status pill: `Present`, `Selected`, `Removed`, `Preserved`, `Unsupported`, or
  `Still present`;
- a checkbox only when advanced per-block selection is enabled.

Do not make every row red. Use red for the source warning and unresolved critical
privacy findings; use neutral cards for evidence; use green only for verified removal.

### 10.4 Raw box tree

The raw tree must be:

- collapsed by default;
- virtualized/lazy for large trees;
- searchable by fourCC, category, or offset;
- bounded by the parser node limit;
- explicit when children were skipped or parsing was partial;
- copyable as a privacy-safe diagnostic summary without dumping binary payloads.

### 10.5 Batch UX

For multiple files:

- inspection may run with a small bounded concurrency, initially two;
- cleaning remains sequential by default to control disk and I/O pressure;
- queue rows show `N blocks · M changes · X B` after inspection;
- provide `Inspect All` implicitly on intake and `Clean Selected` explicitly;
- `Save All` enables only for verified outputs;
- changing a preset recomputes plans immediately but does not re-read unchanged files;
- file modification invalidates the cached inspection and requires reinspection.

### 10.6 Accessibility and interaction

- all summary values receive meaningful VoiceOver labels;
- disclosure controls and rows are keyboard reachable;
- the primary action remains visible without requiring the user to find the bottom of
  a long scroll view;
- persistent 12-pt Kechil scrollbars remain visible without hover;
- minimum control target is 28 pt on macOS;
- state is conveyed by text and symbols, never colour alone;
- monospaced evidence text supports selection but does not capture arrow-key navigation
  needed by the raw tree.

## 11. Phase 6 — performance engineering

### 11.1 Remove file-size-proportional allocations

The first mandatory optimization is deleting this production behavior from broad/AI
video cleaning:

```swift
let exported = try Data(contentsOf: outputURL)
```

No replacement may create another full-size `[UInt8]`, `Data`, or decoded UTF-8 string.

### 11.2 Performance budgets

Use hardware-independent budgets where possible:

- parser bytes read exclude `mdat` payload and should be close to container metadata,
  not the whole file;
- incremental peak RSS for inspection of a 500-MiB video: target ≤ 32 MiB;
- incremental peak RSS for cleaning/verifying a 500-MiB video: target ≤ 64 MiB,
  excluding OS file cache;
- no synchronous file I/O or hashing on the main actor;
- no main-thread stall over 50 ms during intake, inspection, cleaning, cancellation,
  or row selection in an Instruments run;
- cancellation should stop between bounded read/write chunks and update the UI within
  250 ms under normal local-disk conditions;
- only one large-file copy/patch job runs at a time by default;
- disk preflight reserves source size plus 5% and a fixed safety margin before copying.

Wall-clock times vary by Mac and storage. Record them, but do not make one absolute
second threshold the only performance gate.

### 11.3 Local instrumentation

Add privacy-safe `os_signpost` intervals in debug builds for:

- inspect total;
- box inventory;
- semantic metadata merge;
- temporary clone/copy;
- patch;
- media-range hashing;
- AVFoundation reopen;
- post-clean inspection;
- UI report materialization.

Never include filenames, metadata values, coordinates, IDs, or user paths in log text.

### 11.4 Benchmark harness

Add `Tests/VideoCleanPerformanceChecks.swift` or a dedicated local benchmark tool that
reports:

- file size;
- parser bytes read;
- box count;
- inspection time;
- copy/clone time;
- patch time;
- verification/hash time;
- peak resident memory where measurable;
- cancellation latency.

Use generated fixtures at approximately 0.5 MiB, 50 MiB, and 500 MiB. A large fixture
may be generated locally and excluded from source control; commit the generation script
and expected structural manifest instead.

## 12. File-by-file implementation map

| File | Action |
| --- | --- |
| `Sources/VideoMetadataProbe.swift` | Refactor into AVFoundation semantic adapter; remove bounded raw string scanning after the deterministic reader lands. |
| `Sources/MediaContainerSanitizer.swift` | Replace whole-`Data` API with patch planning/range writing; retain small-data helpers only for deterministic unit fixtures if useful. |
| `Sources/VideoCleanPipeline.swift` | Split inspect, plan, clean, and verify; prefer clone+patch; retain clearly labelled exporter fallback. |
| `Sources/VideoCleanModel.swift` | Add inspect-first states, cached reports/plans, explicit clean action, invalidation, batch selection, and bounded concurrency. |
| `Sources/VideoQueueItem.swift` | Store inspection report, removal plan, receipt, stage progress, source fingerprint, and output contract. |
| `Sources/VideoCleanView.swift` | Replace flat findings/result view with summary tiles, categorized cards, source alert, raw tree, and sticky action. |
| `Sources/MediaContracts.swift` | Add shared inspection/removal/receipt states only when they are media-neutral; avoid video-specific leakage into image routes. |
| `Sources/ISOBaseMediaReader.swift` | New deterministic random-access parser. |
| `Sources/VideoInspectionReport.swift` | New unified report and evidence models. |
| `Sources/VideoRemovalPlanner.swift` | New preset/per-block planning and byte accounting. |
| `Sources/VideoTemporaryClone.swift` | New sandbox-safe clone/copy and disk preflight. |
| `Sources/VideoFilePatcher.swift` | New validated random-access writer. |
| `Sources/VideoCleanVerifier.swift` | New post-clean box, media-range, playback, and receipt verification. |
| `Sources/VideoCleanInspectorView.swift` | Optional extraction when `VideoCleanView` becomes too large. |
| `Tests/ISOBaseMediaReaderChecks.swift` | New parser safety and exact-fixture checks. |
| `Tests/VideoRemovalPlannerChecks.swift` | New scope/action/byte-count checks. |
| `Tests/VideoFilePatcherChecks.swift` | New offset/size/protected-range tests. |
| `Tests/VideoCleanVerificationChecks.swift` | New media-range identity and post-clean receipt tests. |
| `Tests/UISnapshotRenderer.swift` | Add inspected, AI source, partial, verified, and compact-height Video Clean snapshots. |
| `tools/check.sh` | Compile/run all new deterministic gates; keep offline and reproducible. |
| `docs/qa/VIDEO_CLEAN_REFERENCE_BASELINE.md` | New competitor/current-product evidence record. |
| `docs/DEVELOPMENT_HANDOFF.md` | Update only after each phase is actually implemented and verified. |

## 13. Testing matrix

### 13.1 Correctness fixtures

| Fixture | Required assertion |
| --- | --- |
| Synthetic OpenAI 5-second MOV | Exact derived box/block/action/byte counts; source signal; all selected metadata removed; media bytes preserved. |
| Clean H.264 MP4 | No false metadata or AI signal; no clean action required. |
| iPhone portrait MOV with GPS/date/device | Correct transform, GPS/date/device categories; scoped removal preserves unrelated fields. |
| HEVC MOV with audio | Video/audio range preservation and playable verified output. |
| No-audio MP4 | No invented audio track; preservation checks pass. |
| Multiple audio tracks | Track count/order preserved or file marked unsupported. |
| Timed metadata track | Explicit support/unsupported result; never silently drop. |
| Fragmented MP4 | Safe parse; patch only if invariants can be proven. |
| `moov` after `mdat` | Correct offsets and no full payload scan. |
| Multiple `mdat` boxes | Every range hashed and preserved. |
| HDR/Dolby Vision | Inspection safe; Clean preserves media; no colour conversion. |
| Spatial/multiview or unusual groups | Explicit unsupported/partial result without damage. |
| Malformed/truncated file | Bounded error, no crash, no output exposed. |
| 500-MiB generated movie | Bounded memory, progress, cancellation, disk preflight. |

### 13.2 Scope behavior

For each supported fixture, test the four legacy image presets and the five independent
video Clean groups. Video tests should also cover representative combinations (location
only, credentials plus dates, and all groups selected):

Image presets:

- Remove all metadata;
- AI metadata;
- Remove EXIF/device data;
- Remove GPS.

Video groups:

- Content Credentials;
- Descriptive metadata;
- XMP;
- Location;
- Container dates.

Assert both sides:

- selected fields are gone;
- unselected fields remain;
- encoded media ranges remain identical on the byte-patch path.

### 13.3 UI states

Snapshot and manually inspect:

- empty;
- inspecting;
- ready with no findings;
- ready with ordinary metadata;
- ready with declared AI source;
- advanced tree expanded;
- cleaning with progress/cancel;
- verified byte-preserving result;
- remuxed warning result;
- partial result;
- failure;
- saved;
- minimum dashboard height;
- dark appearance;
- VoiceOver reading order;
- keyboard-only operation.

## 14. Implementation order and review checkpoints

### Milestone A — recorded baseline and parser

Deliver:

- Phase 0 reference record;
- deterministic box reader;
- exact fixture inventory;
- no production cleaner changes yet.

Checkpoint: inspect parser results with Aminudin before implementing UI or mutation.

### Milestone B — inspection report and read-only UI

Deliver:

- unified report;
- summary counts;
- source-signal evidence;
- categorized metadata cards;
- raw tree;
- inspect-first queue state.

Checkpoint: render and review the exact synthetic fixture at 940 × 900 and minimum
height. The primary action may remain disabled until the patcher is ready.

### Milestone C — byte-preserving clean and verification

Deliver:

- removal planner;
- temporary clone/copy;
- random-access patcher;
- media-range verification;
- structured receipt;
- explicit clean action.

Checkpoint: all exact-fixture, scoped-removal, malformed-input, and media-range tests
pass. Compare the output with the recorded reference output without assuming identical
whole-file hashes.

### Milestone D — performance and batch hardening

Deliver:

- no full-file allocations;
- disk preflight;
- progress/cancel;
- benchmark report;
- bounded inspection concurrency;
- long-file and large-file tests.

Checkpoint: Instruments run shows no meaningful main-thread I/O and memory stays within
the stated budgets.

### Milestone E — release acceptance

Deliver only when requested:

- full `tools/check.sh` pass;
- visual snapshot inspection;
- manual real iPhone MOV, landscape MP4, portrait M4V, no-audio, and long-file tests;
- installed app smoke test;
- universal DMG verification.

Do not change version/build during these milestones unless instructed.

## 15. Stop conditions

Stop and report instead of guessing when:

- a box cannot be bounded safely within its parent;
- a requested patch overlaps `mdat` or another protected range;
- an output changes size unexpectedly on the byte-preserving path;
- media-range hashes change;
- a timed metadata, subtitle, spatial, DRM, or fragmented structure cannot be preserved;
- the parser coverage is partial but the UI would otherwise show green;
- a reference-site result cannot be reproduced and no independent explanation exists;
- an implementation would require a network entitlement or third-party binary.

## 16. Definition of done

This improvement is complete only when all of the following are true:

- the same synthetic MOV produces a detailed, explainable pre-clean inventory;
- every summary number traces to typed parser records;
- the user reviews findings before mutation;
- supported removal runs without a full-file memory allocation;
- required header boxes are preserved while supported date values are neutralized;
- C2PA/descriptive metadata actions preserve box/file offsets where promised;
- `mdat` offset, length, and digest are unchanged on the byte-preserving path;
- selected metadata is absent from a complete post-clean inspection;
- unselected metadata survives scoped presets;
- the receipt distinguishes patched, remuxed, re-encoded, partial, and failed results;
- the UI remains responsive on a large file and cancellation works;
- all deterministic tests and UI snapshot assertions pass;
- manual testing covers the stated real-world matrix;
- `docs/DEVELOPMENT_HANDOFF.md` is updated with actual—not planned—behavior;
- version remains `1.0.0` and build remains `1` unless Aminudin explicitly says
  otherwise.

## 17. Immediate first tasks for the next agent

Execute these in order:

1. Produce `docs/qa/VIDEO_CLEAN_REFERENCE_BASELINE.md` using the exact fixture and
   record the interactive reference/Kechil outputs.
2. Add parser-only tests that express the exact expected box inventory without changing
   production cleaning.
3. Implement `ISOBaseMediaReader` until those tests pass safely on valid and malformed
   fixtures.
4. Present the derived inventory and count calculation for review.
5. Implement the read-only inspection report and new UI.
6. Only after the read-only report is accepted, implement planning and random-access
   cleaning.
7. Add media-range verification before enabling the green result.
8. Remove the production whole-file `Data(contentsOf:)` sanitizer path.
9. Run performance/large-file tests and document the results.
10. Update the handoff; do not build a DMG unless explicitly requested.
