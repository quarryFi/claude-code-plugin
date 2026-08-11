# Anthropic community marketplace submission

This is the copy-and-review bundle for submitting QuarryFi through Anthropic's plugin directory form. The public target is `claude-community`; `claude-plugins-official` is curated separately by Anthropic and has no application process.

Submission form: <https://platform.claude.com/plugins/submit>

## Listing copy

**Plugin name:** QuarryFi R&D Tracker

**Plugin ID:** `quarryfi-tracker`

**Publisher:** QuarryFi

**Repository:** <https://github.com/quarryFi/claude-code-plugin>

**Homepage:** <https://quarryfi.com>

**Support:** <https://quarryfi.com/support>

**Privacy:** <https://quarryfi.com/privacy>

**License:** Apache-2.0

**Category:** Productivity

**Short description:** Create privacy-minimized Claude Code activity records in QuarryFi for R&D evidence review.

**Long description:**

QuarryFi R&D Tracker records active Claude Code session time and privacy-minimized repository context in a user's QuarryFi workspace. Lifecycle hooks send timestamps, bounded duration, project basename, branch and language categories, Git commit SHA, a one-way repository fingerprint, changed-file count, coarse activity type, and runtime diagnostics. The plugin does not send source code, file contents, filenames, local paths, prompts, transcripts, commands, command output, diffs, commit messages, or raw repository URLs. Users explicitly map local project directories to seat-assigned QuarryFi keys. QuarryFi supports evidence review and documentation workflows; the plugin does not determine tax-credit eligibility or provide tax advice.

**Search terms:** R&D, research and development, evidence, time tracking, activity tracking, tax credit documentation, QuarryFi

## Components and permissions disclosure

The plugin contains:

- one status skill;
- `configure` and `update` commands;
- lifecycle hooks for `SessionStart`, `PostToolUse`, `UserPromptSubmit`, `SubagentStop`, `Stop`, and `SessionEnd`; and
- local shell scripts that read Git metadata, bounded tracker state, and the user-created `~/.quarryfi/config.json`.

Automatic network access is limited to `https://quarryfi.com/api/heartbeat`. The status skill calls `https://quarryfi.com/api/status` only when invoked by the user. The hook does not execute content returned by either endpoint.

## Reviewer test plan

No paid QuarryFi account or real seat key is required for structural and privacy review.

1. Clone the repository and check out the release submitted for review.
2. Run strict validation:

   ```bash
   claude plugin validate .claude-plugin/plugin.json --strict
   claude plugin validate .claude-plugin/marketplace.json --strict
   ```

3. Run regression tests:

   ```bash
   node tests/hostname-regression.mjs
   node tests/tracker-context-regression.mjs
   node tests/setup-privacy-regression.mjs
   node tests/submission-readiness.mjs
   ```

4. Inspect `tests/tracker-context-regression.mjs`. It replaces `curl` with a local capture fixture, triggers the real hook, parses the generated heartbeat, and verifies that source content and prohibited fields are absent. `tests/setup-privacy-regression.mjs` also verifies hidden key input, owner-only config permissions, fixed production routing, and valid JSON for quoted profile names.
5. Load the plugin locally:

   ```bash
   claude --plugin-dir .
   ```

6. Run `/quarryfi-tracker:configure`. Confirm it does not request a key in chat and instead returns a terminal command for the hidden-input setup script.
7. Run `/quarryfi-tracker:quarryfi-status` without a config. Confirm it explains that no heartbeats have been sent and points to configuration.

An end-to-end accepted-heartbeat test requires a QuarryFi Core account and a seat-assigned key. Reviewers can request a temporary test seat through `support@quarryfi.com` without including credentials in email.

## Safety review notes

- The hook starts a 60-second timer only for an active configured session and clears timing state at session end.
- Network requests have a five-second timeout and do not block Claude Code on failure.
- The audit log is bounded and contains no seat key.
- Marketplace builds default-deny custom API endpoints.
- API-key input is hidden in a regular terminal and does not enter the Claude conversation.
- The repository contains its declared Apache-2.0 license, privacy disclosure, and private vulnerability-reporting instructions.

## Pre-submission checklist

- [ ] Merge the submission-preparation commit to the repository's default branch.
- [ ] Tag and publish version `1.6.3`.
- [ ] Confirm the GitHub repository is public and the tag resolves without authentication.
- [ ] Run strict validation against both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` using the current Claude Code release.
- [ ] Run all three regression tests from a fresh checkout.
- [ ] Confirm <https://quarryfi.com/privacy>, <https://quarryfi.com/support>, and the repository README are public.
- [ ] Paste the listing copy above into Anthropic's submission form.
- [ ] Review and personally accept all publisher, policy, data-use, and security attestations.
- [ ] Submit the default-branch repository URL; do not open a pull request against Anthropic's read-only community mirror.

After approval, update the public README and QuarryFi integrations page so the primary install path becomes:

```text
/plugin marketplace add anthropics/claude-plugins-community
/plugin install quarryfi-tracker@claude-community
```

Keep the QuarryFi repository marketplace instructions as the fallback until the community catalog entry is confirmed installable.
