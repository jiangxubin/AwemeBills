#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AwemeBillingApp/AwemeBillingApp.xcodeproj"
SCHEME="AwemeBillingApp"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/DerivedData-quality-gate}"

cd "$ROOT_DIR"

echo "== Project =="
echo "Root: $ROOT_DIR"
echo "Project: $PROJECT_PATH"
echo "Scheme: $SCHEME"
echo "Derived data: $DERIVED_DATA_PATH"

echo
echo "== Tracked generated files =="
tracked_generated="$(
  git ls-files | rg '(^|/)(DerivedData|Build|\.module-cache|xcuserdata|project\.xcworkspace)(/|$)|\.(xcuserstate|xcresult|ipa|xcarchive|dSYM)$|^simulator-.*\.png$|^ui-redesign-.*\.png$' || true
)"
if [[ -n "$tracked_generated" ]]; then
  echo "$tracked_generated"
  echo "Remove generated/user-local files from git before continuing." >&2
  exit 1
fi
echo "OK"

echo
echo "== Secret scan =="
secret_hits="$(
  rg -n 'AKID[[:alnum:]]{16,}|sk-proj-[[:alnum:]_-]{20,}|AIza[[:alnum:]_-]{20,}|K[0-9]{10,}|JROA[[:alnum:]]{16,}' . \
    --glob '!OCR_iOS_SDK_v*/**' \
    --glob '!DerivedData*/**' \
    --glob '!.module-cache/**' \
    --glob '!.git/**' \
    --glob '!docs/ios-engineering-governance.md' || true
)"
if [[ -n "$secret_hits" ]]; then
  echo "$secret_hits"
  echo "Potential secret material found in tracked project files." >&2
  exit 1
fi
echo "OK"

echo
echo "== Whitespace =="
git diff --check

echo
echo "== Build for testing =="
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination 'generic/platform=iOS Simulator' \
  build-for-testing
