import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = new URL("../", import.meta.url).pathname;
const temp = mkdtempSync(join(tmpdir(), "quarryfi-claude-context-"));
const project = join(temp, "private-example");
const configDir = join(temp, ".quarryfi");
const binDir = join(temp, "bin");
const captureFile = join(temp, "payload.json");

try {
  mkdirSync(project, { recursive: true });
  mkdirSync(configDir, { recursive: true });
  mkdirSync(binDir, { recursive: true });
  writeFileSync(join(project, "package.json"), "{}\n");
  execFileSync("git", ["init", "-q", project]);
  execFileSync("git", ["-C", project, "config", "user.email", "tracker-test@quarryfi.test"]);
  execFileSync("git", ["-C", project, "config", "user.name", "QuarryFi Tracker Test"]);
  execFileSync("git", ["-C", project, "add", "package.json"]);
  execFileSync("git", ["-C", project, "commit", "-qm", "test fixture"]);
  execFileSync("git", ["-C", project, "remote", "add", "origin", "https://github.com/QuarryFi/private-example.git"]);
  writeFileSync(join(project, "service.test.ts"), "export const privateValue = 'never transmit me';\n");

  writeFileSync(join(configDir, "config.json"), JSON.stringify({
    api_key: "qf_test_key",
    api_url: "https://capture.invalid",
  }));
  const fakeCurl = join(binDir, "curl");
  writeFileSync(fakeCurl, `#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-d" ]; then
    shift
    printf '%s' "$1" > "$QF_CAPTURE_FILE"
  fi
  shift
done
printf '204'
`);
  chmodSync(fakeCurl, 0o755);

  const env = {
    ...process.env,
    HOME: temp,
    PATH: `${binDir}:${process.env.PATH}`,
    QF_CAPTURE_FILE: captureFile,
  };
  const hook = join(root, "hooks/track-session.sh");
  const event = {
    hook_event_name: "UserPromptSubmit",
    cwd: project,
    session_id: "claude-context-test",
    file_path: join(project, "service.test.ts"),
  };
  execFileSync(hook, [], { env, input: JSON.stringify(event), stdio: ["pipe", "ignore", "inherit"] });
  const payload = JSON.parse(readFileSync(captureFile, "utf8"));
  const heartbeat = payload.heartbeats[0];

  assert.match(heartbeat.head_sha, /^[a-f0-9]{40}$/);
  assert.match(heartbeat.repo_fingerprint, /^[a-f0-9]{64}$/);
  assert.equal(heartbeat.activity_kind, "test");
  assert.equal(heartbeat.changed_file_count, 0, "untracked files are deliberately excluded from the count");
  assert.equal(payload.client.plugin_version, "1.6.2");
  for (const forbidden of ["source_code", "diff", "prompt", "command", "file_path", "remote_url"]) {
    assert.equal(forbidden in heartbeat, false, `heartbeat must not include ${forbidden}`);
  }
  assert.ok(!JSON.stringify(payload).includes("privateValue"));

  execFileSync(hook, [], {
    env,
    input: JSON.stringify({ ...event, hook_event_name: "SessionEnd" }),
    stdio: ["pipe", "ignore", "inherit"],
  });
  console.log("Claude tracker privacy-minimized context regression passed.");
} finally {
  rmSync(temp, { recursive: true, force: true });
}
