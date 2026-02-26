# UI Design Review — Remaining Issues

Issues identified from a comprehensive UI/UX review across macOS, iOS, and iPadOS. P0 bugs have been fixed.

## P1 — Significant

| Issue | Platform | Location |
|-------|----------|----------|
| Zero iPad-specific layout — phone UI stretched on large screens. No `horizontalSizeClass`, no `NavigationSplitView`, no sidebar | iPadOS | `iOS/Views/ContentView.swift` |
| No drag-and-drop on iOS (supported on macOS but not iOS) | iOS/iPad | Missing `.dropDestination` in `iOS/Views/ContentView.swift` |
| Zero accessibility labels — VoiceOver unusable for icon-only buttons (rotate, "+", share) | All | All view files |

## P2 — Design Gaps

| Issue | Platform | Location |
|-------|----------|----------|
| Default macOS window size 1500x1850 is taller than most displays | macOS | `macOS/BezelbubApp.swift:30` |
| No visual drag-drop affordance on macOS (no highlighted border or "Drop here" indicator) | macOS | `macOS/Views/ContentView.swift:174-178` |
| No haptic feedback on confirmatory actions (copy, save) | iOS | `iOS/Views/ContentView.swift` |
| iPhone landscape not adapted — very cramped vertical space | iOS | `iOS/Views/ContentView.swift` |
| `VideoExportSheet` only has `.medium` detent — may look odd on iPad | iPadOS | `iOS/Views/VideoExportSheet.swift:70` |
| Controls bar has no background — blends with preview area, only a Divider separates them | iOS | `iOS/Views/ContentView.swift:246-313` |
| macOS bottom toolbar has no background material or visual separation beyond the Divider | macOS | `macOS/Views/ContentView.swift` |

## P3 — Polish

| Issue | Platform | Location |
|-------|----------|----------|
| No keyboard shortcuts on iPad (Cmd+C, Cmd+S, Cmd+O) | iPadOS | `iOS/Views/ContentView.swift` |
| No `.hoverEffect()` on interactive elements for iPad trackpad users | iPadOS | `iOS/Views/ContentView.swift` |
| macOS error state lacks `.multilineTextAlignment(.center)` and `.padding(.horizontal)` | macOS | `macOS/Views/ContentView.swift:50-51` |
| `ExportSizeAccessoryView` uses manual border overlay instead of `.textFieldStyle(.roundedBorder)` | macOS | `macOS/Views/ExportSizeAccessoryView.swift:27,34` |
| Share extension error "No supported image found" is unhelpful when sharing a video | Share Ext | `ShareViewController.swift:57` |
| "+" icon for import may read as "create new" rather than "open existing" | iOS | `iOS/Views/ContentView.swift:143` |
| No "Open Recent" menu on macOS | macOS | `macOS/BezelbubApp.swift` |
| No paste (Cmd+V) support on macOS to paste screenshots from clipboard | macOS | `macOS/Views/ContentView.swift` |
| No way to dismiss/clear the current image without loading a new one | iOS | `iOS/Views/ContentView.swift` |
| No loading/processing indicator for initial photo import (gap before compositing spinner) | iOS | `iOS/Views/ContentView.swift` |
| Export progress overlay uses hardcoded `frame(width: 200)` | iOS | `iOS/Views/ContentView.swift:108` |
| `NSEvent.addLocalMonitorForEvents` set up in `.onAppear` — already fixed | macOS | ~~Fixed~~ |
| macOS app launches and immediately shows `NSOpenPanel` — window briefly appears empty | macOS | `macOS/BezelbubApp.swift:18-23` |

## iPad-Specific Recommendations

- Use `horizontalSizeClass` to detect regular width; switch to `NavigationSplitView` with a sidebar for device/color selection and preview in the detail view
- Add keyboard shortcuts for Copy, Save, Open (matching macOS)
- Add `.hoverEffect()` on interactive elements for trackpad users
- Support drag-and-drop from Files/Photos apps
- Consider `.presentationDetents([.medium, .large])` for `VideoExportSheet`
