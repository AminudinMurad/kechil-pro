#!/usr/bin/env bash
# Installs the already-built Kechil PRO bundle and verifies the copy users run.
set -euo pipefail
trap 'echo "Install failed at line $LINENO: $BASH_COMMAND" >&2' ERR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/build/Kechil PRO.app"
DESTINATION="/Applications/Kechil PRO.app"
BACKUP_ROOT="$ROOT/build/install-backups"

[[ -d "$SOURCE" ]] || {
  echo "error: build/Kechil PRO.app does not exist; run tools/build-app.sh first" >&2
  exit 1
}

clean_and_verify() {
  local app="$1"
  xattr -cr "$app"
  xattr -d com.apple.FinderInfo "$app" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$app" 2>/dev/null || true
  codesign --verify --deep --strict "$app"
}

echo "==> Verifying build"
clean_and_verify "$SOURCE"

if [[ -e "$DESTINATION" ]]; then
  mkdir -p "$BACKUP_ROOT"
  backup="$BACKUP_ROOT/Kechil PRO-$(date +%Y%m%d-%H%M%S).app"
  echo "==> Preserving existing app"
  mv "$DESTINATION" "$backup"
  echo "    backup: $backup"
fi

echo "==> Installing"
ditto "$SOURCE" "$DESTINATION"

echo "==> Verifying installed copy"
clean_and_verify "$DESTINATION"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DESTINATION/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DESTINATION/Contents/Info.plist")"
architectures="$(lipo -archs "$DESTINATION/Contents/MacOS/KechilPRO")"

echo "Installed: $DESTINATION"
echo "Version:   $version ($build)"
echo "Archs:     $architectures"
