#!/usr/bin/env bash
# Copies the raw renders from build/snapshots/<phone>/ into the repo's layout under the output
# directory (default build/design-out), so copying that over the repo root updates design/:
#   lab.<name>   design/lab/<name>-<appearance>.png
#   store.<n>    design/appstore/6.9-<n>-light.png (M6)
#   anything else  design/screens/<phone>/<route>-<appearance>.png
# Runs after every phone, even one that was cut short: whatever rendered is kept.
set -euo pipefail
cd "$(dirname "$0")/.."

out_root="${1:-build/design-out}"
shopt -s nullglob
for dir in build/snapshots/*/; do
  slug=$(basename "$dir")
  count=0
  for file in "$dir"*.png; do
    base=$(basename "$file")
    case "$base" in
      store.*) mkdir -p "$out_root/design/appstore"; cp "$file" "$out_root/design/appstore/6.9-${base#store.}" ;;
      lab.*) mkdir -p "$out_root/design/lab"; cp "$file" "$out_root/design/lab/${base#lab.}" ;;
      *) mkdir -p "$out_root/design/screens/$slug"; cp "$file" "$out_root/design/screens/$slug/$base" ;;
    esac
    count=$((count + 1))
  done
  echo "Collected $count screens from $slug"
done
