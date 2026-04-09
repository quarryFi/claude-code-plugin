#!/usr/bin/env bash
# Checks if QuarryFi is configured. Runs synchronously on SessionStart.
# If no config exists, outputs a message that Claude will show to the user.

CONFIG_FILE="$HOME/.quarryfi/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  cat <<'MSG'
QuarryFi R&D tracking is not configured yet.

To set up, run:  /quarryfi-tracker:configure

Or create ~/.quarryfi/config.json manually:

  {
    "profiles": [
      {
        "name": "My Company",
        "api_key": "qf_your_key_here",
        "api_url": "https://quarryfi.smashedstudiosllc.workers.dev",
        "projects": ["/path/to/your/project"]
      }
    ]
  }

Get your API key: https://quarryfi.smashedstudiosllc.workers.dev/dashboard
MSG
  exit 0
fi

# Config exists — check it has credentials
if grep -q '"api_key"' "$CONFIG_FILE" 2>/dev/null || grep -q '"profiles"' "$CONFIG_FILE" 2>/dev/null; then
  exit 0
fi

cat <<'MSG'
QuarryFi config exists but has no API key. Run:  /quarryfi-tracker:configure
MSG
exit 0
