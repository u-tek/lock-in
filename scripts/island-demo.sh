#!/usr/bin/env bash
# Films the scripted squad session (IslandDemo in the app) in the simulator's real Dynamic Island
# and on its Lock Screen: a video and a few screenshots, into design/island/ (by way of
# build/design-out, like the snapshots). Run after `xcodebuild build-for-testing` into
# $DERIVED_DATA (default build/DerivedData).
#
#   scripts/island-demo.sh "iPhone 16 Pro"
set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:-iPhone 16 Pro}"
derived_data="${DERIVED_DATA:-build/DerivedData}"
out="$PWD/build/design-out/design/island"
rm -rf "$out"
mkdir -p "$out" build

udid=$(scripts/ensure-simulator.sh "$device" "Snapshots $device")
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
# The demo is a real session: start from a clean install, so onboarding and old activities from a
# snapshot run don't get in the way.
xcrun simctl uninstall "$udid" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$derived_data/Build/Products/Debug-iphonesimulator/Lockin.app/Info.plist")" 2>/dev/null || true

packages=(-skipPackageUpdates)
[[ -n "${SPM_DIR:-}" ]] && packages+=(-clonedSourcePackagesDirPath "$SPM_DIR")

for _ in $(seq 1 24); do
  if xcodebuild -project Lockin.xcodeproj -scheme Lockin -showdestinations 2>/dev/null | grep -q "id:$udid"; then
    break
  fi
  sleep 5
done

# The app's and the system's side of Live Activities, in case nothing shows.
xcrun simctl spawn "$udid" log stream --style compact --level info \
  --predicate 'process == "Lockin" OR process == "LockinWidgets" OR process == "chronod" OR subsystem CONTAINS[c] "activitykit"' \
  > build/island-system.log 2>&1 &
logger=$!

# Films only the demo: the test writes `ready` when it starts and waits for `recording`; it
# writes `done` when it's finished. The whole screen, island and Lock Screen included.
raw_video="$PWD/build/island-raw.mp4"
(
  for _ in $(seq 1 1200); do [[ -f "$out/ready" || -f "$out/done" ]] && break; sleep 0.5; done
  [[ -f "$out/ready" ]] || exit 0
  xcrun simctl io "$udid" recordVideo --codec=h264 --force "$raw_video" &
  recorder=$!
  sleep 2
  touch "$out/recording"
  for _ in $(seq 1 600); do [[ -f "$out/done" ]] && break; sleep 0.5; done
  sleep 1
  # recordVideo finishes the file when it's interrupted.
  kill -INT "$recorder" 2>/dev/null || true
  wait "$recorder" 2>/dev/null || true
) &
watcher=$!

status=0
TEST_RUNNER_LK_ISLAND_DIR="$out" \
  xcodebuild test-without-building -project Lockin.xcodeproj -scheme Lockin \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$derived_data" "${packages[@]}" \
    -only-testing:LockinUITests/IslandDemoTests 2>&1 \
  | tee build/island-test.log | xcbeautify || status=$?

touch "$out/done"
wait "$watcher" 2>/dev/null || true
kill "$logger" 2>/dev/null || true
rm -f "$out/ready" "$out/recording" "$out/done"

# Small enough to commit and to play on a phone: H.264, at most 1920 × 1080.
if [[ -f "$raw_video" ]]; then
  if ! avconvert --source "$raw_video" --output "$out/island.mp4" --preset Preset1920x1080 --replace; then
    echo "::warning::avconvert couldn't shrink the film; keeping it as recorded"
    cp "$raw_video" "$out/island.mp4"
  fi
fi

echo "Live Activity log, last lines:"
tail -n 80 build/island-system.log || true

ls -la "$out"
echo "Filmed $(find "$out" -name '*.png' | wc -l | tr -d ' ') screenshots on $device"
exit "$status"
