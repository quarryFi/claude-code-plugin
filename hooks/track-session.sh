#!/usr/bin/env bash
# QuarryFi session tracking hook for Claude Code
#
# Reads ~/.quarryfi/config.json for credentials.
# Supports multi-profile (profiles array) and legacy single-key formats.
# Fires on: SessionStart, Stop, SessionEnd, PostToolUse, UserPromptSubmit,
#           SubagentStop — covering the full session lifecycle including
#           autonomous tool use and subagent work.
# Errors are silently ignored to never break the Claude Code session.

set -o pipefail

CONFIG_DIR="$HOME/.quarryfi"
CONFIG_FILE="$CONFIG_DIR/config.json"
AUDIT_LOG="$CONFIG_DIR/audit.log"
STATE_FILE="$CONFIG_DIR/.session_state"
AUDIT_MAX_BYTES=1048576  # 1 MB
DEFAULT_API_URL="https://quarryfi.smashedstudiosllc.workers.dev"

# --- Read hook event from stdin -------------------------------------------
EVENT_JSON=$(cat)

# --- Parse common event fields --------------------------------------------
HOOK_EVENT=$(printf '%s' "$EVENT_JSON" | grep -o '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null)
CWD=$(printf '%s' "$EVENT_JSON" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null)
SESSION_ID=$(printf '%s' "$EVENT_JSON" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//' 2>/dev/null)

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EPOCH=$(date +%s 2>/dev/null || echo 0)

# --- Derive project_name -------------------------------------------------
# Try git repo root name first, fall back to basename of cwd
if [ -n "$CWD" ] && [ -d "$CWD/.git" ]; then
  PROJECT_NAME=$(basename "$CWD")
elif [ -n "$CWD" ]; then
  GIT_TOPLEVEL=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$GIT_TOPLEVEL" ]; then
    PROJECT_NAME=$(basename "$GIT_TOPLEVEL")
  else
    PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "unknown")
  fi
else
  PROJECT_NAME="unknown"
fi

# --- Derive branch --------------------------------------------------------
BRANCH="unknown"
if [ -n "$CWD" ]; then
  BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
fi

# --- Derive language and file_type from tool context ----------------------
# PostToolUse events for Write/Edit/Read include tool_input.file_path
LANGUAGE="multi"
FILE_TYPE="multi"

FILE_PATH=$(printf '%s' "$EVENT_JSON" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' 2>/dev/null)

if [ -n "$FILE_PATH" ]; then
  # Extract extension
  EXT="${FILE_PATH##*.}"
  if [ -n "$EXT" ] && [ "$EXT" != "$FILE_PATH" ]; then
    FILE_TYPE=".${EXT}"
    # Map common extensions to language names
    case "$EXT" in
      js|mjs|cjs)       LANGUAGE="javascript" ;;
      ts|mts|cts)       LANGUAGE="typescript" ;;
      tsx)              LANGUAGE="typescriptreact" ;;
      jsx)              LANGUAGE="javascriptreact" ;;
      py|pyw)           LANGUAGE="python" ;;
      rb)               LANGUAGE="ruby" ;;
      rs)               LANGUAGE="rust" ;;
      go)               LANGUAGE="go" ;;
      java)             LANGUAGE="java" ;;
      kt|kts)           LANGUAGE="kotlin" ;;
      swift)            LANGUAGE="swift" ;;
      c|h)              LANGUAGE="c" ;;
      cpp|cc|cxx|hpp)   LANGUAGE="cpp" ;;
      cs)               LANGUAGE="csharp" ;;
      php)              LANGUAGE="php" ;;
      sh|bash|zsh)      LANGUAGE="shell" ;;
      json)             LANGUAGE="json" ;;
      yaml|yml)         LANGUAGE="yaml" ;;
      toml)             LANGUAGE="toml" ;;
      xml)              LANGUAGE="xml" ;;
      html|htm)         LANGUAGE="html" ;;
      css|scss|sass)    LANGUAGE="css" ;;
      sql)              LANGUAGE="sql" ;;
      md|markdown)      LANGUAGE="markdown" ;;
      r|R)              LANGUAGE="r" ;;
      lua)              LANGUAGE="lua" ;;
      ex|exs)           LANGUAGE="elixir" ;;
      erl)              LANGUAGE="erlang" ;;
      hs)               LANGUAGE="haskell" ;;
      scala)            LANGUAGE="scala" ;;
      clj|cljs)         LANGUAGE="clojure" ;;
      dart)             LANGUAGE="dart" ;;
      vue)              LANGUAGE="vue" ;;
      svelte)           LANGUAGE="svelte" ;;
      tf|hcl)           LANGUAGE="terraform" ;;
      Dockerfile)       LANGUAGE="docker" ;;
      *)                LANGUAGE="$EXT" ;;
    esac
  fi
fi

