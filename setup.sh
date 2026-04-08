#!/usr/bin/env bash
# quarryFi plugin setup
# Walks the user through creating multi-profile config at ~/.quarryfi/config.json.
# Supports multiple companies/API keys with per-project routing.

set -euo pipefail

CONFIG_DIR="$HOME/.quarryfi"
CONFIG_FILE="$CONFIG_DIR/config.json"
DEFAULT_API_URL="https://quarryfi.smashedstudiosllc.workers.dev"

echo ""
echo "  quarryFi Plugin Setup"
echo "  ─────────────────────"
echo ""

# Check for existing config
if [ -f "$CONFIG_FILE" ]; then
  echo "  Existing config found at $CONFIG_FILE"
  read -rp "  Overwrite? [y/N] " overwrite
  if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
    echo "  Setup cancelled."
    exit 0
  fi
  echo ""
fi

# Collect profiles
PROFILES_JSON=""
profile_index=0

while true; do
  if [ "$profile_index" -eq 0 ]; then
    echo "  Let's set up your first profile."
  else
    echo ""
    echo "  Adding another profile."
  fi
  echo ""

  # Profile name
  read -rp "  Profile name (e.g. Acme Corp): " profile_name
  if [ -z "$profile_name" ]; then
    echo "  ✗ Profile name is required."
    continue
  fi

  # API key
  echo ""
  echo "  Get your API key from your QuarryFi dashboard:"
  echo "  ${DEFAULT_API_URL}/dashboard"
  echo ""
  read -rp "  API Key (qf_...): " api_key

  # Validate key format
  if [[ ! "$api_key" =~ ^qf_[a-f0-9]{40}$ ]]; then
    echo ""
    echo "  ✗ Invalid key format. Expected: qf_ followed by 40 hex characters."
    echo "  Example: qf_a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
    echo "  Skipping this profile."
    continue
  fi

  # API URL
  read -rp "  API URL [${DEFAULT_API_URL}]: " api_url
  api_url="${api_url:-$DEFAULT_API_URL}"

  # Project directories
  echo ""
  echo "  Enter project directories this profile should track."
  echo "  Use absolute paths, comma-separated."
  echo "  Example: /Users/me/work/acme-api, /Users/me/work/acme-frontend"
  echo ""
  read -rp "  Project directories: " projects_raw

  # Build projects JSON array
  projects_json="["
  if [ -n "$projects_raw" ]; then
    first=true
    IFS=',' read -ra proj_arr <<< "$projects_raw"
    for proj in "${proj_arr[@]}"; do
      proj=$(echo "$proj" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -n "$proj" ]; then
        if [ "$first" = true ]; then
          first=false
        else
          projects_json+=", "
        fi
        projects_json+="\"${proj}\""
      fi
    done
  fi
  projects_json+="]"

  # Build this profile's JSON
  if [ -n "$PROFILES_JSON" ]; then
    PROFILES_JSON+=","
  fi
  PROFILES_JSON+="
    {
      \"name\": \"${profile_name}\",
      \"api_key\": \"${api_key}\",
      \"api_url\": \"${api_url}\",
      \"projects\": ${projects_json}
    }"

  profile_index=$((profile_index + 1))

  echo ""
  echo "  ✓ Profile \"${profile_name}\" added."
  echo ""
  read -rp "  Add another profile? [y/N] " add_more
  if [[ ! "$add_more" =~ ^[Yy]$ ]]; then
    break
  fi
done

if [ "$profile_index" -eq 0 ]; then
  echo "  No profiles configured. Setup cancelled."
  exit 1
fi

# Write config
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<EOF
{
  "profiles": [${PROFILES_JSON}
  ]
}
EOF

chmod 600 "$CONFIG_FILE"

echo ""
echo "  ✓ Config written to $CONFIG_FILE (${profile_index} profile(s))"
echo ""

# Verify each profile's API key
echo "  Verifying API keys..."
echo ""

# Re-read and verify each profile
i=0
while [ "$i" -lt "$profile_index" ]; do
  # Extract the i-th profile's key and url from the written config
  p_name=$(awk -v idx="$i" '/"name"/{if(n++==idx){gsub(/.*"name"[[:space:]]*:[[:space:]]*"/,""); gsub(/".*/,""); print; exit}}' "$CONFIG_FILE")
  p_key=$(awk -v idx="$i" '/"api_key"/{if(n++==idx){gsub(/.*"api_key"[[:space:]]*:[[:space:]]*"/,""); gsub(/".*/,""); print; exit}}' "$CONFIG_FILE")
  p_url=$(awk -v idx="$i" '/"api_url"/{if(n++==idx){gsub(/.*"api_url"[[:space:]]*:[[:space:]]*"/,""); gsub(/".*/,""); print; exit}}' "$CONFIG_FILE")
  p_url="${p_url:-$DEFAULT_API_URL}"

  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${p_key}" \
    -H "Content-Type: application/json" \
    -d '{"heartbeats":[{"source":"claude_code","editor":"Claude Code","timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","event_type":"setup_verify"}]}' \
    "${p_url}/api/heartbeat" 2>/dev/null || echo "000")

  if [ "$status" = "200" ]; then
    echo "  ✓ ${p_name}: API key is valid"
  elif [ "$status" = "401" ]; then
    echo "  ✗ ${p_name}: API key was rejected"
  else
    echo "  ⚠ ${p_name}: Could not reach API (HTTP ${status})"
  fi

  i=$((i + 1))
done

echo ""
echo "  Setup complete! The plugin will route heartbeats based on your"
echo "  working directory. Run /quarryfi-tracker:quarryfi-status to verify."
echo ""
