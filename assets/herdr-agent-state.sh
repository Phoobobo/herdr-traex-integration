#!/bin/sh
# installed by herdr traex integration plugin
# managed by herdr; reinstalling or updating the plugin overwrites this file.
# add custom hooks beside this file instead of editing it.
# HERDR_INTEGRATION_ID=traex
# HERDR_INTEGRATION_VERSION=4
#
# Reports traex agent state changes to herdr. Registered as a Command hook
# in ~/.trae/hooks.json by the herdr plugin install action and invoked by
# traex's hook system on lifecycle events.

set -eu

action="${1:-}"
hook_input_file="$(mktemp "${TMPDIR:-/tmp}/herdr-traex-hook.XXXXXX")" || exit 0
trap 'rm -f "$hook_input_file"' EXIT HUP INT TERM
cat >"$hook_input_file" 2>/dev/null || true

case "$action" in
  working|idle|blocked|release) ;;
  *) exit 0 ;;
esac

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

HERDR_ACTION="$action" HERDR_HOOK_INPUT_FILE="$hook_input_file" python3 - <<'PY'
import json
import os
import random
import socket
import time

source = "herdr:traex"
action = os.environ.get("HERDR_ACTION", "")
pane_id = os.environ.get("HERDR_PANE_ID")
socket_path = os.environ.get("HERDR_SOCKET_PATH")
hook_input_file = os.environ.get("HERDR_HOOK_INPUT_FILE")

if not pane_id or not socket_path:
    raise SystemExit(0)

hook_input = {}
if hook_input_file:
    try:
        with open(hook_input_file, encoding="utf-8") as handle:
            content = handle.read()
        if content.strip():
            hook_input = json.loads(content)
    except Exception:
        hook_input = {}

hook_event_name = str(hook_input.get("hook_event_name") or "")
is_subagent = bool(hook_input.get("agent_id"))
if hook_event_name == "SubagentStop":
    # Subagent completion must not make the parent pane look done/idle early.
    raise SystemExit(0)
if is_subagent and action in ("idle", "release"):
    raise SystemExit(0)

session_id = hook_input.get("session_id")
agent_session_id = session_id if isinstance(session_id, str) and session_id else None

request_id = f"{source}:{int(time.time() * 1000)}:{random.randrange(1_000_000):06d}"
report_seq = time.time_ns()
if action == "release":
    request = {
        "id": request_id,
        "method": "pane.release_agent",
        "params": {
            "pane_id": pane_id,
            "source": source,
            "agent": "traex",
            "seq": report_seq,
        },
    }
else:
    request = {
        "id": request_id,
        "method": "pane.report_agent",
        "params": {
            "pane_id": pane_id,
            "source": source,
            "agent": "traex",
            "state": action,
            "seq": report_seq,
        },
    }
    if agent_session_id:
        request["params"]["agent_session_id"] = agent_session_id

try:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    client.connect(socket_path)
    client.sendall((json.dumps(request) + "\n").encode())
    try:
        client.recv(4096)
    except Exception:
        pass
    client.close()
except Exception:
    pass
PY
