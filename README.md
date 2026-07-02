# Herdr TraeX Integration Plugin

A standalone [Herdr](https://herdr.dev) plugin that reports TraeX coding-agent
state to Herdr. It installs as a Herdr plugin — no changes to Herdr core, and no
PRs against Herdr required.

## Features

- **Automatic state reporting**: TraeX state (idle / working / blocked) appears
  in Herdr's sidebar and agents pane.
- **Minimal hook footprint**: 5 lifecycle hooks, one per user-visible state transition,
  plus a bounded per-turn watcher for TraeX question prompts that emit no hook.
- **No Herdr core changes**: ships entirely as a Herdr plugin.
- **Clean uninstall**: removes only the hooks and script this plugin owns.

## Why hooks (and not screen scraping)

Herdr derives agent state from three signals: process detection, integration
hook events, and screen heuristics. For its built-in agents (Claude, Codex,
etc.) Herdr can drop some hooks because its screen heuristics fill the gaps.

**TraeX is different: Herdr has no built-in detector for it** — `traex` is not
in Herdr's agent table, so `process detection` and `screen heuristics` both
return "unknown" and report no visible state. That means these hooks are the
*only* source of truth for a TraeX pane. Every state transition we care about
must be reported by a hook, and we must never emit an `idle` that Herdr cannot
later correct from the screen (because it can't).

That constraint drives the mapping below: it mirrors Herdr's own `claude`/
`codex` integrations, minus the events that would produce a spurious `idle`.

One TraeX UI state is not emitted as a hook: `AskUserQuestion` displays an
interactive question modal and blocks waiting for the user, but TraeX fires no
`PreToolUse`, `PermissionRequest`, or `Notification` while the modal is visible.
To cover that gap without a long-lived monitor, the `UserPromptSubmit` hook
starts a bounded watcher that reads the visible Herdr pane for the question
modal and reports `blocked` only when the modal is actually present.

## Requirements

- Herdr >= 0.7.0 (the plugin system was introduced in 0.7.0)
- TraeX CLI installed and on `PATH`
- A TraeX config directory at `~/.trae` (run `traex` once if it doesn't exist)
- `jq` on `PATH` (the install/uninstall scripts use it to edit `hooks.json`)

## Install

Install from GitHub, then run the install action to wire up the hooks:

```bash
herdr plugin install Phoobobo/herdr-traex-integration
herdr plugin action invoke com.traex.herdr-integration.install
```

`herdr plugin install` registers the plugin under Herdr-managed plugin data.
The `install` action then copies the hook scripts into `~/.trae/hooks/` and
registers the lifecycle hook in `~/.trae/hooks.json`. Restart any running TraeX
session so it picks up the new hooks.

### Local development

When working on the plugin, link the working directory instead of installing
from GitHub:

```bash
herdr plugin link /path/to/herdr-traex-integration
herdr plugin action list --plugin com.traex.herdr-integration
herdr plugin action invoke com.traex.herdr-integration.install
```

## Uninstall

```bash
herdr plugin action invoke com.traex.herdr-integration.uninstall
herdr plugin uninstall com.traex.herdr-integration
```

The `uninstall` action removes the hook scripts and this plugin's entries from
`~/.trae/hooks.json` (it leaves the `[features] hooks = true` flag alone, since
other tools may rely on it). `herdr plugin uninstall` then unregisters the
plugin and removes the managed checkout.

## How it works

The install action writes `~/.trae/hooks/herdr-agent-state.sh` and
`~/.trae/hooks/herdr-question-watch.sh`, then registers the lifecycle hook in
`~/.trae/hooks.json`. On each TraeX lifecycle event the hook reports semantic
state to Herdr over its local socket (`pane.report_agent` / `pane.release_agent`,
using `HERDR_SOCKET_PATH` and `HERDR_PANE_ID` injected into every Herdr pane).

Registered hooks:

| TraeX event        | Reported state | Why |
| ------------------ | -------------- | --- |
| `SessionStart`     | `idle`         | agent ready, prompt visible |
| `UserPromptSubmit` | `working`      | user handed the agent a task |
| `PermissionRequest`| `blocked`      | waiting on the human |
| `Stop`             | `idle`         | turn finished, prompt visible again |
| `SessionEnd`       | `release`      | drop authority so exited panes disappear |

**Deliberately not hooked:**

- `PreToolUse`, `PostToolUse`, and `PostToolUseFailure` are omitted: a submitted
  turn is already `working`, a completed tool call does not end the turn, and
  `Stop` still fires when the turn actually ends.
- `Notification` is omitted: it's ambiguous and can fire while the pane is
  genuinely `blocked`, where reporting `idle` would be wrong.
- `SubagentStop` is ignored inside the hook script so a subagent finishing can
  never make the parent pane look done early.

Note: if a TraeX permission prompt reports `PermissionRequest` and then TraeX
does not emit another lifecycle event after approval, Herdr may keep showing
`blocked` until the turn's `Stop` hook fires. That avoids adding tool hooks that
otherwise do not affect the visible state for normal turns.

### AskUserQuestion watcher

`AskUserQuestion` is special: live testing showed that TraeX fires no hook while
the question modal is blocking. The `UserPromptSubmit` hook therefore starts
`herdr-question-watch.sh`, a short-lived watcher that:

- runs only inside Herdr panes,
- holds a per-pane lock so duplicate watchers do not pile up,
- reads the visible pane through `herdr pane read`,
- matches the question UI (`Question ... unanswered`,
  `enter to submit answer`, `esc to interrupt`),
- reports `blocked` from source `herdr:traex-question` with custom status
  `awaiting answer`,
- exits after it reports or after `HERDR_TRAEX_QUESTION_WATCH_SECONDS` seconds
  (default: 90).

The watcher never reports `idle` or `working`; normal lifecycle hooks still own
those transitions. When the user answers the question, TraeX fires `Stop` and
the main hook returns the pane to `idle`.

### Session id forwarding

The hook forwards TraeX's `session_id` to Herdr when TraeX includes one in the
hook payload. Note that Herdr's **native session resume**
(`resume_agents_on_restore`) is currently limited to agents Herdr recognizes as
official sources (Claude, Codex, Pi, OpenCode, Hermes, …); TraeX is not on that
list yet, so Herdr does not auto-resume TraeX panes today. The forwarded id is
harmless and positions the plugin for resume support if Herdr adds TraeX.

## Troubleshooting

If state doesn't appear in Herdr:

1. Confirm the pane is a Herdr pane: `HERDR_ENV=1` should be set in it.
2. Restart TraeX after installing so it reloads `hooks.json`.
3. Check hooks are enabled in `~/.trae/traecli.toml` (`[features] hooks = true`).
4. Check the Herdr hook is registered in `~/.trae/hooks.json`.
5. Inspect the plugin logs: `herdr plugin log list --plugin com.traex.herdr-integration`

## License

MIT
