# QuarryFi Claude Code Plugin

Track R&D time spent in Claude Code sessions for automated tax credit documentation.

## Install

### Claude Code (Terminal / CLI)

```
/plugin install github.com/quarryfi/claude-code-plugin
```

### Claude Desktop (Mac / Windows)

1. Click the **+** button next to the prompt box
2. Select **Plugins**
3. Select **Add plugin**
4. Search for `quarryfi-tracker` or browse to find it
5. Click **Install** and choose your scope:
   - **User** — active across all projects
   - **Project** — shared with collaborators in this repo
   - **Local** — just for you in this repo

After installing, run `/reload-plugins` to activate without restarting.

## First Run

Run the setup script to configure your profiles:

```bash
bash ~/.claude/plugins/cache/quarryfi-tracker/setup.sh
```

The setup wizard walks you through:
1. Enter a profile name (e.g. "Acme Corp")
2. Enter the API key for that company
3. Enter project directories to track (comma-separated absolute paths)
4. Optionally add more profiles

Get your API key from the [QuarryFi dashboard](https://quarryfi.smashedstudiosllc.workers.dev/dashboard).

## Multi-Company Setup

Freelancers and consultants working for multiple companies can route heartbeats to different QuarryFi accounts based on which project directory they're working in.

### How project-to-key routing works

When a hook fires, the plugin reads your current working directory and checks it against each profile's `projects` list using prefix matching. If your cwd is `/Users/me/work/acme-api/src/handlers`, it matches the profile with `/Users/me/work/acme-api`.

- If **one profile** matches: heartbeat goes to that company's endpoint
- If **multiple profiles** match: heartbeat goes to all matching endpoints
- If **no profile** matches: no heartbeat is sent (explicit opt-in required)

### Config format

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

When detected, it behaves as a single profile with no project filter — all sessions are tracked regardless of directory, matching the original behavior.

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

## Usage

Once installed, the plugin works automatically:

- **Session start**: sends a heartbeat when Claude Code starts
- **Response stop**: sends a heartbeat when Claude finishes responding
- **Session end**: sends a final heartbeat when the session terminates

### Check Status

Use the built-in skill to check your tracking status:

```
/quarryfi-tracker:quarryfi-status
```

This shows:
- All configured profiles and their mapped projects
- Which profile(s) match your current working directory
- Connection status and today's R&D hours per profile
- Recent entries from the local audit log

## Hooks

The plugin registers hooks for these Claude Code events:

| Event          | Behavior                              |
|----------------|---------------------------------------|
| `SessionStart` | Records start time, sends heartbeat   |
| `Stop`         | Sends heartbeat on response complete  |
| `SessionEnd`   | Sends final session-end heartbeat     |

## Troubleshooting

- **Plugin not tracking**: Verify `~/.quarryfi/config.json` exists with valid profiles
- **Wrong company receiving data**: Check that your project directories are correct absolute paths
- **No data for a project**: Ensure the project path is listed in a profile's `projects` array
- **API errors**: Run `bash setup.sh` to re-verify your API keys
- **Check audit log**: `tail -20 ~/.quarryfi/audit.log` shows recent send attempts and errors
- **No data on dashboard**: Data may take a moment to appear — check audit.log for `"status":"sent"`

## License

MIT
