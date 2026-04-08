#!/usr/bin/env bash
# QuarryFi session tracking hook for Claude Code
# Receives hook event JSON on stdin, sends heartbeats to the QuarryFi API.
# Errors are silently ignored to never break the Claude Code session.

set -o pipefail

CONFIG_FILE="$HOME/.quarryfi/config.json"

# --- Read hook event from stdin -------------------------------------------
EVENT_JSON=$(cat)

# --- Load config ----------------------------------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
  exit 0
fi

API_KEY=$(printf '%s' "$EVENT_JSON" | cat "$CONFIG_FILE" | grep -o '"api_key"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' 2>/dev/null) || exit 0
API_URL=$(cat "$CONFIG_FILE" | grep -o '"api_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' 2>/dev/null) || exit 0

if [ -z "$API_KEY" ]; then
  exit 0
fi

# Default API URL
API_URL="${API_URL:-https://quarryfi.smashedstudiosllc.workers.dev}"

# --- Parse event fields ---------------------------------------------------
HOOK_EVENT=$(printf '%s' "$EVENT_JSON" | grep -o '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null)
CWD=$(printf '%s' "$EVENT_JSON" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null)
SESSION_ID=$(printf '%s' "$EVENT_JSON" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null)

# Derive project name from working directory
PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "unknown")

# Current timestamp in ISO 8601
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Determine event type for heartbeat ----------------------------------
case "$HOOK_EVENT" in
  SessionStart)
    EVENT_TYPE="session_start"
    ;;
  Stop)
    EVENT_TYPE="heartbeat"
    ;;
  SessionEnd)
    EVENT_TYPE="session_end"
    ;;
  *)
    EVENT_TYPE="heartbeat"
    ;;
esac

# --- Build heartbeat payload ----------------------------------------------
PAYLOAD=$(cat <<EOF
{
  "heartbeats": [
    {
      "source": "claude_code",
      "project_name": "${PROJECT_NAME}",
      "editor": "Claude Code",
      "timestamp": "${TIMESTAMP}",
      "session_id": "${SESSION_ID}",
      "event_type": "${EVENT_TYPE}"
    }
  ]
}
EOF
)

# --- Send heartbeat -------------------------------------------------------
curl -s -o /dev/null \
  --max-time 5 \
  -X POST \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "${API_URL}/api/heartbeat" 2>/dev/null || true

exit 0
