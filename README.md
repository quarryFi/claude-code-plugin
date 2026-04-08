# QuarryFi Claude Code Plugin

Track R&D time spent in Claude Code sessions for automated tax credit documentation.

## Install

```
/plugin install github.com/quarryfi/claude-code-plugin
```

## First Run

Run the setup script to configure your API credentials:

```bash
bash ~/.claude/plugins/cache/quarryfi-tracker/setup.sh
```

Or manually create `~/.quarryfi/config.json`:

```json
{
  "api_key": "qf_your_api_key_here",
  "api_url": "https://quarryfi.smashedstudiosllc.workers.dev"
}
```

Get your API key from the [QuarryFi dashboard](https://quarryfi.smashedstudiosllc.workers.dev/dashboard).

## What It Tracks

- **Session start/stop times** — when you begin and end Claude Code sessions
- **Project directory** — which project you're working in (basename only)
- **Session duration** — calculated from start/stop heartbeats
- **Session ID** — correlates events within a single session

## Privacy

No code content, conversation transcripts, or file contents are ever sent. Only session metadata (timestamps, project name, session ID) is transmitted to your QuarryFi account.

## Usage

Once installed, the plugin works automatically:

- **Session start**: sends an initial heartbeat when Claude Code starts
- **Session stop**: sends a final heartbeat when Claude finishes responding or the session ends

### Check Status

Use the built-in skill to check your tracking status:

```
/quarryfi-tracker:quarryfi-status
```

This shows your connection status and today's tracked R&D hours.

## Configuration

Config file: `~/.quarryfi/config.json`

| Field     | Description                          | Default                                           |
|-----------|--------------------------------------|---------------------------------------------------|
| `api_key` | Your QuarryFi API key (`qf_...`)     | Required                                          |
| `api_url` | QuarryFi API endpoint                | `https://quarryfi.smashedstudiosllc.workers.dev`  |

## Hooks

The plugin registers hooks for these Claude Code events:

| Event          | Behavior                              |
|----------------|---------------------------------------|
| `SessionStart` | Records start time, sends heartbeat   |
| `Stop`         | Sends heartbeat on response complete  |
| `SessionEnd`   | Sends final session-end heartbeat     |

## Troubleshooting

- **Plugin not tracking**: Verify `~/.quarryfi/config.json` exists and contains a valid `api_key`
- **API errors**: Run `bash setup.sh` to re-verify your API key
- **No data showing**: Check the [QuarryFi dashboard](https://quarryfi.smashedstudiosllc.workers.dev/dashboard) — data may take a moment to appear

## License

MIT
