# QuarryFi Claude Code Plugin

Track R&D time spent in Claude Code sessions for automated tax credit documentation.

## Install

### Step 1: Add the marketplace

**Claude Code CLI:**
```
/plugin marketplace add https://github.com/quarryFi/claude-code-plugin.git
```

**Claude Desktop:** Click **+** next to the prompt box > **Plugins** > **Add plugin** > paste the URL above.

### Step 2: Install the plugin

**Claude Code CLI:**
```
/plugin install quarryfi-tracker@quarryfi
```

**Claude Desktop:** Find **Quarryfi tracker** in your plugins list and click **Install**.

### Step 3: Add your API key and projects

Run the configure command in any Claude Code session:

```
/quarryfi-tracker:configure
```

This walks you through:
1. **Profile name** — label for the company/account (e.g. "Acme Corp")
2. **API key** — from your [QuarryFi dashboard](https://quarryfi.smashedstudiosllc.workers.dev/dashboard)
3. **Project directories** — which local directories this key tracks

Repeat to add more companies. Each profile maps one API key to one or more project directories.

**Alternative:** Create `~/.quarryfi/config.json` manually (see [Config format](#config-format) below) or run the interactive setup script:

```bash
bash ~/.claude/plugins/cache/quarryfi/quarryfi-tracker/setup.sh
```

### Step 4: Start coding

Use Claude Code normally. R&D time automatically appears on your [QuarryFi dashboard](https://quarryfi.smashedstudiosllc.workers.dev/dashboard).

## Multi-Company Setup

Freelancers and consultants working for multiple companies can route heartbeats to different QuarryFi accounts based on which project directory they're working in.

Each profile maps an API key to specific project directories. Add as many profiles as you need:

```
/quarryfi-tracker:configure add
```

### How project-to-key routing works

When a hook fires, the plugin reads your current working directory and checks it against each profile's `projects` list using prefix matching. If your cwd is `/Users/me/work/acme-api/src/handlers`, it matches the profile with `/Users/me/work/acme-api`.

- If **one profile** matches: heartbeat goes to that company's endpoint
- If **multiple profiles** match: heartbeat goes to all matching endpoints
- If **no profile** matches: no heartbeat is sent (explicit opt-in required)

### Managing profiles

```
/quarryfi-tracker:configure           # show current profiles, add/edit/remove
/quarryfi-tracker:configure add       # add a new profile
/quarryfi-tracker:configure remove "Acme Corp"   # remove a profile
/quarryfi-tracker:configure list      # show all profiles
```

## Config Format

Config file: `~/.quarryfi/config.json`

```json
{
  "profiles": [
    {
      "name": "Acme Corp",
      "api_key": "qf_abc123...",
      "api_url": "https://quarryfi.smashedstudiosllc.workers.dev",
      "projects": ["/Users/me/work/acme-api", "/Users/me/work/acme-frontend"]
    },
    {
      "name": "Personal R&D",
      "api_key": "qf_def456...",
      "api_url": "https://quarryfi.smashedstudiosllc.workers.dev",
      "projects": ["/Users/me/projects/ml-experiment"]
    }
  ]
}
```

| Field      | Description                                    |
|------------|------------------------------------------------|
| `name`     | Display name for the profile                   |
| `api_key`  | QuarryFi API key (`qf_...`) for this company   |
| `api_url`  | API endpoint (defaults to workers.dev URL)      |
| `projects` | Array of absolute directory paths to track      |

### Backward compatibility

The old single-key format still works:

```json
{
  "api_key": "qf_...",
  "api_url": "https://quarryfi.smashedstudiosllc.workers.dev"
}
```

When detected, it behaves as a single profile with no project filter — all sessions are tracked regardless of directory.

## What It Tracks

- **Session start/stop times** — when you begin and end Claude Code sessions
- **Project directory** — which project you're working in (basename only)
- **Session duration** — calculated from start/stop heartbeats
- **Session ID** — correlates events within a single session

## Privacy

No code content, conversation transcripts, or file contents are ever sent. Only session metadata (timestamps, project name, session ID) is transmitted to your QuarryFi account.

## Local Audit Log

Every heartbeat sent is logged locally to `~/.quarryfi/audit.log` as one JSON line per event:

```json
{"timestamp":"2026-04-08T14:30:00Z","profile":"Acme Corp","project":"acme-api","event":"session_start","status":"sent"}
```

The log auto-truncates when it exceeds 1 MB (oldest half is removed). Logging is fire-and-forget and never blocks the session.

## Commands & Skills

| Command | Description |
|---------|-------------|
| `/quarryfi-tracker:configure` | Add, remove, or list API key profiles and project mappings |
| `/quarryfi-tracker:quarryfi-status` | Check tracking status and today's R&D hours per profile |

## Hooks

| Event          | Behavior                              |
|----------------|---------------------------------------|
| `SessionStart` | Checks config, sends heartbeat        |
| `Stop`         | Sends heartbeat on response complete  |
| `SessionEnd`   | Sends final session-end heartbeat     |

## Troubleshooting

- **"QuarryFi is not configured"** on session start: Run `/quarryfi-tracker:configure` to add your API key
- **Wrong company receiving data**: Check that your project directories are correct absolute paths in the right profile
- **No data for a project**: Ensure the project path is listed in a profile's `projects` array
- **Check audit log**: `tail -20 ~/.quarryfi/audit.log` shows recent send attempts and errors
- **No data on dashboard**: Data may take a moment to appear — check audit.log for `"status":"sent"`

## License

MIT
