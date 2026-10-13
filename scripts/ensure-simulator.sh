#!/usr/bin/env bash
# Prints the UDID of an iPhone simulator with exactly this name on the newest iOS runtime,
# creating the simulator if it doesn't exist yet. The name defaults to the phone's.
#
#   scripts/ensure-simulator.sh "iPhone SE (3rd generation)" ["Snapshots iPhone SE (3rd generation)"]
set -euo pipefail

python3 - "$1" "${2:-$1}" <<'PY'
import json, subprocess, sys

phone, name = sys.argv[1], sys.argv[2]

def simctl(*args):
    return subprocess.run(["xcrun", "simctl", *args], check=True, capture_output=True, text=True).stdout

runtimes = [
    runtime for runtime in json.loads(simctl("list", "runtimes", "-j"))["runtimes"]
    if runtime.get("platform") == "iOS" and runtime.get("isAvailable")
]
if not runtimes:
    sys.exit("No available iOS simulator runtime")
runtime = max(runtimes, key=lambda r: [int(part) for part in r["version"].split(".")])

for device in json.loads(simctl("list", "devices", "available", "-j"))["devices"].get(runtime["identifier"], []):
    if device["name"] == name:
        print(device["udid"])
        sys.exit(0)

device_type = next((t for t in json.loads(simctl("list", "devicetypes", "-j"))["devicetypes"] if t["name"] == phone), None)
if device_type is None:
    sys.exit(f"No simulator device type named {phone!r}")
supported = {t["identifier"] for t in runtime.get("supportedDeviceTypes", [])}
if supported and device_type["identifier"] not in supported:
    sys.exit(f"{phone} isn't supported by {runtime['name']}")
print(simctl("create", name, device_type["identifier"], runtime["identifier"]).strip())
PY
