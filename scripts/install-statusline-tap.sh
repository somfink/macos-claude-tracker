#!/usr/bin/env bash
# Hooks scripts/statusline-tap.sh into the statusline script of every Claude Code config
# dir (~/.claude, ~/.claude-*), so Claude Tracker can show rate limits.
#
# Usage:
#   scripts/install-statusline-tap.sh              dry run: show what would change
#   scripts/install-statusline-tap.sh --apply      install (backs up each script first)
#   scripts/install-statusline-tap.sh --uninstall  remove the tap lines again
#
# Only statusline scripts that read stdin with `input=$(cat)` are edited; one line is
# added right after it. Everything else is reported for manual setup.
set -euo pipefail

MODE="${1:---dry-run}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAP_SOURCE="$ROOT/scripts/statusline-tap.sh"
TAP_INSTALLED="$HOME/Library/Application Support/ClaudeTracker/bin/statusline-tap.sh"
MARKER="# claude-tracker tap"
TAP_LINE="printf '%s' \"\$input\" | \"$TAP_INSTALLED\" >/dev/null 2>&1 &  $MARKER"
BACKUP_SUFFIX=".bak-claude-tracker"
UNINSTALL_BACKUP_SUFFIX=".bak-claude-tracker-uninstall"

statusline_script() {
    local settings="$1"
    jq -r '.statusLine.command // empty' "$settings" 2>/dev/null | sed "s|^~|$HOME|"
}

process_config_dir() {
    local config_dir="$1"
    local settings="$config_dir/settings.json"
    [[ -f "$settings" ]] || return 0

    local script
    script="$(statusline_script "$settings")"
    if [[ -z "$script" ]]; then
        echo "skip   $config_dir: no statusLine command in settings.json"
        return 0
    fi
    if [[ ! -f "$script" ]]; then
        echo "manual $config_dir: statusLine is not a script file ($script)"
        return 0
    fi

    case "$MODE" in
        --uninstall)
            if grep -qF "$MARKER" "$script"; then
                # Separate copy: the --apply backup stays the pristine pre-install version.
                cp "$script" "$script$UNINSTALL_BACKUP_SUFFIX"
                grep -vF "$MARKER" "$script$UNINSTALL_BACKUP_SUFFIX" > "$script"
                echo "removed $script (backup: $script$UNINSTALL_BACKUP_SUFFIX)"
            fi
            ;;
        --apply | --dry-run)
            if grep -qF "$MARKER" "$script"; then
                echo "ok     $script: tap already installed"
                return 0
            fi
            if ! grep -qE '^input=\$\(cat\)' "$script"; then
                echo "manual $script: no 'input=\$(cat)' line; add after reading stdin:"
                echo "         $TAP_LINE"
                return 0
            fi
            if [[ "$MODE" == "--dry-run" ]]; then
                echo "would  $script: insert after 'input=\$(cat)':"
                echo "         $TAP_LINE"
            else
                cp "$script" "$script$BACKUP_SUFFIX"
                awk -v line="$TAP_LINE" '{ print } /^input=\$\(cat\)/ && !done { print line; done = 1 }' \
                    "$script$BACKUP_SUFFIX" > "$script"
                chmod +x "$script"
                echo "added  $script (backup: $script$BACKUP_SUFFIX)"
            fi
            ;;
        *)
            echo "Unknown option: $MODE" >&2
            exit 2
            ;;
    esac
}

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

if [[ "$MODE" == "--apply" ]]; then
    mkdir -p "$(dirname "$TAP_INSTALLED")"
    cp "$TAP_SOURCE" "$TAP_INSTALLED"
    chmod +x "$TAP_INSTALLED"
    echo "copied tap to $TAP_INSTALLED"
fi

for dir in "$HOME/.claude" "$HOME"/.claude-*; do
    [[ -d "$dir" ]] && process_config_dir "$dir"
done

[[ "$MODE" == "--dry-run" ]] && echo && echo "Dry run only. Re-run with --apply to install."
exit 0
