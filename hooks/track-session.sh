#!/usr/bin/env bash
# QuarryFi session tracking hook for Claude Code
#
# Accuracy-first design:
# - Event hooks still flush immediately on session activity
# - A background timer sends active-session heartbeats every 60s
# - Both flows share one "last sent" clock so time is never double-counted
# - Errors are always silenced so tracking never breaks Claude Code

set -o pipefail

CONFIG_DIR="$HOME/.quarryfi"
CONFIG_FILE="$CONFIG_DIR/config.json"
AUDIT_LOG="$CONFIG_DIR/audit.log"
AUDIT_MAX_BYTES=1048576
DEFAULT_API_URL="https://quarryfi.smashedstudiosllc.workers.dev"
HEARTBEAT_INTERVAL_SECONDS=60
MIN_TICK_DURATION_SECONDS=45

CLI_MODE="${1:-}"
CLI_CWD="${2:-}"
CLI_SESSION_ID="${3:-}"
EVENT_JSON=$(cat 2>/dev/null || true)
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" 2>/dev/null && pwd)
PLUGIN_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd)
PLUGIN_MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"
HOOK_MODE="event_plus_timer"

json_string() {
  printf '%s' "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/'
}

HOOK_EVENT=$(json_string "$EVENT_JSON" "hook_event_name")
EVENT_CWD_FROM_JSON=$(json_string "$EVENT_JSON" "cwd")
EVENT_SESSION_ID_FROM_JSON=$(json_string "$EVENT_JSON" "session_id")
EVENT_FILE_PATH_FROM_JSON=$(json_string "$EVENT_JSON" "file_path")

get_plugin_version() {
  if [ -f "$PLUGIN_MANIFEST" ]; then
    grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_MANIFEST" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/'
    return
  fi
  echo "unknown"
}

get_runtime_channel() {
  case "$PLUGIN_ROOT" in
    *"/.claude/plugins/cache/"*) echo "claude_plugin_cache" ;;
    *"/.claude/plugins/marketplaces/"*) echo "claude_plugin_marketplace" ;;
    *) echo "claude_plugin_custom" ;;
  esac
}

get_install_revision() {
  if [ -f "$SCRIPT_PATH" ]; then
    shasum -a 256 "$SCRIPT_PATH" 2>/dev/null | cut -c1-12
    return
  fi
  if [ -f "$PLUGIN_MANIFEST" ]; then
    shasum -a 256 "$PLUGIN_MANIFEST" 2>/dev/null | cut -c1-12
    return
  fi
  echo "unknown"
}

get_cwd() {
  if [ -n "$CLI_CWD" ]; then
    echo "$CLI_CWD"
    return
  fi
  if [ -n "$EVENT_CWD_FROM_JSON" ]; then
    echo "$EVENT_CWD_FROM_JSON"
    return
  fi
  pwd 2>/dev/null || echo ""
}

session_dir() {
  local cwd="$1"
  local hash
  hash=$(printf '%s' "$cwd" | shasum -a 256 2>/dev/null | cut -c1-12)
  echo "$CONFIG_DIR/session-claude-${hash}"
}

ensure_session_dir() {
  mkdir -p "$CONFIG_DIR" 2>/dev/null || true
  mkdir -p "$1" 2>/dev/null || true
}

session_file() {
  local cwd="$1"
  local name="$2"
  echo "$(session_dir "$cwd")/$name"
}

get_session_id() {
  local cwd="$1"
  local sid_file
  sid_file=$(session_file "$cwd" "session_id")

  if [ -n "$CLI_SESSION_ID" ]; then
    printf '%s' "$CLI_SESSION_ID" > "$sid_file" 2>/dev/null || true
    echo "$CLI_SESSION_ID"
    return
  fi
  if [ -n "$EVENT_SESSION_ID_FROM_JSON" ]; then
    printf '%s' "$EVENT_SESSION_ID_FROM_JSON" > "$sid_file" 2>/dev/null || true
    echo "$EVENT_SESSION_ID_FROM_JSON"
    return
  fi
  if [ -f "$sid_file" ]; then
    cat "$sid_file" 2>/dev/null
    return
  fi

  local new_id
  new_id="claude-$(date +%s)-${RANDOM:-0}"
  printf '%s' "$new_id" > "$sid_file" 2>/dev/null || true
  echo "$new_id"
}

