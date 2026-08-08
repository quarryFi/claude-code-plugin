import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { extname, join, relative } from "node:path";

const root = new URL("../", import.meta.url);
const retiredHostname = "quarryfi.smashedstudiosllc.workers.dev";
const checkedExtensions = new Set([".json", ".md", ".sh"]);
const ignoredDirectories = new Set([".git", "tests"]);

function walk(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory() && ignoredDirectories.has(entry.name)) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      walk(path);
      continue;
    }
    if (!checkedExtensions.has(extname(entry.name))) continue;
    const contents = readFileSync(path, "utf8");
    assert.ok(!contents.includes(retiredHostname), `${relative(root.pathname, path)} must not use the retired workers.dev hostname`);
  }
}

walk(root.pathname);

for (const script of ["setup.sh", "hooks/check-config.sh", "hooks/track-session.sh"]) {
  execFileSync("bash", ["-n", join(root.pathname, script)], { stdio: "inherit" });
}

console.log("Claude tracker production-hostname regression passed.");
