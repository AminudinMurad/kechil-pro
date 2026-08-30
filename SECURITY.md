# Security Policy

## Reporting a vulnerability

Please report security issues privately rather than opening a public issue.
Open a [GitHub security advisory](../../security/advisories/new) with steps to
reproduce and the affected version. Expect an initial response within a few
days.

## Threat model

Kechil PRO exists to prevent unintended disclosure through image metadata.
The security properties that matter most:

**No network access.** `App/KechilPRO.entitlements` enables the App Sandbox and
requests only `com.apple.security.files.user-selected.read-write`. It omits
`com.apple.security.network.client` and `com.apple.security.network.server`. A
sandboxed macOS app without those entitlements cannot open a socket, so images
cannot be transmitted even if the app were compromised or contained a bug.

Audit any build yourself:

```bash
codesign -d --entitlements - "Kechil PRO.app"
```

A build that lists a network entitlement is not a legitimate build. Please
report it.

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

Release archives are published with SHA-256 checksums and signatures under
`releases/`. Verify before installing:

```bash
shasum -a 256 -c Kechil-PRO-vX.Y.Z-macos-universal.dmg.sha256
```
