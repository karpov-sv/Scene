#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC_FILE="${SPEC_FILE:-$ROOT_DIR/project.yml}"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/Scene.xcodeproj}"
SCHEME="${SCHEME:-SceneApp}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode-tests}"
DESTINATION="${DESTINATION:-platform=macOS}"
TEST_SCOPE="${TEST_SCOPE:-ui}"

usage() {
    cat <<'EOF'
Usage: scripts/run-ui-tests.sh [--ui|--unit|--all]

Runs Xcode-based tests for the macOS app.

Options:
  --ui     Run UI tests only (default)
  --unit   Run unit tests only
  --all    Run unit + UI tests
  -h, --help
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: '$1' is required but not installed." >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ui)
            TEST_SCOPE="ui"
            ;;
        --unit)
            TEST_SCOPE="unit"
            ;;
        --all)
            TEST_SCOPE="all"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument '$1'" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

require_command xcodegen
require_command xcodebuild

echo "Generating Xcode project from $SPEC_FILE"
xcodegen generate --spec "$SPEC_FILE" --project "$ROOT_DIR"

TEST_FLAGS=()
case "$TEST_SCOPE" in
    ui)
        TEST_FLAGS=(-only-testing:SceneAppUITests)
        ;;
    unit)
        TEST_FLAGS=(-only-testing:SceneAppTests)
        ;;
    all)
        ;;
esac

echo "Running $TEST_SCOPE tests for $SCHEME"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    test "${TEST_FLAGS[@]}"
