#!/usr/bin/env bash
# Claude Tracker statusline tap.
#
# Claude Code pipes a JSON snapshot (model, context window, cost, rate limits) to the
# statusline command on every render. This tap stores the latest snapshot per session so
# Claude Tracker can show 5-hour / weekly limits:
#   ~/Library/Application Support/ClaudeTracker/statusline/<account>/<session_id>.json
#
# Call it from a statusline script right after the input is read, in the background:
#   printf '%s' "$input" | statusline-tap.sh >/dev/null 2>&1 &
# scripts/install-statusline-tap.sh does that for you. It never prints to stdout, so it
# cannot change what the statusline shows.
set -u

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
config_name="$(basename "$config_dir")"
case "$config_name" in
    .claude) account="default" ;;
    .claude-*) account="${config_name#.claude-}" ;;
    *) account="$config_name" ;;
esac

target_dir="$HOME/Library/Application Support/ClaudeTracker/statusline/$account"
mkdir -p "$target_dir" || exit 0

tmp_file="$(mktemp "$target_dir/.tap.XXXXXX")" || exit 0
trap 'rm -f "$tmp_file"' EXIT
cat > "$tmp_file"

session_id=""
if command -v jq >/dev/null 2>&1; then
    session_id="$(jq -r '.session_id // empty' "$tmp_file" 2>/dev/null)"
fi
# Only plain ids become file names (no path traversal from a malformed snapshot).
[[ "$session_id" =~ ^[A-Za-z0-9_-]+$ ]] || session_id="latest"

mv -f "$tmp_file" "$target_dir/$session_id.json"
trap - EXIT

# Snapshots of closed sessions are useless after a day.
find "$target_dir" -name '*.json' -mtime +1 -delete 2>/dev/null
exit 0
