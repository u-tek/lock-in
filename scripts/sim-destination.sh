#!/usr/bin/env bash
# Prints an xcodebuild -destination for an available iPhone simulator.
#
#   scripts/sim-destination.sh                  # newest-runtime iPhone whose name contains "Pro"
#   scripts/sim-destination.sh "iPhone 16 Pro"  # exact device name, newest runtime that has it
#
# Exits non-zero if nothing matches.
set -euo pipefail

want="${1:-Pro}"

xcrun simctl list devices available -j | python3 -c '
import json, re, sys

want = sys.argv[1]
exact = want.startswith("iPhone")
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, entries in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in entries:
        name = device["name"]
        if not name.startswith("iPhone"):
            continue
        if (exact and name != want) or (not exact and want not in name):
            continue
        key = (version, name)
        if best is None or key > best[0]:
            best = (key, device["udid"])
if best is None:
    sys.exit(f"No available iPhone simulator matches {want!r}")
print(f"platform=iOS Simulator,id={best[1]}")
' "$want"
