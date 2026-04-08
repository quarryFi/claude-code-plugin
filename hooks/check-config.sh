#!/usr/bin/env bash
# Checks if QuarryFi is configured. Runs synchronously on SessionStart.
# If no config exists, outputs a message that Claude will show to the user.

CONFIG_FILE="$HOME/.quarryfi/config.json"

# Also check plugin userConfig env var
if [ -n "${CLAUDE_PLUGIN_OPTION_api_key:-}" ]; then
  exit 0
fi

if [ ! -f "$CONFIG_FILE" ]; then
  cat <<'MSG'
⚠️ QuarryFi is not configured yet. To start tracking R&D time, run:

  bash "${CLAUDE_PLUGIN_ROOT}/setup.sh"

Or create ~/.quarryfi/config.json manually:

  {
    "api_key": "qf_your_key_here",
    "api_url": "https://quarryfi.smashedstudiosllc.workers.dev"
  }

Get your API key from: https://quarryfi.smashedstudiosllc.workers.dev/dashboard
MSG
  exit 0
fi

# Config exists — check it has a key
if grep -q '"api_key"' "$CONFIG_FILE" 2>/dev/null || grep -q '"profiles"' "$CONFIG_FILE" 2>/dev/null; then
  exit 0
fi

cat <<'MSG'
⚠️ QuarryFi config exists but has no API key. Run setup to fix:

  bash "${CLAUDE_PLUGIN_ROOT}/setup.sh"
MSG
exit 0