# --- Determine event type -------------------------------------------------
case "$HOOK_EVENT" in
  SessionStart)     EVENT_TYPE="session_start" ;;
  SessionEnd)       EVENT_TYPE="session_end" ;;
  Stop)             EVENT_TYPE="heartbeat" ;;
  PostToolUse)      EVENT_TYPE="heartbeat" ;;
  UserPromptSubmit) EVENT_TYPE="heartbeat" ;;
  SubagentStop)     EVENT_TYPE="heartbeat" ;;
  *)                EVENT_TYPE="heartbeat" ;;
esac

# --- Compute duration_seconds ---------------------------------------------
# Track last heartbeat time per session in a state file.
# duration_seconds = seconds since last heartbeat in this session.
DURATION_SECONDS=0
mkdir -p "$CONFIG_DIR" 2>/dev/null || true

if [ -n "$SESSION_ID" ] && [ -f "$STATE_FILE" ]; then
  LAST_ENTRY=$(grep "^${SESSION_ID} " "$STATE_FILE" 2>/dev/null | tail -1)
  if [ -n "$LAST_ENTRY" ]; then
    LAST_EPOCH=$(echo "$LAST_ENTRY" | awk '{print $2}')
    if [ -n "$LAST_EPOCH" ] && [ "$LAST_EPOCH" -gt 0 ] 2>/dev/null; then
      DURATION_SECONDS=$(( EPOCH - LAST_EPOCH ))
      # Clamp negative or absurdly large values
      if [ "$DURATION_SECONDS" -lt 0 ] 2>/dev/null; then
        DURATION_SECONDS=0
      elif [ "$DURATION_SECONDS" -gt 86400 ] 2>/dev/null; then
        DURATION_SECONDS=86400
      fi
    fi
  fi
fi

# Update state file with current timestamp
if [ -n "$SESSION_ID" ] && [ "$EPOCH" -gt 0 ] 2>/dev/null; then
  # Keep only current session's entry (overwrite, don't grow)
  if [ -f "$STATE_FILE" ]; then
    grep -v "^${SESSION_ID} " "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
    mv "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true
  fi
  echo "${SESSION_ID} ${EPOCH}" >> "$STATE_FILE" 2>/dev/null || true
  # Prune stale sessions (keep only last 20 entries)
  if [ -f "$STATE_FILE" ]; then
    tail -20 "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null && \
      mv "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true
  fi
fi

# On session end, clean up this session's state
if [ "$EVENT_TYPE" = "session_end" ] && [ -n "$SESSION_ID" ] && [ -f "$STATE_FILE" ]; then
  grep -v "^${SESSION_ID} " "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
  mv "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true
fi

# --- Audit log helper -----------------------------------------------------
audit_log() {
  local profile_name="$1" status="$2"
  {
    printf '{"timestamp":"%s","profile":"%s","project":"%s","event":"%s","branch":"%s","language":"%s","duration":%d,"status":"%s"}\n' \
      "$TIMESTAMP" "$profile_name" "$PROJECT_NAME" "$EVENT_TYPE" "$BRANCH" "$LANGUAGE" "$DURATION_SECONDS" "$status"
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
  api_url="${api_url:-$DEFAULT_API_URL}"

  local payload
  payload=$(cat <<PAYLOAD
{
  "heartbeats": [
    {
      "source": "claude_code",
      "project_name": "${PROJECT_NAME}",
      "language": "${LANGUAGE}",
      "file_type": "${FILE_TYPE}",
      "branch": "${BRANCH}",
      "editor": "Claude Code",
      "timestamp": "${TIMESTAMP}",
      "duration_seconds": ${DURATION_SECONDS},
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

# ==========================================================================
# Config file (~/.quarryfi/config.json)
# ==========================================================================
if [ ! -f "$CONFIG_FILE" ]; then
  exit 0
fi

CONFIG=$(cat "$CONFIG_FILE" 2>/dev/null) || exit 0

# --- Multi-profile config -------------------------------------------------
if printf '%s' "$CONFIG" | grep -q '"profiles"'; then

  profile_count=$(printf '%s' "$CONFIG" | grep -c '"name"' 2>/dev/null || echo 0)
  if [ "$profile_count" -eq 0 ]; then
    exit 0
  fi

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

    if [ "$matched" = true ]; then
      send_heartbeat "$p_key" "$p_url" "$p_name"
    fi

    i=$((i + 1))
  done

else
  # --- Legacy single-key config -------------------------------------------
  API_KEY=$(printf '%s' "$CONFIG" | grep -o '"api_key"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' 2>/dev/null) || exit 0
  API_URL=$(printf '%s' "$CONFIG" | grep -o '"api_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' 2>/dev/null) || true

  if [ -z "$API_KEY" ]; then
    exit 0
  fi

  send_heartbeat "$API_KEY" "$API_URL" "default"
fi

exit 0
