import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = new URL("../", import.meta.url).pathname;
const temp = mkdtempSync(join(tmpdir(), "quarryfi-claude-setup-"));
const binDir = join(temp, "bin");
const requestFile = join(temp, "request.txt");
const apiKey = `qf_${"a".repeat(40)}`;

try {
  mkdirSync(binDir, { recursive: true });
  const fakeCurl = join(binDir, "curl");
  writeFileSync(fakeCurl, `#!/bin/sh
printf '%s\n' "$@" > "$QF_REQUEST_FILE"
printf '200'
`);
  chmodSync(fakeCurl, 0o755);

  const result = spawnSync("bash", [join(root, "setup.sh")], {
    env: {
      ...process.env,
      HOME: temp,
      PATH: `${binDir}:${process.env.PATH}`,
      QF_REQUEST_FILE: requestFile,
    },
    input: `Acme "Research"\n${apiKey}\n/tmp/project-one, /tmp/project-two\nn\n`,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.ok(!result.stdout.includes(apiKey), "setup output must not echo the seat key");
  assert.ok(!result.stderr.includes(apiKey), "setup errors must not echo the seat key");

  const configPath = join(temp, ".quarryfi", "config.json");
  const config = JSON.parse(readFileSync(configPath, "utf8"));
  assert.equal(config.profiles[0].name, 'Acme "Research"');
  assert.equal(config.profiles[0].api_key, apiKey);
  assert.equal(config.profiles[0].api_url, "https://quarryfi.com");
  assert.deepEqual(config.profiles[0].projects, ["/tmp/project-one", "/tmp/project-two"]);
  assert.equal(statSync(configPath).mode & 0o777, 0o600);

  const request = readFileSync(requestFile, "utf8");
  assert.match(request, /https:\/\/quarryfi\.com\/api\/heartbeat/);
  assert.match(request, /--proto\n=https/);

  console.log("Claude tracker private setup regression passed.");
} finally {
  rmSync(temp, { recursive: true, force: true });
}
