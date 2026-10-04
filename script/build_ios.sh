#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-build}"
TARGET="${2:-iphone}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="/tmp/engram-account-libraries-build"
case "$ACTION" in build|test|--check) ;; *) echo 'Expected build, test or --check.' >&2; exit 2 ;; esac
case "$TARGET" in
  iphone) DEVICE_ID='E75C5BB1-19D3-4085-9BFA-B296E40DFBE9' ;;
  ipad) DEVICE_ID='C9DD5AAC-E456-4648-BCF3-A50DD6D8FFF3' ;;
  device) DEVICE_ID='' ;;
  *) echo 'Expected iphone, ipad or device.' >&2; exit 2 ;;
esac
AVAILABLE_KB="$(df -Pk /tmp | awk 'NR==2 {print $4}')"
if (( AVAILABLE_KB < 20 * 1024 * 1024 )); then
  echo "Less than 20 GiB free. Remove only this task's disposable artifacts; preserve reusable caches." >&2
  exit 1
fi
if [[ -n "$DEVICE_ID" ]]; then
  xcrun simctl list --json | python3 -c '
import json, sys
data = json.load(sys.stdin)
device_id = sys.argv[1]
for runtime in data["runtimes"]:
    devices = data["devices"].get(runtime["identifier"], [])
    device = next((d for d in devices if d["udid"] == device_id), None)
    if device:
        if not device.get("isAvailable") or not runtime.get("isAvailable") or runtime.get("version") != "26.5":
            sys.exit("Requested simulator or iOS 26.5 runtime unavailable; do not create/download replacements without approval.")
        print("Verified:", device["name"], device_id, "iOS", runtime["version"])
        break
else:
    sys.exit("Requested simulator missing; do not create a replacement without approval.")
' "$DEVICE_ID"
  DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"
else
  DESTINATION='generic/platform=iOS'
  if [[ "$ACTION" == test ]]; then echo 'Choose iphone or ipad for simulator tests.' >&2; exit 2; fi
fi
echo "Reusable iOS Debug cache: $DERIVED_DATA"
[[ "$ACTION" == --check ]] && exit 0
cd "$PROJECT_ROOT"
XCODEGEN="$(command -v xcodegen || true)"
if [[ -z "$XCODEGEN" && -x /opt/homebrew/bin/xcodegen ]]; then XCODEGEN=/opt/homebrew/bin/xcodegen; fi
if [[ -z "$XCODEGEN" ]]; then echo 'Use the existing XcodeGen installation; none found.' >&2; exit 1; fi
"$XCODEGEN" generate --spec "$PROJECT_ROOT/project.yml"
SIGNING_ARGS=()
[[ -n "$DEVICE_ID" ]] && SIGNING_ARGS=(CODE_SIGNING_ALLOWED=NO)
if (( $# >= 2 )); then shift 2; else shift "$#"; fi
xcodebuild "$ACTION" -project "$PROJECT_ROOT/Engram.xcodeproj" -scheme Engram-iOS \
  -configuration Debug -destination "$DESTINATION" -derivedDataPath "$DERIVED_DATA" "${SIGNING_ARGS[@]}" "$@"
