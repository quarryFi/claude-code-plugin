---
name: quarryfi-status
description: Check QuarryFi tracking status and today's tracked R&D hours. Use when the user asks about their QuarryFi tracking, R&D hours, or time tracking status.
---

# QuarryFi Status

Check the user's QuarryFi R&D time tracking status and show today's tracked hours.

## Instructions

1. Read the QuarryFi config from `~/.quarryfi/config.json` to get the API key and URL.
2. If the config file doesn't exist, tell the user to run setup first:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/setup.sh"
   ```
3. Call the QuarryFi status API using the Bash tool:
   ```bash
   API_KEY=$(cat ~/.quarryfi/config.json | grep -o '"api_key"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//')
   API_URL=$(cat ~/.quarryfi/config.json | grep -o '"api_url"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//;s/"$//')
   API_URL="${API_URL:-https://quarryfi.smashedstudiosllc.workers.dev}"
   curl -s -H "Authorization: Bearer $API_KEY" "${API_URL}/api/status"
   ```
4. Parse the JSON response and display:
   - Connection status (whether the API key is valid)
   - Today's total tracked R&D hours
   - Number of sessions today
   - Current active session (if any)
5. Format the output clearly for the user.
