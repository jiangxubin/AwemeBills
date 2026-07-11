#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AwemeBillingApp/AwemeBillingApp.xcodeproj"
SCHEME="AwemeBillingApp"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/DerivedData-quality-gate}"
SIMULATOR_ID="${SIMULATOR_ID:-}"

cd "$ROOT_DIR"

echo "== Project =="
echo "Root: $ROOT_DIR"
echo "Project: $PROJECT_PATH"
echo "Scheme: $SCHEME"
echo "Derived data: $DERIVED_DATA_PATH"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This project now requires a native arm64 simulator host." >&2
  exit 1
fi

echo
echo "== Architecture and linker settings =="
forbidden_settings="$(
  grep -En 'x86_64|EXCLUDED_ARCHS|CLANG_CXX_LANGUAGE_STANDARD|OTHER_LDFLAGS|libc\+\+|-lc\+\+' \
    "$PROJECT_PATH/project.pbxproj" || true
)"
if [[ -n "$forbidden_settings" ]]; then
  echo "$forbidden_settings"
  echo "Legacy architecture or manual C++/linker settings remain in the project." >&2
  exit 1
fi
echo "OK: native arm64 only; no manual C++ or linker overrides"

echo
echo "== Tracked generated files =="
tracked_generated="$(
  git ls-files | grep -E '(^|/)(DerivedData|Build|\.module-cache|xcuserdata|project\.xcworkspace)(/|$)|\.(xcuserstate|xcresult|ipa|xcarchive|dSYM)$|^simulator-.*\.png$|^ui-redesign-.*\.png$' || true
)"
if [[ -n "$tracked_generated" ]]; then
  echo "$tracked_generated"
  echo "Remove generated/user-local files from git before continuing." >&2
  exit 1
fi
echo "OK"

echo
echo "== Secret scan =="
secret_hits=""
secret_scan_files=()
while IFS= read -r -d '' file; do
  [[ -f "$file" ]] || continue
  [[ "$file" == OCR_iOS_SDK_v* ]] && continue
  [[ "$file" == "docs/ios-engineering-governance.md" ]] && continue
  secret_scan_files+=("$file")
done < <(git -c core.quotePath=false ls-files -z --cached --others --exclude-standard)

if (( ${#secret_scan_files[@]} > 0 )); then
  secret_hits="$(
    grep -En 'AKID[[:alnum:]]{16,}|sk-proj-[[:alnum:]_-]{20,}|AIza[[:alnum:]_-]{20,}|K[0-9]{10,}|JROA[[:alnum:]]{16,}' \
      "${secret_scan_files[@]}" || true
  )"
fi
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
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  build-for-testing

APP_BINARY="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/AwemeBillingApp.app/AwemeBillingApp"
if [[ ! -f "$APP_BINARY" ]]; then
  echo "Simulator app binary not found: $APP_BINARY" >&2
  exit 1
fi

binary_archs="$(lipo -archs "$APP_BINARY")"
if [[ "$binary_archs" != "arm64" ]]; then
  echo "Unexpected simulator architectures: $binary_archs" >&2
  exit 1
fi
echo "OK: simulator app is arm64"

if [[ -n "$SIMULATOR_ID" ]]; then
  echo
  echo "== Tests =="
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    test-without-building
fi
