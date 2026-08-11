---
description: Configure QuarryFi tracking without exposing API keys in the Claude conversation
---

# QuarryFi Configure

Help the user configure QuarryFi through the plugin's local setup script. API keys are secrets: never ask the user to paste one into the Claude conversation, never read a complete key back into context, and never print one in a response.

## Instructions

1. Resolve the active plugin install path without reading the user's QuarryFi configuration:

   ```bash
   node -e 'const fs=require("fs");const file=process.env.HOME+"/.claude/plugins/installed_plugins.json";const data=JSON.parse(fs.readFileSync(file,"utf8"));const plugin=data.plugins.find((p)=>p.id==="quarryfi-tracker@quarryfi"||String(p.id||"").startsWith("quarryfi-tracker@"));if(!plugin?.installPath)process.exit(1);console.log(plugin.installPath);'
   ```

2. Give the user an exact command using the resolved path:

   ```bash
   bash "/resolved/plugin/path/setup.sh"
   ```

   Tell them to run it in their regular terminal. The setup script hides API-key input, validates the key format, writes `~/.quarryfi/config.json` with mode `600`, and sends only a verification heartbeat to `https://quarryfi.com`.

3. Do not execute the interactive script through Claude's Bash tool. The user should enter the key directly into their terminal so it is not included in the Claude conversation or tool transcript.

4. After the user says setup is complete, offer `/quarryfi-tracker:quarryfi-status`. That skill masks keys and shows tracking health.

5. If the plugin path cannot be resolved, tell the user to reinstall the plugin and retry. Do not search unrelated files for API keys.

## Important safety rules

- Never request or display a full `qf_` key.
- Never accept a custom API endpoint in a marketplace installation. Released builds send to `https://quarryfi.com` only.
- Never overwrite or delete an existing config without the setup script's explicit confirmation prompt.
- Do not inspect source files, prompts, transcripts, command output, or diffs during configuration.
