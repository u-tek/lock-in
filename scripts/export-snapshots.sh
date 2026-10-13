#!/usr/bin/env bash
# Exports design snapshots on one simulator. Run after `xcodebuild build-for-testing` into
# $DERIVED_DATA (default build/DerivedData).
#
#   scripts/export-snapshots.sh "iPhone 16 Pro"
#
# Routes come from scripts/snapshot-routes.txt, or only those in $LK_ONLY_ROUTES (comma-separated)
# when it's set. There a name also covers every listed route under it ("lab.liveactivity" is the
# page and each lab.liveactivity.<part>, "store" every store.<n>), and a name that matches nothing
# in the file fails the run. Which routes go where:
#   lab.<name>   design-lab pages: iPhone 16 Pro only, into design/lab/<name>-<appearance>.png
#                (a part: design/lab/liveactivity.island-dark.png)
#   store.<n>    App Store screenshots (M6): iPhone 16 Pro Max only, light, into
#                design/appstore/6.9-<n>-light.png, and only when $LK_ONLY_ROUTES names them
#   anything else  app screens on iPhone 16 Pro and iPhone SE, into design/screens/<device>/
# $LK_APPEARANCES (comma-separated, light and/or dark) defaults to dark.
#
# Renders land in build/snapshots/<phone>/; scripts/collect-snapshots.sh then lays them out under
# design/. One launch of the app covers every screen (see UITests/SnapshotExportTests.swift).
set -euo pipefail
cd "$(dirname "$0")/.."

device="$1"
derived_data="${DERIVED_DATA:-build/DerivedData}"
slug=$(echo "$device" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/-+$//')
mkdir -p build

# Carriage returns dropped, in case the file was saved with Windows line endings.
all=$(tr -d '\r' < scripts/snapshot-routes.txt | grep -vE '^[[:space:]]*(#|$)')
status=0
if [[ -n "${LK_ONLY_ROUTES:-}" ]]; then
  # A name stands for itself and every route under it: "lab.liveactivity" is the whole page and
  # each of its parts, "store" every App Store screenshot. Names that match nothing are printed
  # as "?<name>".
  picked=$(echo "$all" | awk -v wanted="$LK_ONLY_ROUTES" '
    BEGIN { n = split(wanted, w, ","); for (i = 1; i <= n; i++) gsub(/^[ \t]+|[ \t]+$/, "", w[i]) }
    {
      keep = 0
      for (i = 1; i <= n; i++) if (w[i] != "" && ($0 == w[i] || index($0, w[i] ".") == 1)) { hit[i] = 1; keep = 1 }
      if (keep) print
    }
    END { for (i = 1; i <= n; i++) if (w[i] != "" && !hit[i]) print "?" w[i] }')
  all=$(echo "$picked" | grep -v '^?' || true)
  unknown=$(echo "$picked" | sed -n 's/^?//p' | paste -sd, -)
  if [[ -n "$unknown" ]]; then
    # Never a quiet green run that rendered nothing: the job fails once the rest are exported.
    echo "::error title=Unknown snapshot route::Not in scripts/snapshot-routes.txt: $unknown. A new screen needs a line there as well as its case in SnapshotGallery."
    status=1
  fi
else
  # App Store screenshots only when asked for ([snapshots: store]): they rarely change, and
  # the 6.9" phone's first boot takes minutes.
  all=$(echo "$all" | grep -vE '^store\.' || true)
fi

case "$slug" in
  iphone-16-pro) routes=$(echo "$all" | grep -vE '^store\.' || true); appearances="${LK_APPEARANCES:-dark}" ;;
  iphone-16-pro-max) routes=$(echo "$all" | grep -E '^store\.' || true); appearances="light" ;;
  *) routes=$(echo "$all" | grep -vE '^(lab|store)\.' || true); appearances="${LK_APPEARANCES:-dark}" ;;
esac
routes=$(echo "$routes" | paste -sd, -)
if [[ -z "$routes" ]]; then
  echo "No routes for $device"
  exit "$status"
fi

# The same simulator scripts/snapshot-simulator.sh may already be booting.
udid=$(scripts/ensure-simulator.sh "$device" "Snapshots $device")
raw="$PWD/build/snapshots/$slug"
rm -rf "$raw"
mkdir -p "$raw"

echo "$(date +%T) Waiting for $device to boot" >> build/simulator.log
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
echo "$(date +%T) $device ready" >> build/simulator.log
xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100

# Use the package checkouts the build used ($SPM_DIR in CI), instead of fetching them again.
packages=(-skipPackageUpdates)
[[ -n "${SPM_DIR:-}" ]] && packages+=(-clonedSourcePackagesDirPath "$SPM_DIR")

TEST_RUNNER_LK_SNAPSHOT_ROUTES="$routes" TEST_RUNNER_LK_SNAPSHOT_DIR="$raw" \
  TEST_RUNNER_LK_SNAPSHOT_APPEARANCES="$appearances" \
  xcodebuild test-without-building -project Lockin.xcodeproj -scheme Lockin \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$derived_data" "${packages[@]}" \
    -only-testing:LockinUITests/SnapshotExportTests \
    | xcbeautify || status=$?

if [[ -f "$raw/failures.txt" ]]; then
  echo "::error::Screens that didn't render on $device: $(paste -sd, "$raw/failures.txt")"
fi

echo "Exported $(find "$raw" -name '*.png' | wc -l | tr -d ' ') screens on $device"
echo "$(date +%T) Exported on $device" >> build/simulator.log
exit "$status"
