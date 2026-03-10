#!/bin/zsh
# Rebuild chub registry from content and refresh local cache
set -e

CONTENT_DIR="/Users/jwen/workspace/ml/context-hub/content"
DIST_DIR="/Users/jwen/workspace/ml/context-hub/cli/dist"
LOG="/Users/jwen/workspace/ml/context-hub/scripts/rebuild-registry.log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Content change detected — rebuilding registry..." >> "$LOG"

/opt/homebrew/bin/chub build "$CONTENT_DIR" -o "$DIST_DIR" >> "$LOG" 2>&1
/opt/homebrew/bin/chub update --force >> "$LOG" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done." >> "$LOG"
