---
name: quarryfi-status
description: Check QuarryFi tracking status, configured profiles, and recent heartbeat activity from the local audit log. Use when the user asks about their QuarryFi tracking, what's being reported, or time tracking status.
---

# QuarryFi Status

Show the user what QuarryFi is tracking, whether the installed Claude plugin matches the marketplace copy, and whether local hooks have fired recently.

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

5. Read the marketplace clone version + commit:
   ```bash
   grep '"version"' ~/.claude/plugins/marketplaces/quarryfi/.claude-plugin/plugin.json
   git -C ~/.claude/plugins/marketplaces/quarryfi rev-parse HEAD
   ```

6. Read the active cached install version + commit:
   ```bash
   node -e 'const fs=require("fs");const file=process.env.HOME+"/.claude/plugins/installed_plugins.json";const data=JSON.parse(fs.readFileSync(file,"utf8"));const plugin=data.plugins.find((p)=>p.id==="quarryfi-tracker@quarryfi");if(plugin){console.log(JSON.stringify({version:plugin.version,commit:plugin.gitCommitSha,path:plugin.installPath},null,2));}'
   ```

7. For each profile, query the server status endpoint:
   ```bash
   curl -s -H "Authorization: Bearer $API_KEY" "$API_URL/api/status"
   ```
   If it succeeds, show:
   - Last heartbeat timestamp
   - Last accepted heartbeat receipt
   - Last authenticated contact
   - Health state
   - Plugin version / runtime channel / hook mode / install revision
   - Last 24 hours tracked minutes
   - Last 7 days tracked minutes
   - Active projects from the last 7 days
   - Recent sessions

8. Read the local audit log at `~/.quarryfi/audit.log`. If it exists, show the last 20 entries:
   ```bash
   tail -20 ~/.quarryfi/audit.log
   ```
   Parse each JSON line and display in a readable table:
   - Timestamp
   - Profile name
   - Project
   - Event type (session_start, heartbeat, session_end)
   - Status (sent, error:XXX)

9. Summarize:
   - How many heartbeats were sent today
   - How many errors today
   - Which profiles sent heartbeats today
   - Whether the marketplace clone and active cached install match
   - The timestamp of the last local audit event

10. Tell the user: "For detailed deduped R&D hours and qualification review, visit your QuarryFi dashboard: https://quarryfi.smashedstudiosllc.workers.dev/dashboard"

11. If the audit log doesn't exist or is empty, tell the user that no heartbeats have been sent yet — tracking starts on the next Claude Code session start.
