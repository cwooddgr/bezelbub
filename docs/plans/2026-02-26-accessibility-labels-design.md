# Accessibility Labels Design

**Goal:** Make all interactive elements VoiceOver-usable by adding `.accessibilityLabel()` and `.accessibilityHint()` across all platforms.

**Approach:** Add labels to all 9 unlabeled interactive elements, plus hints on actions where the result isn't obvious from the label alone. Labels are short (1-3 words); hints describe what will happen.

## Elements

### Icon-only buttons

| File | Element | Label | Hint |
|------|---------|-------|------|
| `iOS/Views/ContentView.swift` | Plus menu trigger | "Add Image" | "Opens options to import from Photos or Files" |
| `iOS/Views/ContentView.swift` | Share menu trigger | "Share" | "Opens sharing options" |
| `iOS/Views/ContentView.swift` | Rotate video button | "Rotate Video" | — |
| `macOS/Views/ContentView.swift` | Rotate video button | "Rotate Video" | "Hold Option for counter-clockwise" |
| `BezelbubShareExtension/ShareViewController.swift` | Menu trigger | "Share" | "Opens sharing options" |

### Text fields

| File | Element | Label | Hint |
|------|---------|-------|------|
| `macOS/Views/ExportSizeAccessoryView.swift` | Width field | "Width" | "Export width in pixels" |
| `macOS/Views/ExportSizeAccessoryView.swift` | Height field | "Height" | "Export height in pixels" |
| `iOS/Views/VideoExportSheet.swift` | Width field | "Width" | "Export width in pixels" |
| `iOS/Views/VideoExportSheet.swift` | Height field | "Height" | "Export height in pixels" |

### Buttons with visible text

| File | Element | Label | Hint |
|------|---------|-------|------|
| `iOS/Views/ContentView.swift` | Photos button (empty state) | "Photos" | "Import a screenshot from your photo library" |
| `iOS/Views/ContentView.swift` | Files button (empty state) | "Files" | "Import a screenshot from Files" |
| `iOS/Views/VideoExportSheet.swift` | Reset button | "Reset Size" | "Resets to original video dimensions" |
