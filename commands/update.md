---
description: Update the QuarryFi plugin to the latest released marketplace version
---

# QuarryFi Update

Refresh the QuarryFi marketplace using Claude Code's plugin manager and make sure the cached install Claude actually executes matches it.

## Instructions

Run these commands in order using the Bash tool:

1. Refresh the registered marketplace through Claude Code, then capture its version and commit:
```bash
claude plugin marketplace update quarryfi
MARKETPLACE_VERSION=$(grep '"version"' ~/.claude/plugins/marketplaces/quarryfi/.claude-plugin/plugin.json | head -1)
MARKETPLACE_COMMIT=$(git -C ~/.claude/plugins/marketplaces/quarryfi rev-parse HEAD)
```

2. Read the active cached install details from Claude's installed plugins file:
```bash
node -e 'const fs=require("fs");const file=process.env.HOME+"/.claude/plugins/installed_plugins.json";const data=JSON.parse(fs.readFileSync(file,"utf8"));const plugin=data.plugins.find((p)=>p.id==="quarryfi-tracker@quarryfi");if(!plugin){process.exit(1)}console.log(JSON.stringify({version:plugin.version,commit:plugin.gitCommitSha,path:plugin.installPath},null,2));'
```

3. Compare the cached install's version file too:
```bash
find ~/.claude/plugins/cache/quarryfi -name "plugin.json" -path "*/.claude-plugin/*" -exec grep '"version"' {} \; 2>/dev/null | head -1
```

4. If the cached install version OR commit differs from the marketplace clone, run the plugin update:
```bash
claude plugin update quarryfi-tracker@quarryfi
```

5. Tell the user to run `/reload-plugins` so the current session loads the refreshed plugin.

6. Report the result to the user:
   - If updated: "Updated QuarryFi plugin to vX.Y.Z and refreshed the active cached install. Run `/reload-plugins`; start a new Claude session if you want a clean tracking boundary."
   - If already current: "QuarryFi plugin is already current in both the marketplace clone and Claude's active cached install (vX.Y.Z)."
   - If update failed: show the error and suggest uninstalling/reinstalling.

7. Remind the user to verify with `/quarryfi-tracker:quarryfi-status`, which should now show:
   - marketplace version/commit
   - cached install version/commit
   - last local audit event timestamp
