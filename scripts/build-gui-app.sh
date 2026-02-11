#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC_FILE="${SPEC_FILE:-$ROOT_DIR/project.yml}"
SCHEME="${SCHEME:-SceneApp}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_NAME="${APP_NAME:-SceneApp.app}"
CLEAN=0

usage() {
    cat <<'EOF'
Usage: scripts/build-gui-app.sh [--debug|--release] [--clean]

Builds the native macOS GUI app by:
1) generating an Xcode project from project.yml
2) building with xcodebuild
3) copying SceneApp.app to dist/

Options:
  --debug    Build Debug configuration
  --release  Build Release configuration (default)
  --clean    Remove generated project, derived data, and old dist app before build
  -h, --help Show this help

Environment overrides:
  SPEC_FILE, SCHEME, CONFIGURATION,
  DERIVED_DATA_PATH, DIST_DIR, APP_NAME
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
        --debug)
            CONFIGURATION="Debug"
            ;;
        --release)
            CONFIGURATION="Release"
            ;;
        --clean)
            CLEAN=1
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

if [[ ! -f "$SPEC_FILE" ]]; then
    echo "error: project spec not found at '$SPEC_FILE'" >&2
    exit 1
fi

PROJECT_BASE_NAME="$(awk -F': ' '/^name:[[:space:]]*/ {print $2; exit}' "$SPEC_FILE" | tr -d '"')"
if [[ -z "$PROJECT_BASE_NAME" ]]; then
    echo "error: cannot parse project name from '$SPEC_FILE' (expected 'name: <ProjectName>')" >&2
    exit 1
fi
PROJECT_PATH="$ROOT_DIR/${PROJECT_BASE_NAME}.xcodeproj"

if [[ "$CLEAN" -eq 1 ]]; then
    rm -rf "$PROJECT_PATH" "$DERIVED_DATA_PATH" "$DIST_DIR/$APP_NAME"
fi

echo "Generating Xcode project from $SPEC_FILE"
xcodegen generate --spec "$SPEC_FILE" --project "$ROOT_DIR"

echo "Building $SCHEME ($CONFIGURATION)"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build

APP_SOURCE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$APP_SOURCE" ]]; then
    echo "error: expected app bundle not found at '$APP_SOURCE'" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$DIST_DIR/$APP_NAME"
cp -R "$APP_SOURCE" "$DIST_DIR/$APP_NAME"

echo "App bundle created at:"
echo "  $DIST_DIR/$APP_NAME"
