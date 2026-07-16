#!/usr/bin/env node
/**
 * End-to-end smoke test: starts the built server over stdio using the MCP
 * SDK's own client, then exercises initialize, tools/list, and tools/call
 * against the real `bezelbub` CLI.
 *
 * Requires the bezelbub CLI (brew install cwooddgr/tap/bezelbub, or set
 * BEZELBUB_CLI_PATH). Generates its own test PNG — no fixtures needed.
 */

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { deflateSync } from "node:zlib";
import { mkdtempSync, writeFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));

let failures = 0;
function check(name, condition, detail = "") {
  const mark = condition ? "ok " : "FAIL";
  console.log(`${mark} - ${name}${condition || !detail ? "" : ` — ${detail}`}`);
  if (!condition) failures += 1;
}

/** Write a solid-color RGBA PNG (pure stdlib). */
function writePng(path, width, height, [r, g, b, a]) {
  const crcTable = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crcTable[n] = c >>> 0;
  }
  const crc32 = (buf) => {
    let c = 0xffffffff;
    for (const byte of buf) c = crcTable[(c ^ byte) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const out = Buffer.alloc(body.length + 8);
    out.writeUInt32BE(data.length, 0);
    body.copy(out, 4);
    out.writeUInt32BE(crc32(body), body.length + 4);
    return out;
  };
  const row = Buffer.concat([
    Buffer.from([0]),
    Buffer.from(Array(width).fill([r, g, b, a]).flat()),
  ]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr.set([8, 6, 0, 0, 0], 8);
  writeFileSync(
    path,
    Buffer.concat([
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      chunk("IHDR", ihdr),
      chunk("IDAT", deflateSync(Buffer.concat(Array(height).fill(row)))),
      chunk("IEND", Buffer.alloc(0)),
    ])
  );
}

const workDir = mkdtempSync(join(tmpdir(), "bezelbub-mcp-e2e-"));
const shot = join(workDir, "shot.png");
writePng(shot, 1206, 2622, [46, 110, 240, 255]); // iPhone 17 / 17 Pro / 16 Pro size

const transport = new StdioClientTransport({
  command: process.execPath,
  args: [join(root, "dist", "index.js")],
});
const client = new Client({ name: "bezelbub-mcp-e2e", version: "0.0.0" });

try {
  await client.connect(transport); // performs MCP initialize
  check("initialize handshake", true);

  const { tools } = await client.listTools();
  const names = tools.map((t) => t.name).sort();
  check(
    "tools/list exposes frame_image, frame_video, list_devices",
    JSON.stringify(names) ===
      JSON.stringify(["frame_image", "frame_video", "list_devices"]),
    `got ${names.join(", ")}`
  );

  // 1. list_devices with dimensions → matches include iphone17pro
  const devices = await client.callTool({
    name: "list_devices",
    arguments: { dimensions: "1206x2622" },
  });
  const devJson = JSON.parse(devices.content[0].text);
  check(
    "list_devices matches 1206x2622 to iphone17pro",
    !devices.isError &&
      devJson.matches.some((d) => d.id === "iphone17pro"),
    devices.content[0].text.slice(0, 200)
  );

  // 2. frame_image happy path → framed PNG exists on disk
  const framedPath = join(workDir, "framed.png");
  const framed = await client.callTool({
    name: "frame_image",
    arguments: {
      input_path: shot,
      device: "iphone17pro",
      output_path: framedPath,
    },
  });
  const framedJson = framed.isError ? {} : JSON.parse(framed.content[0].text);
  check(
    "frame_image returns success JSON",
    !framed.isError &&
      framedJson.kind === "image" &&
      framedJson.device === "iphone17pro",
    framed.content[0].text.slice(0, 300)
  );
  check("framed PNG written to disk", existsSync(framedPath));

  // 3. ambiguous device → isError with candidate list (CLI exit 2)
  const ambiguous = await client.callTool({
    name: "frame_image",
    arguments: { input_path: shot },
  });
  check(
    "ambiguous device maps to tool error with candidates",
    ambiguous.isError === true &&
      ambiguous.content[0].text.includes("iphone17pro") &&
      ambiguous.content[0].text.includes("code 2"),
    ambiguous.content[0].text.slice(0, 200)
  );

  // 4. unknown color → isError listing valid colors (CLI exit 3)
  const badColor = await client.callTool({
    name: "frame_image",
    arguments: { input_path: shot, device: "iphone17pro", color: "Chartreuse" },
  });
  check(
    "unknown color maps to tool error with valid colors",
    badColor.isError === true &&
      badColor.content[0].text.includes("code 3") &&
      badColor.content[0].text.includes("Cosmic Orange"),
    badColor.content[0].text.slice(0, 200)
  );

  // 5. unreadable input → isError (CLI exit 4)
  const missing = await client.callTool({
    name: "frame_image",
    arguments: { input_path: join(workDir, "nope.png"), device: "iphone17pro" },
  });
  check(
    "missing input maps to tool error",
    missing.isError === true,
    missing.content[0].text.slice(0, 200)
  );
} finally {
  await client.close().catch(() => {});
  rmSync(workDir, { recursive: true, force: true });
}

console.log(failures === 0 ? "\nAll e2e checks passed." : `\n${failures} check(s) FAILED.`);
process.exit(failures === 0 ? 0 : 1);
