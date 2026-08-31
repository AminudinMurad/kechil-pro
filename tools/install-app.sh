#!/usr/bin/env bash
# Installs the already-built Kechil PRO bundle and verifies the copy users run.
set -euo pipefail
trap 'echo "Install failed at line $LINENO: $BASH_COMMAND" >&2' ERR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/build/Kechil PRO.app"
DESTINATION="/Applications/Kechil PRO.app"
BACKUP_ROOT="$ROOT/build/install-backups"
# The project folder can be File Provider-backed. Stage outside it so Finder
# bookkeeping cannot be reattached between xattr cleanup and codesign.
STAGE="$(mktemp -d "${TMPDIR:-/private/tmp}/kechil-pro-install-stage.XXXXXX")"
STAGED_SOURCE="$STAGE/Kechil PRO.app"
trap 'rm -rf "$STAGE"' EXIT

[[ -d "$SOURCE" ]] || {
  echo "error: build/Kechil PRO.app does not exist; run tools/build-app.sh first" >&2
  exit 1
}

verify_signature() {
  local app="$1"
  for _ in {1..20}; do
    xattr -cr "$app"
    xattr -d com.apple.FinderInfo "$app" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$app" 2>/dev/null || true
    if codesign --verify --deep --strict "$app" 2>/dev/null; then
      return 0
    fi
  done
  codesign --verify --deep --strict "$app"
}

echo "==> Verifying build"
ditto "$SOURCE" "$STAGED_SOURCE"
verify_signature "$STAGED_SOURCE"

if [[ -e "$DESTINATION" ]]; then
  mkdir -p "$BACKUP_ROOT"
  backup="$BACKUP_ROOT/Kechil PRO-$(date +%Y%m%d-%H%M%S).app"
  echo "==> Preserving existing app"
  mv "$DESTINATION" "$backup"
  echo "    backup: $backup"
fi

echo "==> Installing"
ditto "$STAGED_SOURCE" "$DESTINATION"

echo "==> Verifying installed copy"
verify_signature "$DESTINATION"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DESTINATION/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DESTINATION/Contents/Info.plist")"
architectures="$(lipo -archs "$DESTINATION/Contents/MacOS/KechilPRO")"

echo "Installed: $DESTINATION"
echo "Version:   $version ($build)"
echo "Archs:     $architectures"
