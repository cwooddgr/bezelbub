// display-modes.js: list every mode a Mac's built-in display offers, with
// the pixel size a screenshot or screen recording taken in that mode has.
// We use it to fill `MacCaptures` in BezelbubKit/Sources/BezelbubKit/DeviceDefinition.swift.
//
// Runs on any Mac with nothing installed:
//   osascript -l JavaScript display-modes.js
//
// The options key below is the *value* of kCGDisplayShowDuplicateLowResolutionModes
// ("kCGDisplayResolution"), not its name. Without it, macOS hides the HiDPI
// modes and lists only the 1x ones.

ObjC.import('AppKit');
ObjC.import('CoreGraphics');
ObjC.bindFunction('CGDisplayIsBuiltin', ['bool', ['unsigned int']]);
ObjC.bindFunction('CGDisplayCopyAllDisplayModes', ['id', ['unsigned int', 'id']]);
ObjC.bindFunction('CGDisplayCopyDisplayMode', ['id', ['unsigned int']]);
ObjC.bindFunction('CGDisplayModeGetWidth', ['unsigned long', ['id']]);
ObjC.bindFunction('CGDisplayModeGetHeight', ['unsigned long', ['id']]);
ObjC.bindFunction('CGDisplayModeGetPixelWidth', ['unsigned long', ['id']]);
ObjC.bindFunction('CGDisplayModeGetPixelHeight', ['unsigned long', ['id']]);
ObjC.bindFunction('CGDisplayModeGetRefreshRate', ['double', ['id']]);
ObjC.bindFunction('CGDisplayModeGetIOFlags', ['unsigned int', ['id']]);

const DEFAULT_FLAG = 0x4;        // kDisplayModeDefaultFlag
const NATIVE_FLAG = 0x02000000;  // kDisplayModeNativeFlag

function run() {
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;
  const model = app.doShellScript('sysctl -n hw.model');
  const os = $.NSProcessInfo.processInfo.operatingSystemVersionString.js;

  // The built-in panel, even when an external monitor is the main display.
  let display = null;
  const screens = $.NSScreen.screens;
  for (let i = 0; i < screens.count; i++) {
    const id = screens.objectAtIndex(i).deviceDescription.objectForKey('NSScreenNumber').unsignedIntValue;
    if ($.CGDisplayIsBuiltin(id)) { display = id; break; }
  }
  if (display === null) return `${model}, ${os}: no built-in display found (is the lid closed?)`;

  const key = (m) => [$.CGDisplayModeGetWidth(m), $.CGDisplayModeGetHeight(m),
    $.CGDisplayModeGetPixelWidth(m), $.CGDisplayModeGetPixelHeight(m)].join('x');
  const current = key($.CGDisplayCopyDisplayMode(display));

  const opts = $.NSDictionary.dictionaryWithObjectForKey($.NSNumber.numberWithBool(true), 'kCGDisplayResolution');
  const modes = $.CGDisplayCopyAllDisplayModes(display, opts);
  const rows = {};
  for (let i = 0; i < modes.count; i++) {
    const m = modes.objectAtIndex(i);
    const k = key(m);
    const hz = Math.round($.CGDisplayModeGetRefreshRate(m));
    if (rows[k]) { rows[k].hz.add(hz); rows[k].flags |= $.CGDisplayModeGetIOFlags(m); continue; }
    rows[k] = {
      w: $.CGDisplayModeGetWidth(m), h: $.CGDisplayModeGetHeight(m),
      pw: $.CGDisplayModeGetPixelWidth(m), ph: $.CGDisplayModeGetPixelHeight(m),
      hz: new Set([hz]), flags: $.CGDisplayModeGetIOFlags(m), current: k === current,
    };
  }

  const lines = [
    `${model}, ${os}`,
    'looks like (pt)  capture (px)  scale  Hz        notes',
  ];
  for (const r of Object.values(rows).sort((a, b) => b.w - a.w || b.pw - a.pw)) {
    const notes = [];
    if (r.current) notes.push('current');
    if (r.flags & DEFAULT_FLAG) notes.push('default');
    if (r.flags & NATIVE_FLAG) notes.push('native');
    lines.push([
      `${r.w}x${r.h}`.padEnd(16),
      `${r.pw}x${r.ph}`.padEnd(13),
      `${(r.pw / r.w).toFixed(0)}x`.padEnd(6),
      [...r.hz].sort((a, b) => a - b).join('/').padEnd(9),
      notes.join(' '),
    ].join(' ').trimEnd());
  }
  return lines.join('\n');
}
