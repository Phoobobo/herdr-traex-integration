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

# Copy hook scripts
HOOK_PATH="$HOOKS_DIR/herdr-agent-state.sh"
QUESTION_WATCH_PATH="$HOOKS_DIR/herdr-question-watch.sh"
# Use script location to find assets dir when not running via Herdr plugin
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSETS_DIR="${HERDR_PLUGIN_ROOT:-$SCRIPT_DIR/..}/assets"
cp "$ASSETS_DIR/herdr-agent-state.sh" "$HOOK_PATH"
chmod +x "$HOOK_PATH"
echo "✅ Copied hook script to $HOOK_PATH"
cp "$ASSETS_DIR/herdr-question-watch.sh" "$QUESTION_WATCH_PATH"
chmod +x "$QUESTION_WATCH_PATH"
echo "✅ Copied question watcher to $QUESTION_WATCH_PATH"

# Update traex settings
SETTINGS_PATH="$TRAEX_DIR/hooks.json"
if [ -f "$SETTINGS_PATH" ]; then
    SETTINGS=$(cat "$SETTINGS_PATH")
else
    SETTINGS='{"version":1}'
fi

# Ensure hooks object exists
if ! echo "$SETTINGS" | jq -e '.hooks' >/dev/null 2>&1; then
    SETTINGS=$(echo "$SETTINGS" | jq '.hooks = {}')
fi

# Remove old Herdr entries before adding the current mapping so upgrades can
# change state mappings without leaving stale commands behind.
remove_herdr_hooks() {
    local event="$1"
    SETTINGS=$(echo "$SETTINGS" | jq --arg event "$event" --arg hook_path "$HOOK_PATH" '
        if .hooks[$event] then
            .hooks[$event] |= map(
                .hooks |= map(select((.command // "") | contains($hook_path) | not))
                | select(.hooks | length > 0)
            )
        else
            .
        end
    ')
}

for event in SessionStart UserPromptSubmit PreToolUse PostToolUse PostToolUseFailure PermissionRequest Notification Stop SessionEnd; do
    remove_herdr_hooks "$event"
done

# Function to add a hook
add_hook() {
    local event="$1"
    local state="$2"
    local command="bash \"$HOOK_PATH\" $state"

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

# Minimal TraeX lifecycle hook set, mirroring Herdr's built-in claude/codex
# integrations. Herdr has no screen-based detector for TraeX (traex is not in
# Herdr's Agent enum), so these hooks are the *only* source of state: every
# transition we care about must be reported by a hook, and none of them may be
# a spurious idle that Herdr cannot correct from the screen.
#
#   SessionStart      -> idle     agent ready, prompt visible
#   UserPromptSubmit  -> working  user handed a task to the agent
#   PreToolUse        -> working  keep working across a tool call...
#   PostToolUse       -> working  ...and stay working after it (NOT idle: the
#                                 agent is still mid-turn between tools; this
#                                 also clears a stale "blocked" after a grant)
#   PermissionRequest -> blocked  waiting on the human
#   Stop              -> idle     turn finished, prompt visible again
#   SessionEnd        -> release  drop authority so exited panes disappear
#
# PostToolUseFailure and Notification are intentionally omitted: a tool failure
# does not end the turn (Stop still fires), and Notification is ambiguous
# (it can arrive while the pane is genuinely blocked, so idle would be wrong).
add_hook "SessionStart" "idle"
add_hook "UserPromptSubmit" "working"
add_hook "PreToolUse" "working"
add_hook "PostToolUse" "working"
add_hook "PermissionRequest" "blocked"
add_hook "Stop" "idle"
add_hook "SessionEnd" "release"

# Remove empty event entries left by old hook cleanup.
SETTINGS=$(echo "$SETTINGS" | jq '.hooks |= with_entries(select(.value | length > 0))')

# Write updated settings
echo "$SETTINGS" | jq '.' > "$SETTINGS_PATH"
echo "✅ Updated TraeX settings at $SETTINGS_PATH"

# Ensure hooks are enabled in traecli.toml
CONFIG_PATH="$TRAEX_DIR/traecli.toml"
if [ -f "$CONFIG_PATH" ]; then
    if ! grep -q 'hooks = true' "$CONFIG_PATH" 2>/dev/null; then
        # Add hooks feature flag
        if grep -q "\[features\]" "$CONFIG_PATH"; then
            # Add after [features] section. BSD sed (macOS) requires this form.
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
