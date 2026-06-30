#!/bin/bash
# Fallback monitor for traex state when hook support is unavailable
# This script runs in the background and detects traex state from terminal output

set -eo pipefail

# Only monitor if pane is running traex
pane_id="${HERDR_PANE_ID:-}"
if [ -z "$pane_id" ]; then
    exit 0
fi

# Check if the pane is running traex
pane_info=$(herdr pane get "$pane_id" 2>/dev/null || echo "")
if ! echo "$pane_info" | grep -qi "traex\|traecli"; then
    exit 0
fi

# Simple polling detector
detect_state() {
    content=$(herdr pane read "$pane_id" --source recent --lines 100 2>/dev/null || echo "")
    lower=$(echo "$content" | tr '[:upper:]' '[:lower:]')

    if echo "$lower" | grep -qE "permission required|allow once or always|waiting for user confirmation|awaiting approval|asking user|enter your response"; then
        echo "blocked"
    elif echo "$lower" | grep -qE "(esc to cancel|working|thinking|processing|running|loading)"; then
        echo "working"
    elif echo "$content" | grep -qE "(^> |^[>] |^• |prompt|ready|idle|done)"; then
        echo "idle"
    else
        echo "unknown"
    fi
}

# Avoid duplicate monitors
lockfile="/tmp/herdr-traex-monitor-$pane_id.lock"
if [ -f "$lockfile" ]; then
    existing_pid=$(cat "$lockfile")
    if kill -0 "$existing_pid" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$lockfile"
trap 'rm -f "$lockfile"' EXIT HUP INT TERM

# Poll for state changes
last_state=""
while true; do
    state=$(detect_state)
    if [ "$state" != "$last_state" ] && [ "$state" != "unknown" ]; then
        herdr pane report-agent "$pane_id" \
          --source "herdr:traex-monitor" \
          --agent "traex" \
          --state "$state" 2>/dev/null || true
        last_state="$state"
    fi
    sleep 2
done
