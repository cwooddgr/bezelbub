# Bezelbub — App Store Metadata

## Platform listings

Bezelbub has both a native macOS build and a native iOS/iPadOS build. Apple handles these as **two separate App Store Connect records**, one per platform, even though they share the bundle ID `co.dgrlabs.bezelbub`. The two records can (and should) be linked via **Universal Purchase** in App Store Connect so a single purchase unlocks both platforms.

Practical plan:
- Create a Mac App record with the macOS binary.
- Create an iOS App record with the iOS binary (which includes the Share Extension).
- Enable Universal Purchase linking them.
- Submit both for review at the same time so the listings go live together.

The metadata below is shared; platform-specific tweaks are noted where relevant.

---

## App Name (30 chars max)

```
Bezelbub
```

## Subtitle (30 chars max)

```
Device mockups for screenshots
```

## Promotional Text (170 chars max, editable without resubmission)

```
Now on iPhone, iPad, and Mac with a Share Extension for one-tap framing from any app. Bezelbub v3.1 adds bezels for iPad A16/M5, iPad mini A17 Pro, MacBook M5, and more.
```

## Keywords (100 chars max, comma-separated, no spaces after commas)

```
mockup,bezel,screenshot,device,iphone,ipad,macbook,frame,recording,preview,demo,marketing,design
```

## Description (4000 chars max)

```
Bezelbub wraps your screenshots and screen recordings in real Apple device bezels — the exact art Apple publishes in its Design Resources, matched automatically to whatever you drop in.

Built for developers, designers, product managers, indie makers, and anyone who needs to show their work framed in a real device.

AUTOMATIC DEVICE MATCHING
Drop in a screenshot or screen recording and Bezelbub detects the resolution, picks the right device model, and selects portrait or landscape. No picker, no calibration, no guesswork.

38+ DEVICE MODELS, EVERY COLOR
Complete coverage of modern Apple hardware — iPhone 14 through iPhone 17, iPhone Air, iPad, iPad (A16), iPad mini, iPad mini (A17 Pro), iPad Air M2/M4 in 11" and 13", iPad Pro M4/M5 in 11" and 13", MacBook Air, MacBook Pro, MacBook Neo, iMac 24", and Apple TV 4K — each in every color Apple ships.

VIDEO FRAMING, NOT JUST STILLS
Wrap full screen recordings in device art. MOV, MP4, and M4V. Audio preserved. Rotation, background color selection, and custom export sizing built in. On iOS, a resolution picker with a quality indicator lets you choose the right size for Slack, Twitter/X, or a marketing site.

FRAME FROM ANY APP ON iOS
The Share Extension means you can frame a screenshot straight from Photos, Safari, Mail, or any app that can share an image. The bezel lands on your clipboard, ready to paste into Slack, Notion, Keynote, or email.

PIXEL-PERFECT OUT OF THE BOX
A custom screen-region detection pipeline analyzes every bezel image and builds anti-aliased masks at build time. No visible seams at the rounded corners, no halos, no manual tweaking.

NATIVE ON EVERY PLATFORM
Built with SwiftUI and AVFoundation. Native on Mac, iPhone, and iPad — no wrappers, no web views. Drag-and-drop on Mac, PhotosPicker on iOS, and platform-appropriate share, copy, and export flows on each.

ACCESSIBILITY
VoiceOver labels across the editor, export controls, and Share Extension.

PRIVACY-RESPECTING
Everything runs on-device. No accounts, no uploads, no telemetry, no tracking.

Universal Purchase — buy once, use on Mac, iPhone, and iPad.
```

## What's New in This Version — v3.1.0 (4000 chars max)

```
• 11 new device bezels, including iPad (A16), iPad mini (A17 Pro), iPad Air M4 (11" and 13"), iPad Pro M5 (11" and 13"), MacBook Pro M5 (14" and 16"), MacBook Air M5 (13" and 15"), and MacBook Neo.
• Redesigned empty state with device mockups so you can see what the app does before dropping anything in.
• Export size controls: adjust width, height, or scale with per-mode limits (images up to 16,384px; videos up to 7,680px).
• Fixes for Mac device matching with landscape-only bezels, and miscellaneous polish across macOS, iOS, and the Share Extension.
```

## Category

- **Primary:** Graphics & Design
- **Secondary:** Photo & Video

## Age Rating

4+ (no objectionable content)

## Copyright

```
© 2026 DGR Labs, LLC
```

## URLs

- **Support URL:** _TODO — needs a public support page (GitHub Issues page is acceptable: https://github.com/cwooddgr/bezelbub/issues)_
- **Marketing URL:** _Optional — could point at https://github.com/cwooddgr/bezelbub or a dedicated landing page_
- **Privacy Policy URL:** _Required. Since the app does no data collection, a simple one-page privacy policy stating "Bezelbub does not collect, transmit, or store any user data" is sufficient. Host on GitHub Pages, your site, or a gist._

## Content Rights

- Check the box indicating the app **contains, displays, or accesses third-party content** (Apple device art from Apple's Design Resources).
- In the rights confirmation, state: "Device bezel artwork is sourced from Apple's publicly available Design Resources and used in accordance with Apple's terms."

## App Privacy (Data Collection)

- **Data collection:** None.
- **Data linked to user:** None.
- **Tracking:** None.

Select "Data Not Collected" in App Store Connect's Privacy questionnaire.

## Platform-specific differences

**iOS listing** — emphasize the Share Extension (only on iOS) and PhotosPicker import. Screenshots should include at least one showing the share-sheet flow from another app.

**macOS listing** — emphasize drag-and-drop from Finder, the full editor window, and video export. The Share Extension is not part of the Mac build, so don't mention it in the Mac description's "frame from any app" section if you localize per platform.

## App Review Notes (internal-only field)

```
Bezelbub is a cross-platform utility for framing screenshots and screen recordings in Apple device bezels. This submission spans:
  • A native macOS app.
  • A native iOS/iPadOS app including a Share Extension that accepts images from the system share sheet.

The two listings are linked via Universal Purchase.

Bezel artwork is sourced from Apple's official Design Resources. Everything is processed on-device — the app has no network access, no accounts, and no telemetry.

To try the core flow:
  1. Open any app (Photos, Safari, Notes) and take a screenshot.
  2. Open Bezelbub (or use the Share Extension on iOS) and import the screenshot.
  3. The matching device bezel is detected automatically; the framed result can be copied, saved, or shared.

For video framing on macOS: drag in any MOV/MP4 screen recording and export as a framed MOV.

We have addressed prior feedback under Guideline 4.3 — see the accompanying review response for details on the cross-platform expansion and proprietary technical work since earlier submissions.

Contact: charlie.wood@gmail.com
```

## Pre-submission checklist

- [ ] Confirm Universal Purchase is enabled linking the iOS and macOS records.
- [ ] Upload iOS screenshots (iPhone 6.7", iPhone 6.5", iPad Pro 12.9" 2nd & 6th gen) — include one showing the Share Extension in use.
- [ ] Upload macOS screenshots (1280×800 or 2560×1600) — include one showing video framing.
- [ ] Add a Privacy Policy URL.
- [ ] Add a Support URL.
- [ ] Tick Content Rights box for third-party content (Apple Design Resources).
- [ ] Paste the updated `APP_REVIEW_RESPONSE.md` into the Review Notes if a 4.3 concern surfaces again.
- [ ] Submit both platform builds for review the same day.
