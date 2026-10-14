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

# The whole screen, island and Lock Screen included, for as long as the test runs.
xcrun simctl io "$udid" recordVideo --codec=h264 --force "$out/island.mp4" &
recorder=$!
sleep 2

status=0
TEST_RUNNER_LK_ISLAND_DIR="$out" \
  xcodebuild test-without-building -project Lockin.xcodeproj -scheme Lockin \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$derived_data" "${packages[@]}" \
    -only-testing:LockinUITests/IslandDemoTests 2>&1 \
  | tee build/island-test.log | xcbeautify || status=$?

# recordVideo finishes the file when it's interrupted.
kill -INT "$recorder" 2>/dev/null || true
wait "$recorder" 2>/dev/null || true

ls -la "$out"
echo "Filmed $(find "$out" -name '*.png' | wc -l | tr -d ' ') screenshots on $device"
exit "$status"
