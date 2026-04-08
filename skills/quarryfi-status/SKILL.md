---
name: quarryfi-status
description: Check QuarryFi tracking status, configured profiles, project routing, and today's tracked R&D hours. Use when the user asks about their QuarryFi tracking, R&D hours, or time tracking status.
---

# QuarryFi Status

Check the user's QuarryFi R&D time tracking status across all configured profiles.

## Instructions

1. Read the QuarryFi config from `~/.quarryfi/config.json`.
2. If the config file doesn't exist, tell the user to run setup first:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/setup.sh"
   ```
3. Detect the config format:
   - **Multi-profile** (has `"profiles"` array): iterate over each profile
   - **Legacy** (has top-level `"api_key"`): treat as a single default profile

4. For each profile, display:
   - Profile name
   - Mapped project directories
   - Whether the current working directory matches this profile

5. For each profile, call the QuarryFi status API:
   ```bash
   curl -s -H "Authorization: Bearer $API_KEY" "${API_URL}/api/status"
   ```
   Display:
   - Connection status (whether the API key is valid)
   - Today's total tracked R&D hours
   - Number of sessions today

6. Check for the local audit log at `~/.quarryfi/audit.log`. If it exists, show the last 5 entries:
   ```bash
   tail -5 ~/.quarryfi/audit.log
   ```
   Parse each JSON line and display: timestamp, profile, project, event type, and status.

7. Format everything clearly with sections per profile and a summary showing:
   - Total profiles configured
   - Which profile(s) match the current directory
   - Combined hours across all profiles today
