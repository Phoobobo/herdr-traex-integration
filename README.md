# Herdr TraeX Integration Plugin

A standalone Herdr plugin that integrates the TraeX coding agent with Herdr, no changes to Herdr core required.

## Features

✅ **Automatic state reporting**: TraeX state (idle/working/blocked) appears in Herdr's sidebar
✅ **Session restore support**: Herdr can resume TraeX sessions when `resume_agents_on_restore = true`
✅ **No core changes**: Works entirely as a Herdr plugin, no PRs required
✅ **Fallback monitor**: Detects TraeX state from terminal output if hook support is unavailable
✅ **Clean uninstall**: Removes only Herdr-owned hooks and scripts

## Install

### Prerequisites
- Herdr >= 0.7.0
- TraeX CLI installed
- TraeX config directory exists at `~/.trae` (run `traex` once if it doesn't)

### Install from GitHub (once published)
```bash
herdr plugin install <your-github-username>/herdr-traex-integration
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
1. Ensure `HERDR_ENV=1` is set in your shell
2. Restart TraeX after installing the integration
3. Check that hooks are enabled in `~/.trae/traecli.toml` (`[features] hooks = true`)
4. Check the Herdr plugin logs: `herdr plugin log list --plugin com.traex.herdr-integration`

## How it works

The plugin uses three components:

1. **TraeX lifecycle hook**: Installed into `~/.trae/hooks/herdr-agent-state.sh`, this hook reports TraeX state directly to Herdr via the socket API.
2. **State monitor fallback**: If hook support is unavailable, a background process monitors TraeX terminal output to infer state.
3. **Session restore**: The hook forwards TraeX session IDs to Herdr, so sessions can be resumed automatically across Herdr restarts when enabled.

## License

MIT

