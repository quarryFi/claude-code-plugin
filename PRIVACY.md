# QuarryFi Claude Code Tracker Privacy

The QuarryFi tracker is an opt-in Claude Code plugin. It observes lifecycle events locally and sends privacy-minimized activity records to the QuarryFi account associated with the user's seat key.

This document describes plugin behavior. QuarryFi's service-level privacy terms are available at [quarryfi.com/privacy](https://quarryfi.com/privacy).

## Network destination

Marketplace releases send HTTPS requests only to:

- `https://quarryfi.com/api/heartbeat`
- `https://quarryfi.com/api/status` when the user explicitly runs the status skill

The seat key is sent in the HTTPS `Authorization` header. It is never included in the heartbeat body or local audit log. Released plugins do not allow the configuration file or an environment variable to redirect requests to another host.

## Data sent by automatic hooks

Depending on the event and repository state, a heartbeat can include:

- UTC timestamp, event type, session identifier, and bounded duration;
- project directory basename, current Git branch, language, and file-extension category;
- current Git commit SHA;
- a one-way SHA-256 fingerprint of a GitHub `owner/repository` name;
- changed tracked-file count, capped at 10,000;
- coarse activity category such as implementation, test, schema, documentation, or configuration; and
- plugin version, runtime channel, hook mode, install revision, and host application.

## Data not sent

The plugin does not transmit:

- source code or file contents;
- filenames or absolute local paths;
- prompts, conversation transcripts, or Claude responses;
- commands or command output;
- diffs or commit messages;
- raw repository URLs or repository names;
- environment variables; or
- the contents of unrelated local files.

The regression test in `tests/tracker-context-regression.mjs` captures a real generated heartbeat locally and asserts that private fixture content and prohibited fields are absent.

## Local files and retention

- `~/.quarryfi/config.json` stores profile names, project mappings, and seat keys. The setup script creates it with owner-only permissions (`600`). It remains until the user edits or deletes it.
- `~/.quarryfi/audit.log` stores delivery metadata without seat keys. It automatically removes the oldest half after exceeding 1 MB.
- `~/.quarryfi/session-claude-*` contains temporary session timing state. The plugin clears it when the session ends; abandoned state can be deleted safely while Claude Code is stopped.
- `~/.quarryfi/update-notices` prevents repeating the same version notice and deletes markers older than 30 days.

Uninstalling the plugin stops new hook activity but does not silently delete the user's local configuration or audit log. To remove all local tracker data after uninstalling, delete `~/.quarryfi`.

## Account data and deletion

Users can review their activity in QuarryFi. Account-data access and deletion requests can be initiated through [quarryfi.com/support](https://quarryfi.com/support) or `support@quarryfi.com`. Server retention and deletion are governed by QuarryFi's published privacy policy.

## Configuration privacy

`/quarryfi-tracker:configure` never asks the user to paste a seat key into the Claude conversation. It resolves the installed setup script and instructs the user to run that script in a regular terminal, where key input is hidden.
