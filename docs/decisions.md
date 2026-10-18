# Bezelbub decisions

Decisions and their rationale. Each entry carries its own provenance stamp. Older settled decisions are summarized in `CLAUDE.md` ("Settled") with rationale in `docs/architecture.md`.

## Padding around the framed device (3.5.0, CLI 1.5.0, MCP 0.4.0)

> **Author:** Claude Code (planner/coder)
> **Date:** 2026-10-18
> **Status:** decided-by-user for scope (below); the mechanics are proposed-by-agent and were approved by Charlie as a plan ("approved")

Charlie asked for it: "we should allow users to specify a certain amount of padding in the generated image. sometimes screenshots look better with some padding."

Decided by Charlie (his answers "1a 2a 3a" to the options I offered):
- Every surface gets it: engine, CLI, MCP, and both apps.
- The apps also get a background color for screenshots, so padding can be colored. Before this, only video had one.
- Padding applies to video as well as images.

Proposed by me and approved as part of the plan:
- Padding is a percentage of the bezel's longer side, the same on every side, because bezel art is thousands of pixels across and is rescaled later, so a pixel value would mean something different on every device. The CLI and MCP also accept exact pixels (`120px`).
- Padding is applied before `--output-size`, so the requested size is the final size.
- Percent is capped at 100% so a typo can't make a huge canvas.
- The apps offer presets (None, 5%, 10%, 15%, 20%, or 25%). Padding is remembered across launches, and the image background is session-only, like the video background. Screenshots stay transparent by default.
- The share extension keeps padding at zero: our settings can't reach it without an app group.
- The MCP `padding` field is optional, so it adds to the schema and changes no existing type (rule in `CLAUDE.md`).

Release order (proposed-by-agent, followed 2026-10-18): the CLI ships before the MCP server, because MCP passes `padding` through as `--padding`, which CLI 1.4.0 rejects.
