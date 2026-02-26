# Accessibility Labels Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `.accessibilityLabel()` and `.accessibilityHint()` to all unlabeled interactive elements so VoiceOver is fully usable across macOS, iOS, and the share extension.

**Architecture:** Pure modifier additions — no new files, no logic changes. Add `.accessibilityLabel()` to every element that lacks one, and `.accessibilityHint()` where the action result isn't obvious from the label.

**Tech Stack:** SwiftUI accessibility modifiers

---

### Task 1: iOS ContentView — icon-only buttons and empty state buttons

**Files:**
- Modify: `iOS/Views/ContentView.swift`

**Step 1: Add labels to the empty state Photos and Files buttons**

At line 103-104, after `.buttonStyle(.bordered)` on the Photos button, add the accessibility modifiers. At line 111, after `.buttonStyle(.bordered)` on the Files button, add them too.

```swift
// Photos button (around line 103-104) — add after .buttonStyle(.bordered):
.accessibilityLabel("Photos")
.accessibilityHint("Import a screenshot from your photo library")

// Files button (around line 110-111) — add after .buttonStyle(.bordered):
.accessibilityLabel("Files")
.accessibilityHint("Import a screenshot from Files")
```

**Step 2: Add label to the plus menu trigger**

At line 162-164, the Menu label is `Image(systemName: "plus")`. Add accessibility modifiers to the Menu (after the closing `}` of the `label:` parameter, around line 164):

```swift
// Plus menu (line 164) — add after the Menu closing:
.accessibilityLabel("Add Image")
.accessibilityHint("Opens options to import from Photos or Files")
```

**Step 3: Add label to the video export button**

At line 176-178, the video mode toolbar button uses `Image(systemName: "square.and.arrow.up")`. Add after `.disabled(appState.isExporting)` on line 179:

```swift
.accessibilityLabel("Export Video")
```

**Step 4: Add label to the share menu trigger**

At line 201-203, the image mode Menu label is `Image(systemName: "square.and.arrow.up")`. Add after the Menu closing brace (line 203):

```swift
.accessibilityLabel("Share")
.accessibilityHint("Opens sharing options")
```

**Step 5: Add label to the rotate video button**

At line 328-333, the rotate button uses `Image(systemName: "rotate.right")`. Add after `.disabled(appState.isExporting)` on line 333:

```swift
.accessibilityLabel("Rotate Video")
```

**Step 6: Build to verify no compile errors**

Run: `xcodegen generate && xcodebuild -project Bezelbub.xcodeproj -scheme Bezelbub-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 7: Commit**

```bash
git add iOS/Views/ContentView.swift
git commit -m "a11y: add accessibility labels to iOS ContentView buttons"
```

---

### Task 2: macOS ContentView — rotate button

**Files:**
- Modify: `macOS/Views/ContentView.swift`

**Step 1: Add label and hint to the rotate video button**

At line 159-165, the rotate button has `.help()` but no accessibility label. Add after `.disabled(appState.isExporting)` on line 165:

```swift
.accessibilityLabel("Rotate Video")
.accessibilityHint("Hold Option for counter-clockwise")
```

**Step 2: Build to verify no compile errors**

Run: `xcodegen generate && xcodebuild -project Bezelbub.xcodeproj -scheme Bezelbub -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add macOS/Views/ContentView.swift
git commit -m "a11y: add accessibility label to macOS rotate button"
```

---

### Task 3: macOS ExportSizeAccessoryView — text fields

**Files:**
- Modify: `macOS/Views/ExportSizeAccessoryView.swift`

**Step 1: Add labels and hints to width and height text fields**

At line 24-27, the width TextField. Add after `.overlay(...)` on line 27:

```swift
.accessibilityLabel("Width")
.accessibilityHint("Export width in pixels")
```

At line 30-34, the height TextField. Add after `.overlay(...)` on line 34:

```swift
.accessibilityLabel("Height")
.accessibilityHint("Export height in pixels")
```

**Step 2: Build to verify no compile errors**

Run: `xcodegen generate && xcodebuild -project Bezelbub.xcodeproj -scheme Bezelbub -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add macOS/Views/ExportSizeAccessoryView.swift
git commit -m "a11y: add accessibility labels to macOS export size fields"
```

---

### Task 4: iOS VideoExportSheet — text fields and reset button

**Files:**
- Modify: `iOS/Views/VideoExportSheet.swift`

**Step 1: Add labels and hints to width and height text fields, and reset button**

At line 29-32, the width TextField. Add after `.frame(width: 100)` on line 32:

```swift
.accessibilityLabel("Width")
.accessibilityHint("Export width in pixels")
```

At line 37-40, the height TextField. Add after `.frame(width: 100)` on line 40:

```swift
.accessibilityLabel("Height")
.accessibilityHint("Export height in pixels")
```

At line 49, the Reset button. Add after `Button("Reset") { model.reset() }`:

```swift
.accessibilityLabel("Reset Size")
.accessibilityHint("Resets to original video dimensions")
```

**Step 2: Build to verify no compile errors**

Run: `xcodegen generate && xcodebuild -project Bezelbub.xcodeproj -scheme Bezelbub-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add iOS/Views/VideoExportSheet.swift
git commit -m "a11y: add accessibility labels to iOS video export sheet"
```

---

### Task 5: Share Extension — menu trigger button

**Files:**
- Modify: `BezelbubShareExtension/ShareViewController.swift`

**Step 1: Add label and hint to the share menu trigger**

At line 158-160, the Menu label is `Image(systemName: "square.and.arrow.up")`. Add after the Menu closing (line 160):

```swift
.accessibilityLabel("Share")
.accessibilityHint("Opens sharing options")
```

**Step 2: Build to verify no compile errors**

Run: `xcodegen generate && xcodebuild -project Bezelbub.xcodeproj -scheme Bezelbub-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add BezelbubShareExtension/ShareViewController.swift
git commit -m "a11y: add accessibility labels to share extension menu"
```

---

### Task 6: Update design review tracking

**Files:**
- Modify: `DESIGN_REVIEW.md`

**Step 1: Mark the accessibility labels issue as complete**

In the P1 table, update the accessibility labels row to show it's been resolved (strike through or remove).

**Step 2: Commit**

```bash
git add DESIGN_REVIEW.md
git commit -m "docs: mark accessibility labels as complete in design review"
```
