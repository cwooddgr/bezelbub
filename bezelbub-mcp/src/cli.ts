/**
 * Resolution and execution of the `bezelbub` CLI binary.
 *
 * The MCP server is a thin adapter: every tool call shells out to
 * `bezelbub` in `--json` mode and maps its exit codes / stderr to
 * MCP tool errors.
 */

import { execFile } from "node:child_process";
import { accessSync, constants } from "node:fs";
import { delimiter, join } from "node:path";

const BREW_HINT =
  "Install it with: brew install cwooddgr/tap/bezelbub — or point the " +
  "BEZELBUB_CLI_PATH environment variable at a bezelbub binary.";

/** Directories checked even when they are missing from PATH (GUI apps like
 *  Claude Desktop launch MCP servers with a minimal PATH that often lacks
 *  the Homebrew bin directory). */
const FALLBACK_DIRS = ["/opt/homebrew/bin", "/usr/local/bin"];

/** Exit-code meanings documented in `bezelbub --help`. */
const EXIT_MEANINGS: Record<number, string> = {
  1: "invalid flag value",
  2: "unknown, ambiguous, or undetectable device",
  3: "unknown color",
  4: "input image or video unreadable",
  5: "compositing or video export failed",
  6: "output could not be written",
  7: "WebM conversion failed (ffmpeg missing from PATH, or ffmpeg errored)",
  64: "malformed arguments",
};

let cachedBinary: string | undefined;

function isExecutable(path: string): boolean {
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

/**
 * Locate the bezelbub binary.
 * Order: BEZELBUB_CLI_PATH env var → `bezelbub` on PATH (plus the standard
 * Homebrew bin dirs) → error telling the user how to install it.
 */
export function resolveBinary(): string {
  if (process.platform !== "darwin") {
    throw new Error(
      "Bezelbub is macOS-only: the bezelbub CLI is a macOS-native binary " +
        "(Core Graphics / AVFoundation). Run this MCP server on a Mac."
    );
  }
  if (cachedBinary) return cachedBinary;

  const envPath = process.env.BEZELBUB_CLI_PATH?.trim();
  // "${..." guards against an MCPB host passing through an unresolved
  // ${user_config...} placeholder when the user left the setting blank.
  if (envPath && !envPath.startsWith("${")) {
    if (!isExecutable(envPath)) {
      throw new Error(
        `BEZELBUB_CLI_PATH is set to "${envPath}" but no executable exists there. ` +
          BREW_HINT
      );
    }
    cachedBinary = envPath;
    return envPath;
  }

  const pathDirs = (process.env.PATH ?? "").split(delimiter).filter(Boolean);
  for (const dir of [...pathDirs, ...FALLBACK_DIRS]) {
    const candidate = join(dir, "bezelbub");
    if (isExecutable(candidate)) {
      cachedBinary = candidate;
      return candidate;
    }
  }

  throw new Error("The bezelbub CLI was not found on PATH. " + BREW_HINT);
}

export interface CliResult {
  /** Parsed stdout when it is valid JSON, else the raw stdout string. */
  json: unknown;
  stdout: string;
}

/**
 * Run `bezelbub <args> --json`. Resolves with parsed JSON on success;
 * throws an Error whose message carries the CLI's stderr (which already
 * contains concrete suggestions — valid ids, nearest devices, etc.) plus
 * the documented meaning of the exit code.
 */
export function runBezelbub(
  args: string[],
  timeoutMs = Number(process.env.BEZELBUB_TIMEOUT_MS) || 10 * 60 * 1000
): Promise<CliResult> {
  const binary = resolveBinary();
  return new Promise((resolve, reject) => {
    execFile(
      binary,
      [...args, "--json"],
      { timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024 },
      (error, stdout, stderr) => {
        if (!error) {
          let json: unknown = stdout;
          try {
            json = JSON.parse(stdout);
          } catch {
            /* leave raw */
          }
          resolve({ json, stdout });
          return;
        }

        const anyErr = error as NodeJS.ErrnoException & {
          code?: number | string;
          killed?: boolean;
          signal?: string | null;
        };
        if (anyErr.code === "ENOENT") {
          reject(
            new Error(`Could not execute bezelbub at "${binary}". ${BREW_HINT}`)
          );
          return;
        }
        if (anyErr.killed || anyErr.signal) {
          reject(
            new Error(
              `bezelbub timed out after ${Math.round(timeoutMs / 1000)}s ` +
                `(signal ${anyErr.signal}). Long video exports may need a larger ` +
                `timeout: set the BEZELBUB_TIMEOUT_MS environment variable.`
            )
          );
          return;
        }

        const code = typeof anyErr.code === "number" ? anyErr.code : undefined;
        const meaning =
          code !== undefined && EXIT_MEANINGS[code]
            ? ` (${EXIT_MEANINGS[code]})`
            : "";
        const detail = (stderr || stdout || "no error output").trim();
        reject(new Error(`bezelbub exited with code ${code}${meaning}:\n${detail}`));
      }
    );
  });
}