persist_session_context() {
  local cwd="$1"
  local session_id="$2"
  printf '%s' "$cwd" > "$(session_file "$cwd" "cwd")" 2>/dev/null || true
  printf '%s' "$session_id" > "$(session_file "$cwd" "session_id")" 2>/dev/null || true
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

epoch_now() {
  date +%s 2>/dev/null || echo 0
}

clamp_duration() {
  local duration="$1"
  if [ "$duration" -lt 0 ] 2>/dev/null; then
    echo 0
  elif [ "$duration" -gt 86400 ] 2>/dev/null; then
    echo 86400
  else
    echo "$duration"
  fi
}

duration_since_last_sent() {
  local cwd="$1"
  local now_ts="$2"
  local last_file
  last_file=$(session_file "$cwd" "last_sent")

  if [ ! -f "$last_file" ]; then
    echo 0
    return
  fi

  local last_ts
  last_ts=$(cat "$last_file" 2>/dev/null)
  if [ -z "$last_ts" ]; then
    echo 0
    return
  fi

  clamp_duration $(( now_ts - last_ts ))
}

record_last_sent() {
  local cwd="$1"
  local now_ts="$2"
  printf '%s' "$now_ts" > "$(session_file "$cwd" "last_sent")" 2>/dev/null || true
}

cleanup_session_state() {
  local cwd="$1"
  rm -f \
    "$(session_file "$cwd" "last_sent")" \
    "$(session_file "$cwd" "session_id")" \
    "$(session_file "$cwd" "cwd")" \
    "$(session_file "$cwd" "timer.pid")" 2>/dev/null || true
  rmdir "$(session_dir "$cwd")" 2>/dev/null || true
}

rotate_audit_log() {
  if [ -f "$AUDIT_LOG" ]; then
    local size
    size=$(wc -c < "$AUDIT_LOG" 2>/dev/null || echo 0)
    if [ "$size" -gt "$AUDIT_MAX_BYTES" ] 2>/dev/null; then
      local total_lines half
      total_lines=$(wc -l < "$AUDIT_LOG" 2>/dev/null || echo 0)
      half=$(( total_lines / 2 ))
      if [ "$half" -gt 0 ]; then
        tail -n +"$((half + 1))" "$AUDIT_LOG" > "$AUDIT_LOG.tmp" 2>/dev/null && \
          mv "$AUDIT_LOG.tmp" "$AUDIT_LOG" 2>/dev/null || \
          rm -f "$AUDIT_LOG.tmp" 2>/dev/null
      fi
    fi
  fi
}

audit_log() {
  local profile_name="$1"
  local status="$2"
  local project_name="$3"
  local event_type="$4"
  local branch="$5"
  local language="$6"
  local duration_seconds="$7"

  rotate_audit_log
  {
    printf '{"timestamp":"%s","profile":"%s","project":"%s","event":"%s","branch":"%s","language":"%s","duration":%s,"status":"%s"}\n' \
      "$(timestamp_utc)" "$profile_name" "$project_name" "$event_type" "$branch" "$language" "$duration_seconds" "$status"
  } >> "$AUDIT_LOG" 2>/dev/null || true
}

map_hook_event() {
  case "$1" in
    SessionStart) echo "session_start" ;;
    SessionEnd|Stop) echo "session_end" ;;
    *) echo "heartbeat" ;;
  esac
}

