# Herdr TraeX Integration Plugin

A standalone Herdr plugin that integrates the TraeX coding agent with Herdr, no changes to Herdr core required.

## Features

✅ **Automatic state reporting**: TraeX state (idle/working/blocked) appears in Herdr's sidebar
✅ **Session restore support**: Herdr can resume TraeX sessions when `resume_agents_on_restore = true`
✅ **No core changes**: Works entirely as a Herdr plugin, no PRs required
✅ **Hook-only integration**: Uses TraeX lifecycle hooks directly, with no background monitor that can leave stale state
✅ **Clean uninstall**: Removes only Herdr-owned hooks and scripts

## Install

### Prerequisites
- Herdr >= 0.7.0
- TraeX CLI installed
- TraeX config directory exists at `~/.trae` (run `traex` once if it doesn't)

### Install from GitHub
```bash
herdr plugin install Phoobobo/herdr-traex-integration
```

### Install locally
```bash
herdr plugin link /path/to/herdr-traex-integration
```

### Run the install action
```bash
herdr plugin action invoke com.traex.herdr-integration.install
```

## Uninstall

```bash
herdr plugin action invoke com.traex.herdr-integration.uninstall
herdr plugin uninstall com.traex.herdr-integration
```

## Requirements

- Herdr >= 0.7.0
- TraeX CLI installed
- TraeX config directory exists at `~/.trae` (run `traex` once if it doesn't)

## Troubleshooting

If state doesn't appear:
1. Ensure `HERDR_ENV=1` is set in your TraeX pane
2. Restart TraeX after installing the integration
3. Check that hooks are enabled in `~/.trae/traecli.toml` (`[features] hooks = true`)
4. Check that Herdr hook commands exist in `~/.trae/hooks.json`
5. Check the Herdr plugin logs: `herdr plugin log list --plugin com.traex.herdr-integration`

## How it works

The plugin installs a TraeX lifecycle hook into `~/.trae/hooks/herdr-agent-state.sh` and registers that hook in `~/.trae/hooks.json`.

The hook reports TraeX semantic state directly to Herdr through Herdr's local socket API:

- `SessionStart` → `idle`
- `UserPromptSubmit` → `working`
- `PreToolUse` → `working`
- `PostToolUse` / `PostToolUseFailure` → `idle`
- `PermissionRequest` → `blocked`
- `Notification` → `idle`
- `Stop` → `idle`
- `SessionEnd` → `release` so exited TraeX sessions are removed from Herdr's agents pane

The hook forwards TraeX `session_id` values to Herdr when TraeX includes them in hook payloads.

## License

MIT
