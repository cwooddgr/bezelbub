#!/usr/bin/env node
/**
 * Build the .mcpb bundle Smithery wants.
 *
 * Smithery's publish API builds a "server card" from the bundle's
 * manifest.json and rejects tool entries that lack an `inputSchema`
 * ("Invalid input: expected object, received undefined", once per tool).
 * The MCPB manifest schema, on the other hand, rejects `inputSchema` on
 * tool entries. So: pack a spec-clean bundle with `mcpb pack`, then swap in a
 * manifest whose tools carry the real input schemas, read from the running
 * server. The repo's manifest.json stays clean.
 *
 * Output: bezelbub-mcp-smithery.mcpb (gitignored). Publish with
 *   npx @smithery/cli mcp publish ./bezelbub-mcp-smithery.mcpb -n charlie-wood/bezelbub-mcp
 */
import { execSync } from "node:child_process";
import { readFileSync, writeFileSync, rmSync, mkdtempSync, copyFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const clean = join(root, "bezelbub-mcp.mcpb");
const out = join(root, "bezelbub-mcp-smithery.mcpb");
const sh = (cmd) => execSync(cmd, { cwd: root, stdio: "inherit" });

// 1. Build, then pack against production deps only (otherwise TypeScript
//    from devDependencies lands in the bundle and triples its size).
sh("npm run build");
sh("npm ci --omit=dev --silent");
try {
  rmSync(clean, { force: true });
  sh(`npx --yes @anthropic-ai/mcpb@2.1.2 pack . ${JSON.stringify(clean)}`);
} finally {
  sh("npm ci --silent");
}

// 2. Ask the built server for its tools and graft the input schemas onto
//    the manifest's tool entries.
const client = new Client({ name: "build-smithery-bundle", version: "0" });
await client.connect(new StdioClientTransport({ command: "node", args: [join(root, "dist/index.js")] }));
const { tools } = await client.listTools();
await client.close();
const byName = Object.fromEntries(tools.map((t) => [t.name, t]));

const manifest = JSON.parse(readFileSync(join(root, "manifest.json"), "utf8"));
for (const tool of manifest.tools ?? []) {
  const live = byName[tool.name];
  if (!live) throw new Error(`manifest lists tool ${tool.name} but the server does not expose it`);
  tool.inputSchema = live.inputSchema;
}
const missing = tools.filter((t) => !(manifest.tools ?? []).some((m) => m.name === t.name));
if (missing.length) throw new Error(`server exposes tools missing from manifest.json: ${missing.map((t) => t.name).join(", ")}`);

// 3. Replace manifest.json inside a copy of the archive.
const work = mkdtempSync(join(tmpdir(), "smithery-bundle-"));
writeFileSync(join(work, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
copyFileSync(clean, out);
execSync(`zip -q ${JSON.stringify(out)} manifest.json`, { cwd: work, stdio: "inherit" });
rmSync(work, { recursive: true, force: true });
console.log(`wrote ${out} (${tools.length} tools with input schemas)`);
