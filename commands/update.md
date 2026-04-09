---
description: Force update the QuarryFi plugin to the latest version from GitHub
---

# QuarryFi Update

Force-pull the latest plugin version from the marketplace and update the installed plugin.

## Instructions

Run these commands in order using the Bash tool:

1. Update the marketplace clone:
```bash
git -C ~/.claude/plugins/marketplaces/quarryfi fetch origin && git -C ~/.claude/plugins/marketplaces/quarryfi reset --hard origin/main
```

2. Get the new version number:
```bash
grep '"version"' ~/.claude/plugins/marketplaces/quarryfi/.claude-plugin/plugin.json
```

3. Get the currently installed version:
```bash
find ~/.claude/plugins/cache/quarryfi -name "plugin.json" -path "*/.claude-plugin/*" -exec grep '"version"' {} \; 2>/dev/null | head -1
```

4. If the versions differ, run the plugin update:
```bash
claude plugin update quarryfi-tracker@quarryfi
```

5. Report the result to the user:
   - If updated: "Updated QuarryFi plugin from vX.Y.Z to vA.B.C. Start a new session to use the new version."
   - If already current: "QuarryFi plugin is already at the latest version (vX.Y.Z)."
   - If update failed: show the error and suggest uninstalling/reinstalling.
