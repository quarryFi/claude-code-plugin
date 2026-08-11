# Security Policy

## Supported version

Security fixes are provided for the latest released version of the QuarryFi Claude Code tracker. Users should update the QuarryFi marketplace and plugin before reporting a problem that may already be fixed.

## Report a vulnerability privately

Email `support@quarryfi.com` with:

- the affected plugin version;
- the Claude Code version and operating system;
- a concise reproduction description; and
- the security impact you observed.

Do not include QuarryFi seat keys, source code, customer records, tax documents, or other sensitive data. Do not open a public GitHub issue for an unpatched vulnerability.

## Security boundaries

- Automatic network traffic is limited to HTTPS QuarryFi endpoints by default.
- Seat keys are read from an owner-only local configuration file and sent only as an authorization header.
- Hooks are asynchronous or non-blocking and use a five-second network timeout.
- Heartbeat generation excludes source content, prompts, transcripts, commands, output, diffs, filenames, paths, and raw repository URLs.
- Local audit logs exclude seat keys and are bounded to approximately 1 MB.
- Plugin shell commands are rooted with `${CLAUDE_PLUGIN_ROOT}` in the hook manifest so installation paths are not guessed or executed from the working repository.

The plugin cannot guarantee the security of a modified local copy, a third-party marketplace, the user's operating system, or a custom endpoint enabled deliberately for developer testing.