get_project_name() {
  local cwd="$1"
  if [ -n "$cwd" ] && [ -d "$cwd/.git" ]; then
    basename "$cwd"
    return
  fi

  local git_toplevel
  git_toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$git_toplevel" ]; then
    basename "$git_toplevel"
    return
  fi

  basename "$cwd" 2>/dev/null || echo "unknown"
}

get_branch() {
  local cwd="$1"
  git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
}

get_file_path() {
  if [ -n "$EVENT_FILE_PATH_FROM_JSON" ]; then
    echo "$EVENT_FILE_PATH_FROM_JSON"
    return
  fi
  echo ""
}

get_language_and_file_type() {
  local file_path="$1"
  local language="multi"
  local file_type="multi"

  if [ -n "$file_path" ]; then
    local ext
    ext="${file_path##*.}"
    if [ -n "$ext" ] && [ "$ext" != "$file_path" ]; then
      file_type=".${ext}"
      case "$ext" in
        js|mjs|cjs) language="javascript" ;;
        ts|mts|cts) language="typescript" ;;
        tsx) language="typescriptreact" ;;
        jsx) language="javascriptreact" ;;
        py|pyw) language="python" ;;
        rb) language="ruby" ;;
        rs) language="rust" ;;
        go) language="go" ;;
        java) language="java" ;;
        kt|kts) language="kotlin" ;;
        swift) language="swift" ;;
        c|h) language="c" ;;
        cpp|cc|cxx|hpp) language="cpp" ;;
        cs) language="csharp" ;;
        php) language="php" ;;
        sh|bash|zsh) language="shell" ;;
        json) language="json" ;;
        yaml|yml) language="yaml" ;;
        toml) language="toml" ;;
        xml) language="xml" ;;
        html|htm) language="html" ;;
        css|scss|sass) language="css" ;;
        sql) language="sql" ;;
        md|markdown) language="markdown" ;;
        r|R) language="r" ;;
        lua) language="lua" ;;
        ex|exs) language="elixir" ;;
        erl) language="erlang" ;;
        hs) language="haskell" ;;
        scala) language="scala" ;;
        clj|cljs) language="clojure" ;;
        dart) language="dart" ;;
        vue) language="vue" ;;
        svelte) language="svelte" ;;
        tf|hcl) language="terraform" ;;
        Dockerfile) language="docker" ;;
        *) language="$ext" ;;
      esac
    fi
  fi

  printf '%s\t%s\n' "$language" "$file_type"
}

build_payload() {
  local event_type="$1"
  local duration_seconds="$2"
  local timestamp="$3"
  local session_id="$4"
  local project_name="$5"
  local language="$6"
  local file_type="$7"
  local branch="$8"
  local plugin_version="$9"
  local runtime_channel="${10}"
  local install_revision="${11}"

  cat <<EOF
{
  "client": {
    "plugin_version": "${plugin_version}",
    "runtime_channel": "${runtime_channel}",
    "hook_mode": "${HOOK_MODE}",
    "install_revision": "${install_revision}",
    "host_app": "claude_code"
  },
  "heartbeats": [
    {
      "source": "claude_code",
      "project_name": "${project_name}",
      "language": "${language}",
      "file_type": "${file_type}",
      "branch": "${branch}",
      "editor": "Claude Code",
      "timestamp": "${timestamp}",
      "duration_seconds": ${duration_seconds},
      "session_id": "${session_id}",
      "event_type": "${event_type}"
    }
  ]
}
EOF
}

send_heartbeat_to_profile() {
  local api_key="$1"
  local api_url="$2"
  local profile_name="$3"
  local payload="$4"
  local project_name="$5"
  local event_type="$6"
  local branch="$7"
  local language="$8"
  local duration_seconds="$9"

  [ -z "$api_key" ] && return
  api_url="${api_url:-$DEFAULT_API_URL}"

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 5 \
    -X POST \
    -H "Authorization: Bearer ${api_key}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${api_url}/api/heartbeat" 2>/dev/null || echo "000")

  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
    audit_log "$profile_name" "sent" "$project_name" "$event_type" "$branch" "$language" "$duration_seconds"
  else
    audit_log "$profile_name" "error:${http_code}" "$project_name" "$event_type" "$branch" "$language" "$duration_seconds"
  fi
}

