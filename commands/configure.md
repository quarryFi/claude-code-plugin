---
description: Configure QuarryFi API keys and project mappings for R&D time tracking. Supports multiple companies/keys.
---

# QuarryFi Configure

Configure API keys and map them to project directories. Each key belongs to a profile (a company or account), and each profile tracks specific project directories.

Config file location: `~/.quarryfi/config.json`
Dashboard for API keys: https://quarryfi.smashedstudiosllc.workers.dev/dashboard

## Step 1: Read existing config

Read `~/.quarryfi/config.json` if it exists. It may be in one of two formats:

**Multi-profile format** (has `"profiles"` array):
```json
{
  "profiles": [
    {
      "name": "Acme Corp",
      "api_key": "qf_...",
      "api_url": "https://quarryfi.smashedstudiosllc.workers.dev",
      "projects": ["/Users/me/work/acme-api", "/Users/me/work/acme-frontend"]
    }
  ]
}
```

**Legacy single-key format** (has top-level `"api_key"`):
```json
{
  "api_key": "qf_...",
  "api_url": "https://quarryfi.smashedstudiosllc.workers.dev"
}
```

If legacy format exists, migrate it: treat it as one profile named "Default" with no project filter, and convert to the multi-profile format before making any changes.

## Step 2: Show current state

If profiles exist, display them in a table:

| # | Profile | API Key | Projects |
|---|---------|---------|----------|
| 1 | Acme Corp | qf_...a1b2 | /Users/me/work/acme-api, /Users/me/work/acme-frontend |
| 2 | Personal R&D | qf_...c3d4 | /Users/me/projects/ml-experiment |

Mask API keys — show only `qf_...` plus the last 4 characters.

If no config exists, say so and proceed to adding the first profile.

## Step 3: Determine action from $ARGUMENTS

The argument is: "$ARGUMENTS"

Parse the arguments to determine what the user wants:

- **No arguments**: Show current config, then ask what they'd like to do: add a profile, edit a profile, or remove a profile.
- **`add`**: Add a new profile (go to Step 4).
- **`remove <name>`**: Remove the named profile from the config and write the updated file.
- **`list`**: Just show the current profiles table (Step 2) and stop.
- **A bare API key** (starts with `qf_`): Shortcut — ask for a profile name and project directories, then add it as a new profile.

## Step 4: Add a profile

Ask the user for these three things (use AskUserQuestion or conversation):

1. **Profile name** — A label for this company/account (e.g. "Acme Corp", "Personal R&D")
2. **API key** — Their QuarryFi API key (starts with `qf_`). Get it from: https://quarryfi.smashedstudiosllc.workers.dev/dashboard
3. **Project directories** — Absolute paths to the directories this key should track. The hook uses prefix matching, so `/Users/me/work/acme-api` covers all subdirectories.

API URL defaults to `https://quarryfi.smashedstudiosllc.workers.dev` — only ask if the user mentions a custom endpoint.

## Step 5: Verify the key

Test the API key:

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer THE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"heartbeats":[{"source":"claude_code","editor":"Claude Code","timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","event_type":"setup_verify"}]}' \
  "https://quarryfi.smashedstudiosllc.workers.dev/api/heartbeat"
```

Report result: 200 = valid, 401 = rejected (still save if user wants), other = unreachable.

## Step 6: Write config

Add the new profile to the existing profiles array (don't overwrite existing profiles). Write the complete config to `~/.quarryfi/config.json`:

```bash
mkdir -p ~/.quarryfi
cat > ~/.quarryfi/config.json << 'EOF'
{
  "profiles": [
    ... existing profiles ...,
    {
      "name": "NEW_PROFILE_NAME",
      "api_key": "qf_...",
      "api_url": "https://quarryfi.smashedstudiosllc.workers.dev",
      "projects": ["/path/to/project1", "/path/to/project2"]
    }
  ]
}
EOF
chmod 600 ~/.quarryfi/config.json
```

## Step 7: Confirm and offer next steps

After saving, show the updated profiles table and tell the user:

- Tracking is now active for the configured projects.
- To add another company/key: `/quarryfi-tracker:configure add`
- To check tracking status: `/quarryfi-tracker:quarryfi-status`
- To remove a profile: `/quarryfi-tracker:configure remove "Profile Name"`

## Important notes

- Always preserve existing profiles when adding new ones.
- The hook script matches the current working directory against each profile's `projects` array using prefix matching. If cwd starts with a project path, that profile's key is used.
- Multiple profiles can match the same directory — heartbeats go to all matching profiles.
- If no profile matches the current directory, no heartbeat is sent. This is by design — explicit opt-in only.
- The config file is at `~/.quarryfi/config.json` — same file used by both the `/configure` command and `setup.sh`.
