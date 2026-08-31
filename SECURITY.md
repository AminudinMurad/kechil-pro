# Security Policy

## Reporting a vulnerability

Please report security issues privately rather than opening a public issue.
Open a [GitHub security advisory](../../security/advisories/new) with steps to
reproduce and the affected version. Expect an initial response within a few
days.

## Threat model

Kechil PRO exists to prevent unintended disclosure through image metadata.
The security properties that matter most:

**No uploads or inbound server access.** `App/KechilPRO.entitlements` enables the
App Sandbox, user-selected file access and `com.apple.security.network.client`.
That outbound entitlement is used only when the user asks Kechil to fetch one direct
image or video URL into its temporary folder. Kechil does not upload media, run a
network server, send telemetry or make a background licensing/update request. The
inbound `com.apple.security.network.server` entitlement remains absent.

YouTube, Facebook and Instagram page and media-delivery domains are rejected. Kechil
does not scrape those platforms, accept their account cookies or reconstruct their
playback streams. Media owned by the user should be exported through the platform's
official tools and imported as a local file.

Audit any build yourself:

```bash
codesign -d --entitlements - "Kechil PRO.app"
```

A legitimate signed build lists the sandbox, user-selected file and outbound client
entitlements. A build that lists `com.apple.security.network.server` falls outside
Kechil's stated security boundary and should be reported.

**No file access beyond what you pick.** The app can only read and write files
and folders selected through a system open/save panel.

**No telemetry, no analytics, no update check.** There is nothing to disable,
because there is nothing that could phone home.

## Interpreting the guarantee correctly

The app removes metadata: EXIF, GPS, IPTC, XMP, C2PA Content Credentials, maker
notes, embedded text and timestamps.

The **Clean** tool does **not** remove information encoded into pixels themselves.
Invisible watermarks such as SynthID and steganographic payloads survive because they
are not metadata. Kechil PRO's separate Watermark tool can add a visible watermark, but
does not change this limitation. Treat a cleaned image as free of the metadata the app
verified as removed, not as untraceable.

Also worth knowing: metadata may persist in copies you have already shared, in
cloud backups of the original, and in derivative files exported by other
software.

## Verifying a release

Release archives are published with SHA-256 checksums under `releases/`. The app
bundle is ad-hoc signed for local distribution unless the release notes explicitly
state that a Developer ID signature and notarisation are present. Verify the
checksum before installing:

```bash
shasum -a 256 -c Kechil-PRO-vX.Y.Z-macos-universal.dmg.sha256
```
