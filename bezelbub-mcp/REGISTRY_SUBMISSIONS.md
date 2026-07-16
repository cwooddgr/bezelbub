# Listing bezelbub-mcp in MCP directories

> **Author:** Claude Code (coder)
> **Date:** 2026-07-15
> **Status:** proposed-by-agent
>
> Processes below were verified against the live sources linked in each
> section on 2026-07-15. Two items could not be fully verified and are
> flagged inline. Nothing here has been executed — all four listings require
> the package to be published to npm first, which has not happened.

Prerequisite for everything below: publish to npm —

```sh
cd bezelbub-mcp
npm publish --access public
```

The `mcpName` field the official registry requires (`io.github.cwooddgr/bezelbub-mcp`)
is already in `package.json`.

## 1. Official MCP Registry (registry.modelcontextprotocol.io)

Verified against the live quickstart: <https://modelcontextprotocol.io/registry/quickstart>
and <https://github.com/modelcontextprotocol/registry>. The registry is in
preview (API frozen at v0.1). There is no human review queue — publishing is
schema validation plus namespace authentication.

How ownership is proven, twice over:
- **npm package ownership**: the registry checks that the npm package's
  `mcpName` field matches the `server.json` `name`. Already in place.
- **Namespace ownership**: `mcp-publisher login github` runs a GitHub device
  flow; logging in as `cwooddgr` grants publish rights to `io.github.cwooddgr/*`
  only.

Steps:

```sh
brew install mcp-publisher
cd bezelbub-mcp
mcp-publisher init          # generates server.json; edit to taste
mcp-publisher login github  # device flow at github.com/login/device
mcp-publisher publish
```

`server.json` shape for an npm stdio server (current schema, verified):

```json
{
  "$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
  "name": "io.github.cwooddgr/bezelbub-mcp",
  "description": "Frame screenshots and screen recordings in Apple device bezels (device mockups). macOS only.",
  "repository": { "url": "https://github.com/cwooddgr/bezelbub", "source": "github" },
  "version": "0.1.0",
  "packages": [
    {
      "registryType": "npm",
      "identifier": "@dgrlabs/bezelbub-mcp",
      "version": "0.1.0",
      "transport": { "type": "stdio" }
    }
  ]
}
```

Verify afterwards:

```sh
curl "https://registry.modelcontextprotocol.io/v0.1/servers?search=io.github.cwooddgr/bezelbub-mcp"
```

Known failure modes (documented in the quickstart): mismatched `mcpName` →
"Registry validation failed for package"; wrong GitHub account → "You do not
have permission to publish this server."

## 2. Smithery (smithery.ai)

Verified against <https://smithery.ai/docs/build/publish.md>.

- Submit via the web UI at <https://smithery.ai/new> (GitHub login), or the
  CLI: `smithery mcp publish`.
- Smithery's current release types are: externally hosted (public Streamable
  HTTP endpoint), **local/stdio as a pre-built `.mcpb` bundle**, or a CLI
  publish with a custom config schema. A plain npm package is *not* one of the
  listed release types — for us the natural path is uploading the `.mcpb`
  bundle (`npx @anthropic-ai/mcpb pack` in this directory).
- *Unverified*: whether the legacy `smithery.yaml` still plays any role — the
  current publish docs don't mention it; treat it as not required.

## 3. Glama (glama.ai)

Verified against <https://glama.ai/mcp/servers> and a live listing page.

- Listing is primarily **automatic**: Glama aggregates from the official
  `modelcontextprotocol/servers` repo and the popular "awesome MCP" lists,
  refreshed roughly every 3 hours. An npm-published server with a public
  GitHub repo is likely to be indexed without action.
- Manual add: the directory page has an "Add Server" control taking a GitHub
  repository URL. *Unverified*: its exact form URL (appears to sit behind
  login/JS; could not be fetched directly).
- Once listed, **claim** the server (button on the listing page: "If you are
  the server author, claim this server…") via GitHub ownership to unlock the
  admin panel at `/mcp/servers/<owner>/<name>/admin` — unclaimed servers have
  limited discoverability.
- Note: the bezelbub GitHub repo would need to be public for Glama to index
  the server directory within it.

## 4. PulseMCP (pulsemcp.com)

Verified against <https://www.pulsemcp.com/submit>.

- PulseMCP **ingests the official MCP registry weekly** — publishing there
  (step 1) covers PulseMCP automatically within about a week.
- Fallback: the submit form at <https://www.pulsemcp.com/submit> takes a URL
  ("a GitHub repository, a subfolder of a repository, or a standalone
  website"); for edits or a missing listing after a week, email
  <hello@pulsemcp.com>.

## Recommended order

1. `npm publish --access public`
2. Official registry via `mcp-publisher` (GitHub device-flow auth)
3. PulseMCP: nothing to do — follows the official registry within ~a week
4. Glama: wait for auto-indexing (or use "Add Server"), then claim the listing
5. Smithery: pack a `.mcpb` bundle and submit at smithery.ai/new
