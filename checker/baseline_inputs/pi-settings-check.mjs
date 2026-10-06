// Real target-side Pi SDK check, not a JSON-file-exists test.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import assert from "node:assert/strict";
import { SettingsManager } from "/opt/pi/package/dist/index.js";

const templates = "/opt/cybertiel/pi-config";
const runtime = process.env.PI_CODING_AGENT_DIR;
if (!runtime || !runtime.startsWith("/home/node/.pi-run.")) throw new Error("not a fresh private Pi runtime");
const expected = JSON.parse(fs.readFileSync(path.join(templates, "settings.json"), "utf8"));
const manager = SettingsManager.create(process.cwd(), runtime, { projectTrusted: false });
if (manager.drainErrors().length) throw new Error("settings read/lock failed");
await manager.reload();
if (manager.drainErrors().length) throw new Error("settings reload/lock failed");
const effective = manager.getSettings();
for (const [key, value] of Object.entries(expected)) assert.deepEqual(effective[key], value, `Pi ignored setting ${key}`);
assert.equal(manager.isProjectTrusted(), false);
assert.equal(effective.httpIdleTimeoutMs, 7200000);
assert.equal(effective.retry.provider.timeoutMs, 7200000);
assert.deepEqual(effective.defaultTools, ["read", "bash", "edit", "write", "grep", "find", "ls"]);
const expectedModel = fs.readFileSync(path.join(templates, "models.json"));
assert.equal(Buffer.compare(expectedModel, fs.readFileSync(path.join(runtime, "models.json"))), 0);
console.log(JSON.stringify({ status: "PASS", actual_pi_sdk_settings_checked: true,
  templates_immutable: true, ephemeral_runtime: true, project_trusted: false,
  settings_sha256: crypto.createHash("sha256").update(fs.readFileSync(path.join(runtime, "settings.json"))).digest("hex") }));
