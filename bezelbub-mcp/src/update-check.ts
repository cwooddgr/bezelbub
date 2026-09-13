/**
 * Update-available notice for stale sessions.
 *
 * An MCP client fetches a server's tool list once, when it connects, and a
 * stdio server launched with `npx -y` keeps running the code it started
 * with. So a session opened before a new release keeps the old tool
 * descriptions and schemas for its whole life, and nothing we publish later
 * can reach it. The only thing that does reach it is the text of tool
 * results, which the model reads before every reply.
 *
 * This module checks the npm registry for a newer version and, if one
 * exists, supplies a one-line notice for the server to append to every tool
 * result: which version is available, and that the session has to reconnect
 * the server to get it.
 *
 * The check runs on demand, not on a timer: a tool call triggers it in the
 * background when the last check is older than CHECK_INTERVAL_MS, and the
 * call itself is answered immediately (the next call carries the notice).
 * An idle session makes no requests at all. A check at startup alone would
 * be pointless, since npx has just fetched the latest build at that moment;
 * the release we care about is the one that lands after the session opened.
 * Best-effort, short timeout, silent on failure. Set
 * BEZELBUB_NO_UPDATE_CHECK=1 to turn it off.
 */

const PACKAGE_NAME = "@dgr_labs/bezelbub-mcp";
const REGISTRY_URL = `https://registry.npmjs.org/${PACKAGE_NAME}/latest`;
const FETCH_TIMEOUT_MS = 4_000;
const CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000;

let currentVersion = "0.0.0";
let latestVersion: string | undefined;
let registryUrl: string | undefined; // undefined = check disabled
let lastCheckStarted = -Infinity;
let inFlight: Promise<void> | undefined;

/** True when BEZELBUB_NO_UPDATE_CHECK is set to anything but "", "0", "false". */
export function updateCheckDisabled(env: NodeJS.ProcessEnv = process.env): boolean {
  const value = env.BEZELBUB_NO_UPDATE_CHECK?.trim().toLowerCase();
  return value !== undefined && value !== "" && value !== "0" && value !== "false";
}

/** Numeric major.minor.patch comparison; prerelease tags are ignored. */
export function isNewerVersion(candidate: string, current: string): boolean {
  const parse = (v: string) =>
    v
      .trim()
      .replace(/^v/, "")
      .split(/[-+]/, 1)[0]
      .split(".")
      .map((part) => Number.parseInt(part, 10));
  const a = parse(candidate);
  const b = parse(current);
  if (a.length !== 3 || b.length !== 3 || [...a, ...b].some(Number.isNaN)) return false;
  for (let i = 0; i < 3; i++) {
    if (a[i] !== b[i]) return a[i] > b[i];
  }
  return false;
}

/** The notice text for a stale session, or undefined when up to date. */
export function formatUpdateNotice(current: string, latest: string): string {
  return (
    `Note from bezelbub-mcp: version ${latest} is available and this session ` +
    `is still running ${current}. Tool descriptions and schemas from newer ` +
    `versions only reach a session after the MCP server is reconnected. In ` +
    `Claude Code, run /mcp and choose Reconnect on bezelbub; in Claude Desktop, ` +
    `restart the app. Please mention this to the user.`
  );
}

export function updateNotice(): string | undefined {
  if (!latestVersion) return undefined;
  return formatUpdateNotice(currentVersion, latestVersion);
}

async function fetchLatestVersion(url: string): Promise<string | undefined> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: { accept: "application/json", "user-agent": `bezelbub-mcp/${currentVersion}` },
    });
    if (!response.ok) return undefined;
    const body = (await response.json()) as { version?: unknown };
    return typeof body.version === "string" ? body.version : undefined;
  } catch {
    return undefined;
  } finally {
    clearTimeout(timer);
  }
}

async function checkOnce(url: string): Promise<void> {
  const latest = await fetchLatestVersion(url);
  if (latest && isNewerVersion(latest, currentVersion)) {
    if (latest !== latestVersion) {
      console.error(
        `bezelbub-mcp ${currentVersion}: version ${latest} is available; ` +
          `reconnect the server to pick it up`
      );
    }
    latestVersion = latest;
  }
}

/** Configure the check. Does not perform one. */
export function configureUpdateCheck(version: string, env: NodeJS.ProcessEnv = process.env): void {
  currentVersion = version;
  latestVersion = undefined;
  lastCheckStarted = -Infinity;
  // The URL is overridable for tests only; not documented.
  registryUrl = updateCheckDisabled(env)
    ? undefined
    : env.BEZELBUB_UPDATE_CHECK_URL?.trim() || REGISTRY_URL;
}

/**
 * Called on every tool call. Starts a background check when the last one is
 * older than the interval; never waits for it and never throws. The returned
 * promise is for tests that want to await the lookup.
 */
export function maybeCheckForUpdate(now = Date.now()): Promise<void> {
  if (!registryUrl) return Promise.resolve();
  if (inFlight) return inFlight;
  if (now - lastCheckStarted < CHECK_INTERVAL_MS) return Promise.resolve();
  lastCheckStarted = now;
  inFlight = checkOnce(registryUrl).finally(() => {
    inFlight = undefined;
  });
  return inFlight;
}
