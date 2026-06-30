#!/bin/bash
set -eo pipefail

echo "=== Installing Herdr TraeX Integration ==="

# Detect traex config dir
if [ -n "${TRAEX_CONFIG_DIR:-}" ]; then
    TRAEX_DIR="$TRAEX_CONFIG_DIR"
else
    TRAEX_DIR="$HOME/.trae"
fi

echo "Detected TraeX config dir: $TRAEX_DIR"

# Check if traex is installed
if ! command -v traex >/dev/null 2>&1; then
    echo "❌ Error: traex command not found. Install TraeX first."
    exit 1
fi

# Check config dir exists
if [ ! -d "$TRAEX_DIR" ]; then
    echo "❌ Error: TraeX config directory not found at $TRAEX_DIR. Run traex once first to create it."
    exit 1
fi

# Create hooks dir if needed
HOOKS_DIR="$TRAEX_DIR/hooks"
mkdir -p "$HOOKS_DIR"

# Copy hook script
HOOK_PATH="$HOOKS_DIR/herdr-agent-state.sh"
# Use script location to find assets dir when not running via Herdr plugin
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSETS_DIR="${HERDR_PLUGIN_ROOT:-$SCRIPT_DIR/..}/assets"
cp "$ASSETS_DIR/herdr-agent-state.sh" "$HOOK_PATH"
chmod +x "$HOOK_PATH"
echo "✅ Copied hook script to $HOOK_PATH"

# Update traex settings
SETTINGS_PATH="$TRAEX_DIR/hooks.json"
if [ -f "$SETTINGS_PATH" ]; then
    SETTINGS=$(cat "$SETTINGS_PATH")
else
    SETTINGS="{}"
fi

# Ensure hooks object exists
if ! echo "$SETTINGS" | jq -e '.hooks' >/dev/null 2>&1; then
    SETTINGS=$(echo "$SETTINGS" | jq '.hooks = {}')
fi

# Function to add a hook
add_hook() {
    local event="$1"
    local state="$2"
    local command="bash \"$HOOK_PATH\" $state"

    # Check if hook already exists
    existing=$(echo "$SETTINGS" | jq -r --arg event "$event" --arg cmd "$command" '
        .hooks[$event] // [] | .[] | .hooks[]? | select(.command == $cmd)
    ')
    if [ -n "$existing" ]; then
        echo "ℹ️  Hook for $event already exists, skipping"
        return
    fi

    # Add the hook
    SETTINGS=$(echo "$SETTINGS" | jq --arg event "$event" --arg cmd "$command" '
        .hooks[$event] += [{
            "matcher": "*",
            "hooks": [{
                "type": "command",
                "command": $cmd,
                "timeout": 30
            }]
        }]
    ')
    echo "✅ Added hook for $event → $state"
}

# Add hooks for traex lifecycle events
add_hook "SessionStart" "idle"
add_hook "UserPromptSubmit" "working"
add_hook "PreToolUse" "working"
add_hook "PostToolUse" "idle"
add_hook "PostToolUseFailure" "idle"
add_hook "PermissionRequest" "blocked"
add_hook "Stop" "idle"
add_hook "SessionEnd" "release"

# Write updated settings
echo "$SETTINGS" | jq '.' > "$SETTINGS_PATH"
echo "✅ Updated TraeX settings at $SETTINGS_PATH"

# Ensure hooks are enabled in traecli.toml
CONFIG_PATH="$TRAEX_DIR/traecli.toml"
if [ -f "$CONFIG_PATH" ]; then
    if ! grep -q 'hooks = true' "$CONFIG_PATH" 2>/dev/null; then
        # Add hooks feature flag
        if grep -q "\[features\]" "$CONFIG_PATH"; then
            # Add after [features] section
            sed -i '' '/^\[features\]/a\
hooks = true\
' "$CONFIG_PATH"
        else
            # Add [features] section
            echo "" >> "$CONFIG_PATH"
            echo "[features]" >> "$CONFIG_PATH"
            echo "hooks = true" >> "$CONFIG_PATH"
        fi
        echo "✅ Enabled hooks feature in $CONFIG_PATH"
    else
        echo "ℹ️  Hooks feature already enabled"
    fi
fi

echo ""
echo "🎉 Herdr TraeX integration installed successfully!"
echo ""
echo "To uninstall later, run:"
echo "  herdr plugin action invoke com.traex.herdr-integration.uninstall"
echo ""
echo "TraeX state will now automatically appear in Herdr's sidebar."
