#!/usr/bin/env swift

// generate-screen-regions.swift
// Flood-fills all bezel PNGs in Resources/Bezels/ to detect screen regions,
// writes the results to Resources/screen-regions.json.
//
// Usage:
//   swift Scripts/generate-screen-regions.swift           # incremental
//   swift Scripts/generate-screen-regions.swift --force   # regenerate all

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Configuration

let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let bezelsDir = projectDir.appendingPathComponent("Resources/Bezels")
let outputPath = projectDir.appendingPathComponent("Resources/screen-regions.json")

let forceRegenerate = CommandLine.arguments.contains("--force")

// MARK: - Region Detection (same algorithm as ScreenRegionDetector.detectScreenRegion)

func detectScreenRegion(imageURL: URL) -> CGRect? {
    guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        return nil
    }

    let width = image.width
    let height = image.height

    guard let data = image.dataProvider?.data,
          let ptr = CFDataGetBytePtr(data)
    else {
        return nil
    }

    let bytesPerPixel = image.bitsPerPixel / 8
    let bytesPerRow = image.bytesPerRow

    let startX = width / 2
    let startY = height / 2

    let startAlpha = ptr[startY * bytesPerRow + startX * bytesPerPixel + 3]
    guard startAlpha == 0 else {
        return nil
    }

    var visited = [Bool](repeating: false, count: width * height)
    var stack: [(Int, Int)] = [(startX, startY)]

    var minX = startX, maxX = startX
    var minY = startY, maxY = startY

    while let (x, y) = stack.popLast() {
        guard x >= 0, x < width, y >= 0, y < height else { continue }
        let idx = y * width + x
        guard !visited[idx] else { continue }
        let alpha = ptr[y * bytesPerRow + x * bytesPerPixel + 3]
        guard alpha == 0 else { continue }

        visited[idx] = true

        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }

        stack.append((x - 1, y))
        stack.append((x + 1, y))
        stack.append((x, y - 1))
        stack.append((x, y + 1))
    }

    let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)

    guard rect.width > 100, rect.height > 100 else {
        return nil
    }

    return rect
}

// MARK: - JSON Model

struct RegionEntry: Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

// MARK: - Main

// Load existing JSON (for incremental mode)
var existing: [String: RegionEntry] = [:]
if !forceRegenerate, let data = try? Data(contentsOf: outputPath),
   let decoded = try? JSONDecoder().decode([String: RegionEntry].self, from: data) {
    existing = decoded
}

// Enumerate all bezel PNGs
let fm = FileManager.default
guard let contents = try? fm.contentsOfDirectory(at: bezelsDir, includingPropertiesForKeys: nil) else {
    fputs("Error: Cannot read \(bezelsDir.path)\n", stderr)
    exit(1)
}

let pngFiles = contents
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !pngFiles.isEmpty else {
    fputs("Error: No PNG files found in \(bezelsDir.path)\n", stderr)
    exit(1)
}

// Track which filenames are still on disk (for pruning)
let onDiskNames = Set(pngFiles.map(\.lastPathComponent))

// Prune entries for bezels no longer on disk
let prunedCount = existing.keys.filter { !onDiskNames.contains($0) }.count
for key in existing.keys where !onDiskNames.contains(key) {
    existing.removeValue(forKey: key)
}

// Process new/missing bezels
var newCount = 0
var skipCount = 0
var failCount = 0
var failures: [String] = []

for pngURL in pngFiles {
    let name = pngURL.lastPathComponent

    if existing[name] != nil {
        skipCount += 1
        continue
    }

    if let region = detectScreenRegion(imageURL: pngURL) {
        existing[name] = RegionEntry(
            x: Int(region.origin.x),
            y: Int(region.origin.y),
            width: Int(region.size.width),
            height: Int(region.size.height)
        )
        newCount += 1
    } else {
        failures.append(name)
        failCount += 1
    }
}

// Write output
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
guard let jsonData = try? encoder.encode(existing) else {
    fputs("Error: Failed to encode JSON\n", stderr)
    exit(1)
}

do {
    try jsonData.write(to: outputPath)
} catch {
    fputs("Error: Failed to write \(outputPath.path): \(error)\n", stderr)
    exit(1)
}

// Summary
print("Screen regions: \(existing.count) total, \(newCount) new, \(skipCount) skipped, \(prunedCount) pruned")
if !failures.isEmpty {
    fputs("Failed bezels (\(failCount)):\n", stderr)
    for name in failures {
        fputs("  - \(name)\n", stderr)
    }
    exit(1)
}
