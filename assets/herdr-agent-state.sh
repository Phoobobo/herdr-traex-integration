#!/bin/sh
# installed by herdr traex integration plugin
# managed by herdr; reinstalling or updating the plugin overwrites this file.
# add custom hooks beside this file instead of editing it.
# HERDR_INTEGRATION_ID=traex
# HERDR_INTEGRATION_VERSION=2
#
# Reports traex agent state changes to herdr. Registered as a Command hook
# in ~/.traex/settings.json by the herdr plugin install action and
# invoked by traex's hook system on lifecycle events.

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
import subprocess

source = "herdr:traex"
action = os.environ.get("HERDR_ACTION", "")
pane_id = os.environ.get("HERDR_PANE_ID")
socket_path = os.environ.get("HERDR_SOCKET_PATH")
hook_input_file = os.environ.get("HERDR_HOOK_INPUT_FILE")
herdr_bin = os.environ.get("HERDR_BIN_PATH", "herdr")

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

# Ignore subagent completion events
is_subagent = bool(hook_input.get("agent_id"))
hook_event_name = str(hook_input.get("hook_event_name") or "")
if hook_event_name == "SubagentStop" or (is_subagent and action in ("idle", "release")):
    raise SystemExit(0)

# Extract session id if present
session_id = hook_input.get("session_id")
agent_session_id = session_id if isinstance(session_id, str) and session_id else None

# Prefer CLI for portability
try:
    if action == "release":
        # Send idle first to ensure state updates before release
        idle_cmd = [herdr_bin, "pane", "report-agent", pane_id, "--source", source, "--agent", "traex", "--state", "idle"]
        subprocess.run(idle_cmd, capture_output=True, timeout=1, check=False)

        cmd = [herdr_bin, "pane", "release-agent", pane_id, "--source", source, "--agent", "traex"]
        subprocess.run(cmd, capture_output=True, timeout=1, check=False)
    else:
        # Always use direct socket API for more reliable state reporting
        request_id = f"{source}:{int(time.time() * 1000)}:{random.randrange(1_000_000):06d}"
        report_seq = time.time_ns()
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
    # Fallback to CLI if socket fails
    try:
        if action != "release":
            cmd = [herdr_bin, "pane", "report-agent", pane_id, "--source", source, "--agent", "traex", "--state", action]
            subprocess.run(cmd, capture_output=True, timeout=1, check=False)
    except Exception:
        pass
PY
