#!/usr/bin/env bash
# Archives a Release build for iPhones, signs it for the App Store and uploads it to App Store
# Connect, where it shows up in TestFlight once Apple has processed it (usually within 15 minutes).
# CI runs it for [testflight] commits and manual runs (see .github/workflows/ios.yml).
#
#   scripts/testflight.sh [build number]
#
# The build number defaults to $BUILD_NUMBER, then $GITHUB_RUN_NUMBER. It only has to grow:
# App Store Connect refuses a build number it has already seen for the same version.
#
# Needs Lockin.xcodeproj (`xcodegen generate`) and a Config/Local.xcconfig naming the real team
# and bundle ID (CI writes it from repository secrets), plus an App Store Connect API key:
#   ASC_KEY_ID      the key's ID
#   ASC_ISSUER_ID   the issuer ID shown above the list of keys
#   ASC_KEY_PATH    the key's .p8 file (CI writes it to $RUNNER_TEMP, never into the repo)
#
# Signing is automatic: given the key and -allowProvisioningUpdates, xcodebuild creates the
# profiles it needs, and the export signs with a cloud-managed distribution certificate. That's why
# the key needs the Admin role. The archive first signs for development. With no Apple Development
# certificate on the machine, xcodebuild makes one whose private key stays on that runner, and a
# later run can fail for want of it. When the LK_DEV_CERT_P12 and LK_DEV_CERT_PASSWORD secrets are
# set, CI installs a long-lived one before this runs instead
# (docs/decisions/0003-ci-development-certificate.md). Raw logs go to build/logs/ for when
# xcbeautify's summary isn't enough.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
    echo "::error title=TestFlight::$*"
  else
    echo "error: $*" >&2
  fi
  exit 1
}

# Prints what usually goes wrong at this stage, then the raw error lines from the log.
explain() {
  local stage="$1" log="$2"
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
    echo "::error title=TestFlight $stage failed::Signing and upload need the one-time Apple setup in docs/apple-setup.md. Details below and in the TestFlight logs artifact."
  fi
  cat <<EOF

The $stage failed. If it's about signing, profiles, certificates or authentication, check the
steps in docs/apple-setup.md:
  - the App Store Connect API key has the Admin role (the export creates a cloud-managed
    distribution certificate, and only Admin keys may);
  - APPLE_TEAM_ID is the team the key belongs to, and LK_BUNDLE_ID is an App ID registered on
    that team with Push Notifications and the App Group group.<bundle id>;
  - at least one iPhone is registered under Devices: automatic signing makes a development
    profile while archiving, and Apple won't make one for a team with no devices;
  - "already has an Apple Development signing certificate for this machine, but its private key
    is not installed": an earlier runner made that certificate. Give CI one of its own with the
    LK_DEV_CERT_P12 and LK_DEV_CERT_PASSWORD secrets
    (docs/decisions/0003-ci-development-certificate.md);
  - for the upload: an app with this bundle ID exists in App Store Connect, and this build number
    is higher than the last one uploaded for this version.
Error lines from $log:
EOF
  grep -E '(error|Error|ERROR)' "$log" | awk '!seen[$0]++' | tail -25 || true
}

build_number="${1:-${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}}"
[[ "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
  || fail "Build number '$build_number' should be one to three dot-separated integers, e.g. 42 or 42.2."
[[ -f Lockin.xcodeproj/project.pbxproj ]] || fail "No Lockin.xcodeproj: run 'xcodegen generate' first."
for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
  [[ -n "${!name:-}" ]] || fail "$name isn't set (see the top of scripts/testflight.sh)."
done
[[ -f "$ASC_KEY_PATH" ]] || fail "No App Store Connect key at $ASC_KEY_PATH."

# The same values the build sees: Shared.xcconfig includes Local.xcconfig last, so its lines win.
setting() {
  local files=(Config/Shared.xcconfig)
  [[ -f Config/Local.xcconfig ]] && files+=(Config/Local.xcconfig)
  sed -nE "s/^$1 *= *//p" "${files[@]}" | tail -1 | tr -d '[:space:]'
}
team=$(setting LK_TEAM_ID)
bundle_id=$(setting LK_BUNDLE_ID)
[[ -n "$team" ]] || fail "LK_TEAM_ID is empty: set it in Config/Local.xcconfig (CI writes it from the APPLE_TEAM_ID secret)."
[[ -n "$bundle_id" && "$bundle_id" != com.example.* ]] \
  || fail "LK_BUNDLE_ID is still the placeholder '$bundle_id': set it in Config/Local.xcconfig (CI writes it from the LK_BUNDLE_ID secret)."

mkdir -p build/logs
rm -rf build/Lockin.xcarchive build/export
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

beautify=(cat)
if command -v xcbeautify > /dev/null; then
  beautify=(xcbeautify)
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
    beautify+=(--renderer github-actions)
  fi
fi
auth=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)
# Never empty, so it expands safely under `set -u` in macOS's bash 3.2 too.
packages=(-skipMacroValidation -skipPackagePluginValidation)
if [[ -n "${SPM_DIR:-}" ]]; then
  packages+=(-clonedSourcePackagesDirPath "$SPM_DIR")
fi

echo "Archiving $bundle_id build $build_number for team $team"
# CURRENT_PROJECT_VERSION on the command line reaches every target, so the widget extension's
# CFBundleVersion matches the app's, which App Store Connect requires.
if ! xcodebuild archive -project Lockin.xcodeproj -scheme Lockin -configuration Release \
  -destination generic/platform=iOS -archivePath build/Lockin.xcarchive \
  "${packages[@]}" "${auth[@]}" \
  CURRENT_PROJECT_VERSION="$build_number" \
  2>&1 | tee build/logs/archive.log | "${beautify[@]}"; then
  explain archive build/logs/archive.log
  exit 1
fi

options="$work/ExportOptions.plist"
cp scripts/ExportOptions.plist "$options"
plutil -replace teamID -string "$team" "$options"

echo "Exporting and uploading to App Store Connect"
if ! xcodebuild -exportArchive -archivePath build/Lockin.xcarchive -exportPath build/export \
  -exportOptionsPlist "$options" "${auth[@]}" \
  2>&1 | tee build/logs/export.log | "${beautify[@]}"; then
  explain upload build/logs/export.log
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" \
  build/Lockin.xcarchive/Info.plist 2>/dev/null || echo "?")
message="Uploaded Lockin $version ($build_number) to App Store Connect. It appears in TestFlight once Apple has processed it, usually within 15 minutes."
echo "$message"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "$message" >> "$GITHUB_STEP_SUMMARY"
fi