dispatch_to_profiles() {
  local cwd="$1"
  local session_id="$2"
  local event_type="$3"
  local duration_seconds="$4"

  [ ! -f "$CONFIG_FILE" ] && return

  local timestamp project_name branch file_path language file_type payload
  local plugin_version runtime_channel install_revision
  timestamp=$(timestamp_utc)
  project_name=$(get_project_name "$cwd")
  branch=$(get_branch "$cwd")
  file_path=$(get_file_path)
  IFS=$'\t' read -r language file_type <<< "$(get_language_and_file_type "$file_path")"
  plugin_version=$(get_plugin_version)
  runtime_channel=$(get_runtime_channel)
  install_revision=$(get_install_revision)
  audit_log "system" "hook_fired" "$project_name" "$event_type" "$branch" "$language" "$duration_seconds"
  payload=$(build_payload "$event_type" "$duration_seconds" "$timestamp" "$session_id" "$project_name" "$language" "$file_type" "$branch" "$plugin_version" "$runtime_channel" "$install_revision")

  local config
  config=$(cat "$CONFIG_FILE" 2>/dev/null) || return

  if printf '%s' "$config" | grep -q '"profiles"'; then
    if command -v node >/dev/null 2>&1; then
      local matched_profiles
      matched_profiles=$(node - "$CONFIG_FILE" "$cwd" <<'NODE' 2>/dev/null
const fs = require("fs");
const [file, cwd] = process.argv.slice(2);
const cfg = JSON.parse(fs.readFileSync(file, "utf8"));
const profiles = Array.isArray(cfg.profiles) ? cfg.profiles : [cfg];
const normalizedCwd = String(cwd || "");

function matchesProject(project) {
  const prefix = String(project || "").replace(/\/+$/, "");
  return !prefix || normalizedCwd === prefix || normalizedCwd.startsWith(`${prefix}/`);
}

for (const profile of profiles) {
  if (!profile || !profile.api_key) continue;
  const projects = Array.isArray(profile.projects) ? profile.projects.filter(Boolean) : [];
  if (projects.length > 0 && !projects.some(matchesProject)) continue;
  console.log([
    profile.name || "unnamed",
    profile.api_key,
    profile.api_url || "https://quarryfi.smashedstudiosllc.workers.dev",
  ].join("\t"));
}
NODE
)

      local sent=0
      while IFS=$'\t' read -r p_name p_key p_url; do
        [ -z "$p_key" ] && continue
        send_heartbeat_to_profile "$p_key" "$p_url" "$p_name" "$payload" "$project_name" "$event_type" "$branch" "$language" "$duration_seconds" &
        sent=$((sent + 1))
      done <<< "$matched_profiles"
      [ "$sent" -gt 0 ] && wait 2>/dev/null || true
      if [ "$sent" -eq 0 ]; then
        audit_log "system" "skipped:no_matching_profile" "$project_name" "$event_type" "$branch" "$language" "$duration_seconds"
      fi
      return
    fi
  else
    local api_key api_url
    api_key=$(printf '%s' "$config" | grep -o '"api_key"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' 2>/dev/null)
    api_url=$(printf '%s' "$config" | grep -o '"api_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' 2>/dev/null)
    if [ -n "$api_key" ]; then
      send_heartbeat_to_profile "$api_key" "$api_url" "default" "$payload" "$project_name" "$event_type" "$branch" "$language" "$duration_seconds"
    fi
  fi
}

