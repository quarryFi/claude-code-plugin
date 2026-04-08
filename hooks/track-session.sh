#!/usr/bin/env bash
# QuarryFi session tracking hook for Claude Code
# Supports multi-profile configs with project-to-key routing.
# Falls back to legacy single-key config for backward compatibility.
# Errors are silently ignored to never break the Claude Code session.

set -o pipefail

CONFIG_DIR="$HOME/.quarryfi"
CONFIG_FILE="$CONFIG_DIR/config.json"
AUDIT_LOG="$CONFIG_DIR/audit.log"
AUDIT_MAX_BYTES=1048576  # 1 MB

# --- Read hook event from stdin -------------------------------------------
EVENT_JSON=$(cat)

# --- Bail if no config ----------------------------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
  exit 0
fi

CONFIG=$(cat "$CONFIG_FILE" 2>/dev/null) || exit 0

# --- Parse event fields ---------------------------------------------------
HOOK_EVENT=$(printf '%s' "$EVENT_JSON" | grep -o '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null)
CWD=$(printf '%s' "$EVENT_JSON" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null)
SESSION_ID=$(printf '%s' "$EVENT_JSON" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null)

PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Determine event type -------------------------------------------------
case "$HOOK_EVENT" in
  SessionStart) EVENT_TYPE="session_start" ;;
  Stop)         EVENT_TYPE="heartbeat" ;;
  SessionEnd)   EVENT_TYPE="session_end" ;;
  *)            EVENT_TYPE="heartbeat" ;;
esac

# --- Audit log helper -----------------------------------------------------
audit_log() {
  local profile_name="$1" status="$2"
  {
    printf '{"timestamp":"%s","profile":"%s","project":"%s","event":"%s","status":"%s"}\n' \
      "$TIMESTAMP" "$profile_name" "$PROJECT_NAME" "$EVENT_TYPE" "$status"
  } >> "$AUDIT_LOG" 2>/dev/null || true

  # Truncate oldest half if over 1 MB
  if [ -f "$AUDIT_LOG" ]; then
    local size
    size=$(wc -c < "$AUDIT_LOG" 2>/dev/null || echo 0)
    if [ "$size" -gt "$AUDIT_MAX_BYTES" ] 2>/dev/null; then
      local total_lines half
      total_lines=$(wc -l < "$AUDIT_LOG" 2>/dev/null || echo 0)
      half=$(( total_lines / 2 ))
      if [ "$half" -gt 0 ]; then
        tail -n +"$((half + 1))" "$AUDIT_LOG" > "$AUDIT_LOG.tmp" 2>/dev/null && \
          mv "$AUDIT_LOG.tmp" "$AUDIT_LOG" 2>/dev/null || rm -f "$AUDIT_LOG.tmp" 2>/dev/null
      fi
    fi
  fi
}

# --- Send heartbeat to a single profile -----------------------------------
send_heartbeat() {
  local api_key="$1" api_url="$2" profile_name="$3"

  if [ -z "$api_key" ]; then
    return
  fi
  api_url="${api_url:-https://quarryfi.smashedstudiosllc.workers.dev}"

  local payload
  payload=$(cat <<PAYLOAD
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
PAYLOAD
)

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 5 \
    -X POST \
    -H "Authorization: Bearer ${api_key}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${api_url}/api/heartbeat" 2>/dev/null || echo "000")

  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
    audit_log "$profile_name" "sent"
  else
    audit_log "$profile_name" "error:${http_code}"
  fi
}

# --- Detect config format and route ---------------------------------------

# Check if this is a multi-profile config (has "profiles" key)
if printf '%s' "$CONFIG" | grep -q '"profiles"'; then
  # ---- Multi-profile mode ------------------------------------------------
  # Extract profile blocks using awk. Each profile needs: name, api_key, api_url, projects[].
  # We use a simple line-by-line state machine since we can't rely on jq.

  SENT_ANY=false

  # Parse profiles as delimited blocks between { and } inside the profiles array.
  # Strategy: extract each profile object, check if CWD matches any project prefix.
  profile_count=$(printf '%s' "$CONFIG" | grep -c '"name"' 2>/dev/null || echo 0)

  if [ "$profile_count" -eq 0 ]; then
    exit 0
  fi

  # Use awk to extract profile fields in order
  eval "$(printf '%s' "$CONFIG" | awk '
    BEGIN { idx=0; in_profiles=0; in_profile=0; in_projects=0 }
    /"profiles"/ { in_profiles=1; next }
    in_profiles && /\{/ && !in_profile { in_profile=1; next }
    in_profile && /"name"/ {
      gsub(/.*"name"[[:space:]]*:[[:space:]]*"/, ""); gsub(/".*/, "");
      printf "PROFILE_%d_NAME=\"%s\"\n", idx, $0
    }
    in_profile && /"api_key"/ {
      gsub(/.*"api_key"[[:space:]]*:[[:space:]]*"/, ""); gsub(/".*/, "");
      printf "PROFILE_%d_KEY=\"%s\"\n", idx, $0
    }
    in_profile && /"api_url"/ {
      gsub(/.*"api_url"[[:space:]]*:[[:space:]]*"/, ""); gsub(/".*/, "");
      printf "PROFILE_%d_URL=\"%s\"\n", idx, $0
    }
    in_profile && /"projects"/ { in_projects=1; printf "PROFILE_%d_PROJECTS=\"", idx; next }
    in_projects && /\]/ {
      in_projects=0; printf "\"\n"
    }
    in_projects && /"/ {
      gsub(/.*"/, ""); gsub(/".*/, "");
      printf "%s|", $0
    }
    in_profile && /\}/ && !in_projects {
      in_profile=0; idx++
    }
    END { printf "PROFILE_COUNT=%d\n", idx }
  ' 2>/dev/null)"

  # Iterate over parsed profiles
  i=0
  while [ "$i" -lt "${PROFILE_COUNT:-0}" ]; do
    eval "p_name=\${PROFILE_${i}_NAME:-}"
    eval "p_key=\${PROFILE_${i}_KEY:-}"
    eval "p_url=\${PROFILE_${i}_URL:-}"
    eval "p_projects=\${PROFILE_${i}_PROJECTS:-}"

    if [ -z "$p_key" ]; then
      i=$((i + 1))
      continue
    fi

    # Check if CWD matches any project prefix in this profile
    matched=false
    if [ -n "$p_projects" ]; then
      IFS='|' read -ra proj_list <<< "$p_projects"
      for proj in "${proj_list[@]}"; do
        proj=$(printf '%s' "$proj" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$proj" ] && [[ "$CWD" == "$proj"* ]]; then
          matched=true
          break
        fi
      done
    fi
    # No projects listed and no match — skip (explicit opt-in required)

    if [ "$matched" = true ]; then
      send_heartbeat "$p_key" "$p_url" "$p_name"
      SENT_ANY=true
    fi

    i=$((i + 1))
  done

else
  # ---- Legacy single-key mode (backward compatibility) -------------------
  API_KEY=$(printf '%s' "$CONFIG" | grep -o '"api_key"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' 2>/dev/null) || exit 0
  API_URL=$(printf '%s' "$CONFIG" | grep -o '"api_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' 2>/dev/null) || true

  if [ -z "$API_KEY" ]; then
    exit 0
  fi

  # Legacy mode: no project filter, send everything (matches original behavior)
  send_heartbeat "$API_KEY" "$API_URL" "default"
fi

exit 0
