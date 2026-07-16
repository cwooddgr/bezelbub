#!/usr/bin/env node
/**
 * bezelbub-mcp — MCP server wrapping the `bezelbub` CLI.
 *
 * Composites Apple device bezels onto screenshots and screen recordings.
 * macOS-only (the CLI is a macOS-native binary). Every tool shells out to
 * `bezelbub --json`; see src/cli.ts for binary resolution and error mapping.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { resolve as resolvePath } from "node:path";
import { runBezelbub } from "./cli.js";

const SERVER_VERSION = "0.1.0";

const server = new McpServer({
  name: "bezelbub",
  version: SERVER_VERSION,
});

/** Shared framing options (image + video). */
const framingShape = {
  input_path: z
    .string()
    .describe(
      "Absolute path to the input file. Relative paths are resolved against " +
        "the MCP server's working directory, so prefer absolute paths."
    ),
  device: z
    .string()
    .optional()
    .describe(
      "Device id, e.g. 'iphone17pro', 'ipadpro13m5', 'macbookpro14'. Omit to " +
        "auto-detect from the input's pixel size; if several devices share " +
        "that resolution the error lists the candidates. Use list_devices " +
        "for valid ids."
    ),
  color: z
    .string()
    .optional()
    .describe(
      "Bezel color name, e.g. 'Silver', 'Cosmic Orange'. Defaults to the " +
        "device's default color. Invalid colors error with the valid list."
    ),
  orientation: z
    .enum(["portrait", "landscape", "auto"])
    .optional()
    .describe("Bezel orientation. Default 'auto' (inferred from the input)."),
  output_size: z
    .string()
    .optional()
    .describe(
      "Scale the output, preserving the bezel's aspect ratio: a width " +
        "('1920'), an exact size ('1920x988'), or a percentage of native " +
        "size ('50%'). Default: the bezel's native size."
    ),
  output_path: z
    .string()
    .optional()
    .describe(
      "Absolute path for the output file. Defaults to '<input>-framed.png' " +
        "(image) or '<input>-framed.mp4' / '.mov' (video) beside the input."
    ),
};

type FramingArgs = {
  input_path: string;
  device?: string;
  color?: string;
  orientation?: "portrait" | "landscape" | "auto";
  output_size?: string;
  output_path?: string;
};

function framingFlags(args: FramingArgs): string[] {
  const flags = ["frame", "--input", resolvePath(args.input_path)];
  if (args.device) flags.push("--device", args.device);
  if (args.color) flags.push("--color", args.color);
  if (args.orientation) flags.push("--orientation", args.orientation);
  if (args.output_size) flags.push("--output-size", args.output_size);
  if (args.output_path) flags.push("--output", resolvePath(args.output_path));
  return flags;
}

type ToolResult = {
  content: Array<{ type: "text"; text: string }>;
  isError?: boolean;
};

function ok(json: unknown, stdout: string): ToolResult {
  return {
    content: [
      {
        type: "text",
        text: typeof json === "string" ? stdout : JSON.stringify(json, null, 2),
      },
    ],
  };
}

function fail(error: unknown): ToolResult {
  return {
    content: [
      { type: "text", text: error instanceof Error ? error.message : String(error) },
    ],
    isError: true,
  };
}

server.registerTool(
  "frame_image",
  {
    title: "Frame a screenshot in a device bezel",
    description:
      "Frame a screenshot in an Apple device bezel — i.e. make a device " +
      "mockup: put a screenshot inside a realistic iPhone, iPad, Mac, iMac, " +
      "or Apple TV frame. Use for requests like 'frame this screenshot in an " +
      "iPhone bezel', 'device mockup', 'make this look like it's on an iPad', " +
      "or App Store / marketing imagery. Input: PNG, JPEG, or HEIC file on " +
      "disk. Output: a framed PNG written next to the input (or at " +
      "output_path); the background around the bezel is transparent unless a " +
      "hex color is given. The device is auto-detected from the screenshot's " +
      "pixel size when 'device' is omitted. Returns JSON with the output " +
      "path, device, color, orientation, and final pixel size. macOS only.",
    inputSchema: {
      ...framingShape,
      background: z
        .string()
        .optional()
        .describe(
          "Background fill behind/around the bezel: a hex color like " +
            "'#FFFFFF' or '#RRGGBBAA', or 'transparent'. Default: transparent."
        ),
    },
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
    },
  },
  async (args) => {
    try {
      const flags = framingFlags(args);
      if (args.background) flags.push("--background", args.background);
      const { json, stdout } = await runBezelbub(flags);
      return ok(json, stdout);
    } catch (error) {
      return fail(error);
    }
  }
);

