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

## November 2026 bezel packs: what we added and what waits

> **Author:** Claude Code (coder)
> **Date:** 2026-11-15
> **Status:** decided-by-user where marked; the rest is proposed-by-agent

- **Add the two new packs** (decided-by-user, Charlie answered "a" when offered: add the iPad mini (A20 Pro) and PROLED MacBook Pros, and diff the Duo re-upload). Landed in `a8566c9`.
- **Skip the Duo "Inner Partially Open" view** (proposed-by-agent). Apple's Oct 14 re-upload only adds those PSDs, and the folded lower half is drawn in perspective, so a flat screenshot can't be composited onto it. The existing Duo PNGs are pixel-identical to ours.
- **Clear the iPad mini (A20 Pro) hole ring** (proposed-by-agent). Details in `docs/architecture.md`.
- **The PROLED capture-size tables hold only the native size for now** (proposed-by-agent). Apple hasn't published the display-zoom presets, and `testCaptureSizeTablesAreConsistentWithBezels` requires a table, so I listed the one size every earlier MacBook Pro offers. That size is inferred, not checked on hardware.
- **The next build waits for hardware numbers** (decided-by-user, Charlie: "I'll wait until someone can run the script on a PROLED MacBook Pro so we can get those numbers into the app before we cut another build"). The tool is `Scripts/display-modes.js` (runs through `osascript`, so nothing to install). Charlie also chose to wait for a friend rather than ask on a forum ("b").
- **Bezelbub joins the workspace session-start App Review check** (decided-by-user, Charlie answered "a"). 3.5.0 had been live since Oct 19 (iOS) and Oct 23 (macOS) while our status lines still said "waiting", because bezelbub wasn't on that list.
- **16" PROLED capture sizes from hardware** (proposed-by-agent, 2026-11-15). A Bezelbub user ran `Scripts/display-modes.js` on a Mac17,10 (native 3472×2266, macOS 27.2.1) and Charlie passed on the output. I kept the five sizes on the panel's own aspect (4128×2694, 3472×2266, 2994×1954, 2632×1718, 2332×1522) and dropped the seven 16:10 island-hidden modes, per the 2026-09-11 notch decision. The 14" table is still the inferred native size only.
- **Cut 3.6.0 without the 14" PROLED numbers** (decided-by-user 2026-11-15, Charlie answered "b" when asked whether to wait for the 14" or cut now). Other 14" sizes match by aspect ratio.
- **The MCP server's version mirrors the CLI's** (decided-by-user 2026-11-15, Charlie: "I think the MCP version should mirror the CLI version", after asking for meaningful bumps and why MCP was under 1.0). So MCP went from 0.4.0 to 1.6.0 alongside CLI 1.6.0. Nothing had recorded a reason for staying under 1.0; it started at 0.1.0 in July and was never declared stable.