timer_is_running() {
  local cwd="$1"
  local pid_file
  pid_file=$(session_file "$cwd" "timer.pid")
  [ -f "$pid_file" ] || return 1
  local timer_pid
  timer_pid=$(cat "$pid_file" 2>/dev/null)
  [ -n "$timer_pid" ] || return 1
  kill -0 "$timer_pid" 2>/dev/null
}

start_timer_loop() {
  local cwd="$1"
  local session_id="$2"
  local pid_file
  pid_file=$(session_file "$cwd" "timer.pid")

  if timer_is_running "$cwd"; then
    return
  fi

  nohup "$0" "__timer_loop" "$cwd" "$session_id" >/dev/null 2>&1 &
  printf '%s' "$!" > "$pid_file" 2>/dev/null || true
}

stop_timer_loop() {
  local cwd="$1"
  local pid_file
  pid_file=$(session_file "$cwd" "timer.pid")
  if [ -f "$pid_file" ]; then
    local timer_pid
    timer_pid=$(cat "$pid_file" 2>/dev/null)
    if [ -n "$timer_pid" ]; then
      kill "$timer_pid" 2>/dev/null || true
    fi
    rm -f "$pid_file" 2>/dev/null || true
  fi
}

run_timer_loop() {
  local cwd="$1"
  local session_id="$2"
  local pid_file
  pid_file=$(session_file "$cwd" "timer.pid")
  printf '%s' "$$" > "$pid_file" 2>/dev/null || true

  while true; do
    sleep "$HEARTBEAT_INTERVAL_SECONDS" || exit 0

    if [ ! -f "$(session_file "$cwd" "session_id")" ]; then
      exit 0
    fi
    if [ "$(cat "$pid_file" 2>/dev/null)" != "$$" ]; then
      exit 0
    fi

    local now_ts duration_seconds
    now_ts=$(epoch_now)
    duration_seconds=$(duration_since_last_sent "$cwd" "$now_ts")
    if [ "$duration_seconds" -lt "$MIN_TICK_DURATION_SECONDS" ] 2>/dev/null; then
      continue
    fi

    dispatch_to_profiles "$cwd" "$session_id" "heartbeat" "$duration_seconds"
    record_last_sent "$cwd" "$now_ts"
  done
}

main() {
  local cwd session_id session_path event_type now_ts duration_seconds
  cwd=$(get_cwd)
  [ -z "$cwd" ] && exit 0
  ensure_session_dir "$(session_dir "$cwd")"

  if [ "$CLI_MODE" = "__timer_loop" ]; then
    run_timer_loop "$cwd" "$(get_session_id "$cwd")"
    exit 0
  fi

  session_id=$(get_session_id "$cwd")
  persist_session_context "$cwd" "$session_id"

  local raw_event
  raw_event="${HOOK_EVENT:-$CLI_MODE}"
  [ -z "$raw_event" ] && raw_event="heartbeat"
  event_type=$(map_hook_event "$raw_event")

  if { [ "$event_type" = "session_end" ] && [ ! -f "$(session_file "$cwd" "last_sent")" ] && [ ! -f "$(session_file "$cwd" "timer.pid")" ]; }; then
    exit 0
  fi

  now_ts=$(epoch_now)
  if [ "$raw_event" = "SessionStart" ]; then
    dispatch_to_profiles "$cwd" "$session_id" "session_start" 0
    record_last_sent "$cwd" "$now_ts"
    start_timer_loop "$cwd" "$session_id"
    exit 0
  fi

  if ! timer_is_running "$cwd"; then
    start_timer_loop "$cwd" "$session_id"
  fi

  duration_seconds=$(duration_since_last_sent "$cwd" "$now_ts")
  dispatch_to_profiles "$cwd" "$session_id" "$event_type" "$duration_seconds"
  record_last_sent "$cwd" "$now_ts"

  if [ "$event_type" = "session_end" ]; then
    stop_timer_loop "$cwd"
    cleanup_session_state "$cwd"
  fi
}

main
exit 0
