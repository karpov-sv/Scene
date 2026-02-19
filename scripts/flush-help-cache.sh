#!/usr/bin/env bash
# Flush all macOS help-related caches so updated help book content is picked up.
# Run after rebuilding the app when help pages have changed.
set -euo pipefail

# Official hiutil purge: shuts down helpd and clears its caches + preferences
hiutil -P 2>/dev/null || true

# Clear the help bundle copy that helpd serves content from
rm -rf ~/Library/Group\ Containers/group.com.apple.helpviewer.content/Library/Caches 2>/dev/null || true

# Clear helpd caches (index, plist, generated search indexes)
rm -rf ~/Library/Caches/com.apple.helpd 2>/dev/null || true
rm -rf ~/Library/HTTPStorages/com.apple.helpd 2>/dev/null || true

# Clear HelpViewer container (WebKit page cache, preferences, saved state)
rm -rf ~/Library/Containers/com.apple.helpviewer/Data/Library/Caches 2>/dev/null || true
rm -rf ~/Library/Containers/com.apple.helpviewer/Data/Library/Saved\ Application\ State 2>/dev/null || true
rm -rf ~/Library/Containers/com.apple.helpviewer/Data/Library/WebKit 2>/dev/null || true

# Clear tipsd cache (macOS 15 routes help through Tips)
rm -rf ~/Library/Caches/com.apple.tipsd 2>/dev/null || true
rm -rf ~/Library/HTTPStorages/com.apple.tipsd 2>/dev/null || true

# Restart daemons
killall helpd 2>/dev/null || true
killall tipsd 2>/dev/null || true

echo "Help caches flushed. Relaunch the app to see updated help content."
