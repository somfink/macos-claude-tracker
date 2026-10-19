#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from the mascot sprite (MascotSprites.appIcon).
# Run after changing the sprite or its colors; bundle.sh only copies the result.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
ICONSET="$WORK_DIR/AppIcon.iconset"
MASTER="$WORK_DIR/icon-1024.png"

cd "$ROOT"
swift build --product ClaudeTracker
# The app renders the master and exits; the wait is bounded in case it launches normally instead.
CLAUDE_TRACKER_ICON="$MASTER" "$(swift build --show-bin-path)/ClaudeTracker" &
RENDER_PID=$!
for _ in $(seq 1 60); do
    kill -0 "$RENDER_PID" 2>/dev/null || break
    sleep 1
done
if kill -0 "$RENDER_PID" 2>/dev/null; then
    kill "$RENDER_PID"
    echo "error: icon rendering did not finish within 60 s" >&2
    exit 1
fi
[[ -f "$MASTER" ]] || { echo "error: icon master was not rendered" >&2; exit 1; }

mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote $ROOT/Resources/AppIcon.icns"
