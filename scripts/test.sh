#!/bin/bash
# Runs the test suite.
#
# On Command-Line-Tools-only toolchains (no full Xcode install), Swift
# Testing's macro plugin is not auto-resolved by the dependency scanner, so we
# load it explicitly. On full Xcode toolchains the plugin resolves itself and
# the extra flag is skipped.
set -euo pipefail
cd "$(dirname "$0")/.."

EXTRA=()
PLUGIN="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$PLUGIN" ]]; then
  EXTRA+=(-Xswiftc -load-plugin-library -Xswiftc "$PLUGIN")
fi

swift test "${EXTRA[@]}"
