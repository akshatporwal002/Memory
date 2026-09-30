#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$PROJECT_ROOT/Engram.xcodeproj"
DERIVED_DATA="$PROJECT_ROOT/.build/xcode"
APP_NAME="Engram-macOS"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
xcodegen generate --spec "$PROJECT_ROOT/project.yml" >/dev/null
perl -0pi -e 's/(isa = XCSwiftPackageProductDependency;\n)(\s+productName)/$1\t\t\tpackage = 8B569F3F9CF22A765B039142 \/\* XCLocalSwiftPackageReference "." \*\/;\n$2/g' "$PROJECT/project.pbxproj"
xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$APP_NAME" >/dev/null
xcodebuild -project "$PROJECT" -scheme "$APP_NAME" -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO -configuration Debug build

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }

case "$MODE" in
  run) open_app ;;
  --verify|verify) open_app; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate 'subsystem == "dev.engram.study.mac"' ;;
  --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  *) echo "usage: $0 [run|--verify|--logs|--telemetry|--debug]" >&2; exit 2 ;;
esac
