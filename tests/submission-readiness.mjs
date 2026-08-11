import assert from "node:assert/strict";
import { accessSync, constants, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const root = new URL("../", import.meta.url).pathname;
const read = (path) => readFileSync(join(root, path), "utf8");
const manifest = JSON.parse(read(".claude-plugin/plugin.json"));
const marketplace = JSON.parse(read(".claude-plugin/marketplace.json"));
const hooks = JSON.parse(read("hooks/hooks.json"));
const tracker = read("hooks/track-session.sh");
const readme = read("README.md");
const privacy = read("PRIVACY.md");

assert.equal(manifest.name, "quarryfi-tracker");
assert.equal(manifest.version, "1.6.3");
assert.equal(manifest.license, "Apache-2.0");
assert.equal(manifest.repository, "https://github.com/quarryfi/claude-code-plugin");
assert.equal(manifest.homepage, "https://quarryfi.com");
assert.ok(!/tax credit documentation$/i.test(manifest.description), "description must not imply automatic tax eligibility");

assert.equal(marketplace.plugins.length, 1);
assert.equal(marketplace.plugins[0].name, manifest.name);
assert.equal(marketplace.plugins[0].source, "./");

for (const path of ["LICENSE", "PRIVACY.md", "SECURITY.md", "docs/anthropic-community-submission.md"]) {
  accessSync(join(root, path), constants.R_OK);
}
assert.match(read("LICENSE"), /Apache License/);
assert.match(readme, /PRIVACY\.md/);
assert.match(readme, /SECURITY\.md/);
assert.match(privacy, /https:\/\/quarryfi\.com\/api\/heartbeat/);

assert.match(tracker, /DEFAULT_API_URL="https:\/\/quarryfi\.com"/);
assert.match(tracker, /--proto '=https'/);
assert.match(tracker, /--tlsv1\.2/);
assert.doesNotMatch(tracker, /QUARRYFI_ALLOW_CUSTOM_API_URL/);
assert.ok(!tracker.includes("workers.dev"));

for (const groups of Object.values(hooks.hooks)) {
  for (const group of groups) {
    for (const hook of group.hooks) {
      assert.match(hook.command, /^\$\{CLAUDE_PLUGIN_ROOT\}\//, "hook commands must resolve from the installed plugin root");
    }
  }
}

for (const path of ["setup.sh", "hooks/check-config.sh", "hooks/track-session.sh"]) {
  assert.ok((statSync(join(root, path)).mode & 0o111) !== 0, `${path} must remain executable`);
}

console.log("Claude tracker submission-readiness regression passed.");
