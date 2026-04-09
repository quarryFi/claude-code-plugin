---
name: quarryfi-status
description: Check QuarryFi tracking status, configured profiles, and recent heartbeat activity from the local audit log. Use when the user asks about their QuarryFi tracking, what's being reported, or time tracking status.
---

# QuarryFi Status

Show the user what QuarryFi is tracking and what heartbeats have been sent.

## Instructions

1. Read the QuarryFi config from `~/.quarryfi/config.json`.
2. If the config file doesn't exist, tell the user to run `/quarryfi-tracker:configure` to set up.
3. Detect the config format:
   - **Multi-profile** (has `"profiles"` array): show each profile
   - **Legacy** (has top-level `"api_key"`): show as a single default profile

4. For each profile, display:
   - Profile name
   - Mapped project directories
   - Whether the current working directory matches this profile
   - Mask the API key (show only `qf_...` plus last 4 characters)

5. Read the local audit log at `~/.quarryfi/audit.log`. If it exists, show the last 20 entries:
   ```bash
   tail -20 ~/.quarryfi/audit.log
   ```
   Parse each JSON line and display in a readable table:
   - Timestamp
   - Profile name
   - Project
   - Event type (session_start, heartbeat, session_end)
   - Status (sent, error:XXX)

6. Summarize:
   - How many heartbeats were sent today
   - How many errors today
   - Which profiles sent heartbeats today

7. Tell the user: "For detailed R&D hours and session data, visit your QuarryFi dashboard: https://quarryfi.smashedstudiosllc.workers.dev/dashboard"

8. If the audit log doesn't exist or is empty, tell the user that no heartbeats have been sent yet — tracking starts on the next Claude Code session start.
