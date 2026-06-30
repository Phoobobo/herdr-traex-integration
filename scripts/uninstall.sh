#!/bin/bash
set -eo pipefail

echo "=== Uninstalling Herdr TraeX Integration ==="

# Detect traex config dir
if [ -n "${TRAEX_CONFIG_DIR:-}" ]; then
    TRAEX_DIR="$TRAEX_CONFIG_DIR"
else
    TRAEX_DIR="$HOME/.trae"
fi

echo "Detected TraeX config dir: $TRAEX_DIR"

# Check config dir exists
if [ ! -d "$TRAEX_DIR" ]; then
    echo "ℹ️  TraeX config directory not found at $TRAEX_DIR, nothing to uninstall"
    exit 0
fi

# Remove hook script
HOOK_PATH="$TRAEX_DIR/hooks/herdr-agent-state.sh"
if [ -f "$HOOK_PATH" ]; then
    rm "$HOOK_PATH"
    echo "✅ Removed hook script at $HOOK_PATH"
else
    echo "ℹ️  No hook script found at $HOOK_PATH"
fi

# Update traex settings to remove Herdr hooks
SETTINGS_PATH="$TRAEX_DIR/hooks.json"
if [ -f "$SETTINGS_PATH" ]; then
    SETTINGS=$(cat "$SETTINGS_PATH")
    quoted_hook_path=$(printf '%s' "$HOOK_PATH" | sed 's/"/\\"/g')
    command_prefix="bash \"$quoted_hook_path\""

    # Function to remove Herdr hooks from an event
    remove_hooks() {
        local event="$1"
        # Filter out entries that contain the Herdr hook command
        SETTINGS=$(echo "$SETTINGS" | jq --arg event "$event" --arg cmd_prefix "$command_prefix" '
            if .hooks[$event] then
                .hooks[$event] |= map(
                    .hooks |= map(
                        select(.command | startswith($cmd_prefix) | not)
                    ) | select(.hooks | length > 0)
                )
            else
                .
            end
        ')
    }

    # Remove all Herdr hooks
    remove_hooks "SessionStart"
    remove_hooks "UserPromptSubmit"
    remove_hooks "PreToolUse"
    remove_hooks "PermissionRequest"
    remove_hooks "Stop"
    remove_hooks "SessionEnd"

    # Remove empty event entries
    SETTINGS=$(echo "$SETTINGS" | jq '
        .hooks |= with_entries(select(.value | length > 0))
    ')

    # Remove empty hooks object if needed
    if echo "$SETTINGS" | jq -e '.hooks == {}' >/dev/null 2>&1; then
        SETTINGS=$(echo "$SETTINGS" | jq 'del(.hooks)')
    fi

    # Write updated settings
    echo "$SETTINGS" | jq '.' > "$SETTINGS_PATH"
    echo "✅ Removed Herdr hooks from $SETTINGS_PATH"
else
    echo "ℹ️  No settings file found at $SETTINGS_PATH"
fi

# Note: leave hooks feature flag enabled in traecli.toml as other plugins may use it

echo ""
echo "✅ Herdr TraeX integration uninstalled successfully!"
