#!/bin/sh
# installed by herdr traex integration plugin
# Bounded watcher for TraeX question prompts. AskUserQuestion does not emit a
# hook while its modal blocks, so this checks the visible pane briefly after a
# user prompt and reports blocked only when the question UI is actually visible.

set -eu

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0

HERDR_BIN="${HERDR_BIN_PATH:-herdr}"
command -v "$HERDR_BIN" >/dev/null 2>&1 || exit 0

pane_id="$HERDR_PANE_ID"
lock_path="${TMPDIR:-/tmp}/herdr-traex-question-${pane_id}.lock"
if ! (set -C; echo "$$" >"$lock_path") 2>/dev/null; then
    existing_pid="$(cat "$lock_path" 2>/dev/null || true)"
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
        exit 0
    fi
    rm -f "$lock_path"
    if ! (set -C; echo "$$" >"$lock_path") 2>/dev/null; then
        exit 0
    fi
fi
trap 'rm -f "$lock_path"' EXIT HUP INT TERM

seq_ns() {
    python3 - <<'PY' 2>/dev/null || date +%s
import time
print(time.time_ns())
PY
}

is_question_visible() {
    awk '
        index($0, "Question ") && index($0, "/") && index($0, " unanswered)") { q = 1 }
        /enter to submit answer/ { enter = 1 }
        /esc to interrupt/ { esc = 1 }
        END { exit !(q && enter && esc) }
    '
}

report_blocked() {
    "$HERDR_BIN" pane report-agent "$pane_id" \
        --source "herdr:traex-question" \
        --agent "traex" \
        --state "blocked" \
        --custom-status "awaiting answer" \
        --seq "$(seq_ns)" >/dev/null 2>&1 || true
}

# AskUserQuestion usually appears within a few seconds of UserPromptSubmit, but
# model latency can be longer. Keep this bounded so a missed prompt never leaves
# a long-lived process behind.
deadline=$(( $(date +%s) + ${HERDR_TRAEX_QUESTION_WATCH_SECONDS:-90} ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    screen="$("$HERDR_BIN" pane read "$pane_id" --source visible --lines 60 2>/dev/null || true)"
    if printf '%s\n' "$screen" | is_question_visible; then
        report_blocked
        exit 0
    fi
    sleep 1
done

exit 0
