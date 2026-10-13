#!/usr/bin/env bash
# Gets the snapshot simulator ready while the app builds, and keeps a booted-once copy of it
# between CI runs.
#
#   scripts/snapshot-simulator.sh key "iPhone 16 Pro"     prints the cache key for this runner
#   scripts/snapshot-simulator.sh start "iPhone 16 Pro"   puts a cached copy in place, then boots it in the background
#   scripts/snapshot-simulator.sh save "iPhone 16 Pro"    shuts it down and copies it into the cache folder
#
# A new simulator's first boot spends minutes setting itself up; a copy that has booted once
# starts far faster. The copy lives in $LK_SIM_CACHE (default ~/lk-simulator) for actions/cache.
# It only suits the same runner image, Xcode and iOS runtime, so the key names all three. If the
# boot also built the runtime's shared cache, that is kept too.
#
# The simulator is called "Snapshots <phone>" so it never mixes with the runner's own.
# Timings go to build/simulator.log.
set -euo pipefail
cd "$(dirname "$0")/.."

command="$1"
phone="$2"
name="Snapshots $phone"
cache="${LK_SIM_CACHE:-$HOME/lk-simulator}"
devices="$HOME/Library/Developer/CoreSimulator/Devices"
dyld=/Library/Developer/CoreSimulator/Caches/dyld
mkdir -p build

stamp() {
  echo "$(date +%T) $*" | tee -a build/simulator.log
}

dyld_size() {
  sudo du -sk "$dyld" 2>/dev/null | cut -f1 || echo 0
}

case "$command" in
  key)
    runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")]
print(max(runtimes, key=lambda r: [int(part) for part in r["version"].split(".")])["buildversion"])
')
    xcode=$(xcodebuild -version | awk '/Build version/ {print $3}')
    slug=$(echo "$phone" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/-+$//')
    echo "simulator-${ImageOS:-macos}-${ImageVersion:-local}-xcode-$xcode-ios-$runtime-$slug-v1"
    ;;

  start)
    if [[ -d "$cache/devices" ]]; then
      for dir in "$cache/devices"/*; do
        rm -rf "${devices:?}/$(basename "$dir")"
        mv "$dir" "$devices/"
      done
      if [[ -d "$cache/dyld" ]]; then
        sudo mkdir -p "$dyld"
        sudo ditto "$cache/dyld" "$dyld"
        sudo chown -R "$(cat "$cache/dyld-owner" 2>/dev/null || echo root:wheel)" "$dyld"
      fi
      # CoreSimulator reads its device folder when it starts, so restart it to pick up the copy.
      killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true
      stamp "Restored the cached simulator"
    fi
    udid=$(scripts/ensure-simulator.sh "$phone" "$name")
    echo "$udid" > build/simulator-udid
    dyld_size > build/dyld-before
    stamp "Booting $name ($udid) in the background; runtime shared cache: $(cat build/dyld-before) KB"
    # shellcheck disable=SC2016 # $1 and $2 belong to the inner shell, not this one.
    nohup bash -c '
      xcrun simctl boot "$1" 2>/dev/null || true
      xcrun simctl bootstatus "$1" -b > /dev/null 2>&1 || true
      echo "$(date +%T) Booted $2" >> build/simulator.log
    ' boot "$udid" "$name" > /dev/null 2>&1 &
    ;;

  save)
    [[ -f build/simulator-udid ]] || { echo "No simulator to keep"; exit 0; }
    udid=$(cat build/simulator-udid)
    # The defaults in Shared.xcconfig: CI's snapshot builds never write a Local.xcconfig.
    bundle_id=$(sed -nE 's/^LK_BUNDLE_ID *= *//p' Config/Shared.xcconfig)
    xcrun simctl uninstall "$udid" "$bundle_id" 2>/dev/null || true
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    rm -rf "$cache"
    mkdir -p "$cache/devices"
    # A clone on APFS: instant, and no extra disk.
    cp -cR "$devices/$udid" "$cache/devices/"
    after=$(dyld_size)
    if [[ "$after" -gt "$(cat build/dyld-before 2>/dev/null || echo 0)" ]]; then
      stat -f '%Su:%Sg' "$dyld" > "$cache/dyld-owner"
      sudo ditto "$dyld" "$cache/dyld"
      sudo chown -R "$(id -un)" "$cache/dyld"
      stamp "Keeping the runtime shared cache it built ($after KB)"
    fi
    stamp "Kept $name for next time: $(du -sh "$cache" | cut -f1)"
    ;;

  *)
    echo "usage: $0 key|start|save <phone>" >&2
    exit 64
    ;;
esac
