#!/usr/bin/env bash
# Flush the macOS helpd cache so updated help book content is picked up.
# Run after rebuilding the app when help pages have changed.
set -euo pipefail

rm -rf ~/Library/Caches/com.apple.helpd 2>/dev/null || true
killall helpd 2>/dev/null || true

echo "Help cache flushed. Relaunch the app to see updated help content."
