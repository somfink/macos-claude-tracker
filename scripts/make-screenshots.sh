#!/usr/bin/env bash
# Renders the README screenshots (docs/screenshots/*.png) from invented demo data, so no real
# session, project or client name can end up in them. Needs python3 (ships with Xcode).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/docs/screenshots"
DEMO_HOME="$(mktemp -d)"
trap 'rm -rf "$DEMO_HOME"' EXIT

python3 - "$DEMO_HOME" <<'PY'
import json, os, sys, time, uuid, random
from datetime import datetime, timedelta, timezone

home = sys.argv[1]
now = datetime.now(timezone.utc)
random.seed(7)

def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)

def dumps(value):
    # Compact like Claude Code's own files: the tracker pre-filters lines by `"type":"assistant"`.
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)

def slug(path):
    return "".join(c if c.isalnum() else "-" for c in path)

def assistant(msg_id, when, cwd, text=None, output=40_000, model="claude-opus-5-5"):
    content = [{"type": "text", "text": text}] if text else []
    return dumps({
        "type": "assistant", "entrypoint": "cli", "cwd": cwd,
        "timestamp": when.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "message": {"id": msg_id, "model": model, "role": "assistant", "content": content,
                    "usage": {"input_tokens": 2_000, "output_tokens": output,
                              "cache_read_input_tokens": 400_000, "cache_creation_input_tokens": 30_000}},
    })

def transcript(account, cwd, sid, title, answer, days_back=0, messages=6, modified=None):
    lines = [dumps({"type": "ai-title", "aiTitle": title, "sessionId": sid})]
    for i in range(messages):
        when = now - timedelta(days=random.randint(0, days_back), hours=random.randint(0, 6))
        lines.append(assistant(f"{sid}-{i}", when, cwd, output=random.randint(20_000, 90_000)))
    lines.append(assistant(f"{sid}-last", now - timedelta(minutes=5), cwd, text=answer))
    path = f"{home}/.claude-{account}/projects/{slug(cwd)}/{sid}.jsonl"
    write(path, "\n".join(lines) + "\n")
    if modified:
        t = time.mktime(modified.timetuple())
        os.utime(path, (t, t))

projects = "/Users/demo/Projects"
live = [
    ("work", "Acme Portal v2", "busy", None, "Refaktor modułu płatności",
     "Przeniosłem walidację do PaymentPolicy, testy przechodzą. Zostało podpięcie webhooka.", 12, 74),
    ("work", "Acme Portal v2", "waiting", "input needed", "ACME-204 migracja bazy",
     "Migracja gotowa w trybie dry-run. Czy mogę uruchomić ją na stagingu?", 3, 41),
    ("personal", "Orbit", "busy", None, "Tryb offline w aplikacji",
     "Dodaję kolejkę synchronizacji i testy konfliktów zapisu.", 25, 88),
    ("personal", "Studio-WEB", "idle", None, "Galeria zdjęć w portfolio",
     "Gotowe: lazy loading, miniatury WebP i lightbox z obsługą klawiatury.", 40, 23),
    ("work", "design-system", "shell", None, "Nowe tokeny kolorów",
     "Tokeny wygenerowane, Storybook buduje się w tle.", 65, 12),
]
for index, (account, folder, status, waiting, title, answer, minutes, context) in enumerate(live, start=1):
    sid = str(uuid.UUID(int=random.getrandbits(128)))
    cwd = f"{projects}/{folder}"
    record = {"pid": 1, "sessionId": sid, "cwd": cwd, "status": status, "kind": "interactive",
              "entrypoint": "cli", "name": folder.lower(), "nameSource": "derived",
              "statusUpdatedAt": int((now - timedelta(minutes=minutes)).timestamp() * 1000)}
    if waiting:
        record["waitingFor"] = waiting
    write(f"{home}/.claude-{account}/sessions/{index}.json", dumps(record))
    transcript(account, cwd, sid, title, answer, days_back=now.day - 1, messages=40)
    write(f"{home}/Library/Application Support/ClaudeTracker/statusline/{account}/{sid}.json", dumps({
        "session_id": sid,
        "context_window": {"used_percentage": context},
        "rate_limits": {
            "five_hour": {"used_percentage": 64 if account == "work" else 31,
                          "resets_at": (now + timedelta(hours=2, minutes=12)).timestamp()},
            "seven_day": {"used_percentage": 47 if account == "work" else 22,
                          "resets_at": (now + timedelta(days=3)).timestamp()},
        },
    }))

finished = [
    ("work", "Acme Portal v2", "Poprawka eksportu CSV", "Eksport obsługuje już polskie znaki i separator średnika."),
    ("personal", "Orbit", "Ikony w pasku zakładek", "Podmieniłem ikony na SF Symbols i dodałem stany aktywne."),
    ("work", "design-system", "Przegląd dostępności", "Kontrast przycisków poprawiony, zostały dwa formularze."),
]
for hours, (account, folder, title, answer) in enumerate(finished, start=1):
    sid = str(uuid.UUID(int=random.getrandbits(128)))
    transcript(account, f"{projects}/{folder}", sid, title, answer, messages=8,
               modified=datetime.now() - timedelta(hours=hours))
PY

cd "$ROOT"
swift build --product ClaudeTracker
BINARY="$(swift build --show-bin-path)/ClaudeTracker"
mkdir -p "$OUT_DIR"
for tab in active finished costs; do
    env -u CLAUDE_CONFIG_DIR CLAUDE_TRACKER_SNAPSHOT_HOME="$DEMO_HOME" CLAUDE_TRACKER_SNAPSHOT_TAB="$tab" \
        CLAUDE_TRACKER_SNAPSHOT="$OUT_DIR/panel-$tab.png" "$BINARY"
    echo "Wrote $OUT_DIR/panel-$tab.png"
done
