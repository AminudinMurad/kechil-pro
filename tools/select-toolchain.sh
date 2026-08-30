#!/usr/bin/env bash
#
# Selects a Swift toolchain that can expand SwiftUI macros, and exports DEVELOPER_DIR.
# Meant to be sourced, not run:  . "$(dirname "$0")/select-toolchain.sh"
#
# In the current macOS SDK, SwiftUI's @State is a *macro*, not a property wrapper, so
# expanding it needs libSwiftUIMacros.dylib. Command Line Tools does not ship that
# plugin — only a full Xcode does — and when it is missing every SwiftUI file fails with
# "external macro implementation type ... could not be found", which says nothing about
# the real cause.
#
# Lives in one file because check.sh and build-app.sh both need it, and a copy in each
# is exactly how this became tribal knowledge the first time.

MACRO_REL="Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"

if [ -z "${DEVELOPER_DIR:-}" ] && [ ! -e "$(xcode-select -p)/$MACRO_REL" ]; then
  for candidate in /Applications/Xcode*.app/Contents/Developer; do
    if [ -e "$candidate/$MACRO_REL" ]; then
      export DEVELOPER_DIR="$candidate"
      echo "==> Using $DEVELOPER_DIR (selected toolchain has no SwiftUI macro plugin)"
      break
    fi
  done
fi

if [ ! -e "${DEVELOPER_DIR:-$(xcode-select -p)}/$MACRO_REL" ]; then
  echo "No SwiftUI macro plugin found. Command Line Tools cannot expand @State;" >&2
  echo "install Xcode, or set DEVELOPER_DIR to one that has $MACRO_REL" >&2
  exit 1
fi