server.registerTool(
  "frame_video",
  {
    title: "Frame a screen recording in a device bezel",
    description:
      "Frame a screen recording (video) in an Apple device bezel — a video " +
      "device mockup: put an iPhone/iPad/Mac screen recording inside a " +
      "realistic device frame, preserving the audio track. Use for requests " +
      "like 'frame this screen recording in an iPhone bezel', 'app demo " +
      "video in a device frame', or 'transparent video with alpha for my " +
      "website'. Input: .mov, .mp4, or .m4v file on disk. Output: a framed " +
      "MP4 (background defaults to black), or — with background " +
      "'transparent' — an HEVC-with-alpha QuickTime .mov whose surroundings " +
      "are truly transparent (plays in Safari and Apple frameworks only; set " +
      "webm=true to also write a VP9/WebM copy for Chrome/Firefox, which " +
      "requires ffmpeg on PATH). Device is auto-detected from the video's " +
      "pixel size when 'device' is omitted. Returns JSON with the output " +
      "path(s) and final pixel size. Long videos can take minutes. macOS only.",
    inputSchema: {
      ...framingShape,
      background: z
        .string()
        .optional()
        .describe(
          "Background fill: a hex color like '#1D1D1F', or 'transparent'. " +
            "Default: black. 'transparent' switches the export to " +
            "HEVC-with-alpha in a QuickTime .mov (Safari/Apple playback only)."
        ),
      webm: z
        .boolean()
        .optional()
        .describe(
          "Also write a VP9/WebM copy of a transparent export for " +
            "Chrome/Firefox playback. Requires background='transparent' and " +
            "ffmpeg on PATH."
        ),
    },
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
    },
  },
  async (args) => {
    try {
      const flags = framingFlags(args);
      if (args.background) flags.push("--background", args.background);
      if (args.webm) flags.push("--webm");
      const { json, stdout } = await runBezelbub(flags);
      return ok(json, stdout);
    } catch (error) {
      return fail(error);
    }
  }
);

server.registerTool(
  "list_devices",
  {
    title: "List device bezels / match a screenshot to devices",
    description:
      "List the Apple device bezels available for framing (iPhones, iPads, " +
      "MacBooks, iMac, Apple TV) with their ids, color options, and screen " +
      "pixel sizes — or find which devices fit a given screenshot, screen " +
      "recording, or WxH pixel size ('which iPhone matches a 1206x2622 " +
      "screenshot?'). With input_path or dimensions, returns {width, height, " +
      "matches, nearest}: 'matches' are exact screen-size fits (empty means " +
      "no device fits; 'nearest' then lists the closest by aspect ratio). " +
      "Without a filter, returns the full device catalog. Use this before " +
      "frame_image/frame_video when the device or color is ambiguous. " +
      "macOS only.",
    inputSchema: {
      input_path: z
        .string()
        .optional()
        .describe(
          "Absolute path to a screenshot or video: filters the list to " +
            "devices whose screen matches its pixel size."
        ),
      dimensions: z
        .string()
        .optional()
        .describe(
          "Filter by a pixel size like '1206x2622' (width x height) without " +
            "needing a file on disk. Ignored if input_path is given."
        ),
    },
    annotations: {
      readOnlyHint: true,
      openWorldHint: false,
    },
  },
  async (args) => {
    try {
      const flags = ["devices"];
      if (args.input_path) flags.push("--input", resolvePath(args.input_path));
      else if (args.dimensions) flags.push("--dimensions", args.dimensions);
      const { json, stdout } = await runBezelbub(flags);
      return ok(json, stdout);
    } catch (error) {
      return fail(error);
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error(`bezelbub-mcp ${SERVER_VERSION} ready (stdio)`);
}

main().catch((error) => {
  console.error("bezelbub-mcp fatal:", error);
  process.exit(1);
});
