#!/usr/bin/env node
/**
 * Update-notice tests.
 *
 * 1. Pure version comparison.
 * 2. Throttling of the on-demand check (pure, with an injected clock).
 * 3. End to end: a local fake npm registry reports a newer version. The
 *    first tool call triggers the background lookup, the second call carries
 *    the reconnect notice, and the registry was hit once (error results
 *    here, so no bezelbub CLI is needed). A server with the check disabled
 *    never contacts the registry and appends nothing.
 */

import { createServer } from "node:http";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const { isNewerVersion, formatUpdateNotice, updateCheckDisabled, configureUpdateCheck, maybeCheckForUpdate } = await import(
  join(root, "dist", "update-check.js")
);

let failures = 0;
function check(name, condition, detail = "") {
  console.log(`${condition ? "ok " : "FAIL"} - ${name}${condition || !detail ? "" : ` (${detail})`}`);
  if (!condition) failures += 1;
}

// 1. Version comparison.
check("0.3.0 is newer than 0.2.1", isNewerVersion("0.3.0", "0.2.1"));
check("1.0.0 is newer than 0.9.9", isNewerVersion("1.0.0", "0.9.9"));
check("0.2.10 is newer than 0.2.9", isNewerVersion("0.2.10", "0.2.9"));
check("same version is not newer", !isNewerVersion("0.2.1", "0.2.1"));
check("older is not newer", !isNewerVersion("0.2.0", "0.2.1"));
check("prerelease tag is ignored", isNewerVersion("0.3.0-beta.1", "0.2.1"));
check("garbage is not newer", !isNewerVersion("latest", "0.2.1"));
check("notice names both versions", formatUpdateNotice("0.2.1", "0.3.0").includes("0.3.0") &&
  formatUpdateNotice("0.2.1", "0.3.0").includes("0.2.1"));
check("opt-out env var: unset", !updateCheckDisabled({}));
check("opt-out env var: 0", !updateCheckDisabled({ BEZELBUB_NO_UPDATE_CHECK: "0" }));
check("opt-out env var: 1", updateCheckDisabled({ BEZELBUB_NO_UPDATE_CHECK: "1" }));
check("opt-out env var: true", updateCheckDisabled({ BEZELBUB_NO_UPDATE_CHECK: "true" }));

// 2. Fake registry + throttling.
let hits = 0;
const registry = createServer((req, res) => {
  hits += 1;
  res.setHeader("content-type", "application/json");
  res.end(JSON.stringify({ name: "@dgr_labs/bezelbub-mcp", version: "99.0.0" }));
});
await new Promise((resolve) => registry.listen(0, "127.0.0.1", resolve));
const registryUrl = `http://127.0.0.1:${registry.address().port}/latest`;

configureUpdateCheck("0.0.1", { BEZELBUB_UPDATE_CHECK_URL: registryUrl });
const t0 = 1_000_000_000_000;
await maybeCheckForUpdate(t0);
await maybeCheckForUpdate(t0 + 1000);
await maybeCheckForUpdate(t0 + 5 * 60 * 60 * 1000);
check("in-process: calls within the interval share one lookup", hits === 1, `hits=${hits}`);
await maybeCheckForUpdate(t0 + 7 * 60 * 60 * 1000);
check("in-process: a call after the interval looks again", hits === 2, `hits=${hits}`);
configureUpdateCheck("0.0.1", { BEZELBUB_UPDATE_CHECK_URL: registryUrl, BEZELBUB_NO_UPDATE_CHECK: "1" });
await maybeCheckForUpdate(t0 + 20 * 60 * 60 * 1000);
check("in-process: disabled means no lookup", hits === 2, `hits=${hits}`);
hits = 0;

async function callWithEnv(env) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [join(root, "dist", "index.js")],
    env: { ...process.env, BEZELBUB_CLI_PATH: "/nonexistent/bezelbub", ...env },
  });
  const client = new Client({ name: "update-check-test", version: "0.0.0" });
  try {
    await client.connect(transport);
    const hitsAtConnect = hits;
    // The first call starts the background lookup; give it a moment to land,
    // then the second call should carry the notice.
    const first = await client.callTool({ name: "list_devices", arguments: {} });
    await new Promise((resolve) => setTimeout(resolve, 500));
    const second = await client.callTool({ name: "list_devices", arguments: {} });
    return { first, second, hitsAtConnect };
  } finally {
    await client.close().catch(() => {});
  }
}

try {
  const { first, second: stale, hitsAtConnect } = await callWithEnv({ BEZELBUB_UPDATE_CHECK_URL: registryUrl });
  check("no lookup before the first tool call", hitsAtConnect === 0, `hits=${hitsAtConnect}`);
  check("two calls produce one registry hit", hits === 1, `hits=${hits}`);
  const isNotice = (c) => c.type === "text" && c.text.startsWith("Note from bezelbub-mcp");
  check("first call (lookup still pending) has no notice", !first.content.some(isNotice));
  check("result is still an error (no CLI)", stale.isError === true);
  const notice = stale.content.find(isNotice);
  check("stale session gets the reconnect notice", Boolean(notice), JSON.stringify(stale.content).slice(0, 300));
  check("notice is the last content block", stale.content.at(-1) === notice);
  check("notice names 99.0.0 and says to reconnect",
    Boolean(notice) && notice.text.includes("99.0.0") && /reconnect/i.test(notice.text));

  const hitsBefore = hits;
  const { second: quiet } = await callWithEnv({ BEZELBUB_UPDATE_CHECK_URL: registryUrl, BEZELBUB_NO_UPDATE_CHECK: "1" });
  check("opt-out: registry not consulted", hits === hitsBefore, `hits=${hits}`);
  check("opt-out: no notice appended", !quiet.content.some(isNotice));
} finally {
  registry.close();
}

console.log(failures === 0 ? "\nAll update-check checks passed." : `\n${failures} check(s) FAILED.`);
process.exit(failures === 0 ? 0 : 1);
