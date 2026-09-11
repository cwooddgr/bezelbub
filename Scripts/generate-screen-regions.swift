#!/usr/bin/env swift

// generate-screen-regions.swift
// Flood-fills all bezel PNGs (seeded by findScreenSeed, mirrored in ScreenRegionDetector) in BezelbubKit/Sources/BezelbubKit/Resources/Bezels/
// to detect screen regions and screen masks. Writes regions to
// .../Resources/screen-regions.json and grayscale mask PNGs to .../Resources/Masks/.
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
// Resources live inside the BezelbubKit Swift package and are served to all
// targets (apps, share extension, CLI) via Bundle.module.
let resourcesDir = projectDir.appendingPathComponent("BezelbubKit/Sources/BezelbubKit/Resources")
let bezelsDir = resourcesDir.appendingPathComponent("Bezels")
let masksDir = resourcesDir.appendingPathComponent("Masks")
let outputPath = resourcesDir.appendingPathComponent("screen-regions.json")

let forceRegenerate = CommandLine.arguments.contains("--force")

// MARK: - Seed Search

/// Returns a fully-transparent pixel inside the screen hole to flood-fill from.
///
/// Fast path: the image center, which every single-screen bezel satisfies.
/// When the center is opaque — the iPhone Duo "outer display, open" view puts
/// the hinge there, with the back panel on one side and the display on the
/// other — scan for the largest connected alpha == 0 component that does not
/// touch the image border. The exterior transparency always reaches the
/// border; the screen hole never does.
func findScreenSeed(ptr: UnsafePointer<UInt8>, width: Int, height: Int,
                    bytesPerRow: Int, bytesPerPixel: Int) -> (x: Int, y: Int)? {
    let centerX = width / 2
    let centerY = height / 2
    if ptr[centerY * bytesPerRow + centerX * bytesPerPixel + 3] == 0 {
        return (centerX, centerY)
    }

    var visited = [Bool](repeating: false, count: width * height)
    var best: (seed: (x: Int, y: Int), size: Int)?

    for y in 0..<height {
        for x in 0..<width {
            let idx = y * width + x
            guard !visited[idx], ptr[y * bytesPerRow + x * bytesPerPixel + 3] == 0 else { continue }

            visited[idx] = true
            var stack: [(Int, Int)] = [(x, y)]
            var size = 0
            var touchesBorder = false

            while let (px, py) = stack.popLast() {
                size += 1
                if px == 0 || py == 0 || px == width - 1 || py == height - 1 {
                    touchesBorder = true
                }
                for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)] {
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let nidx = ny * width + nx
                    guard !visited[nidx], ptr[ny * bytesPerRow + nx * bytesPerPixel + 3] == 0 else { continue }
                    visited[nidx] = true
                    stack.append((nx, ny))
                }
            }

            if !touchesBorder, size > (best?.size ?? 0) {
                best = ((x, y), size)
            }
        }
    }

    return best?.seed
}

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

    guard let (startX, startY) = findScreenSeed(
        ptr: ptr, width: width, height: height,
        bytesPerRow: bytesPerRow, bytesPerPixel: bytesPerPixel
    ) else {
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

// MARK: - Mask Detection (same algorithm as ScreenRegionDetector.detectScreenMask)

func detectScreenMask(imageURL: URL) -> CGImage? {
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

    guard let (startX, startY) = findScreenSeed(
        ptr: ptr, width: width, height: height,
        bytesPerRow: bytesPerRow, bytesPerPixel: bytesPerPixel
    ) else {
        return nil
    }

    // Phase 1: Flood fill through fully-transparent pixels from center.
    var visited = [Bool](repeating: false, count: width * height)
    var stack: [(Int, Int)] = [(startX, startY)]
    var edgeCandidates: [(Int, Int)] = []

    while let (x, y) = stack.popLast() {
        guard x >= 0, x < width, y >= 0, y < height else { continue }
        let idx = y * width + x
        guard !visited[idx] else { continue }
        let alpha = ptr[y * bytesPerRow + x * bytesPerPixel + 3]
        if alpha != 0 {
            if alpha < 255 { edgeCandidates.append((x, y)) }
            continue
        }

        visited[idx] = true

        stack.append((x - 1, y))
        stack.append((x + 1, y))
        stack.append((x, y - 1))
        stack.append((x, y + 1))
    }

    // Phase 2: Expand into connected semi-transparent pixels at the edge.
    var edgeStack = edgeCandidates
    while let (x, y) = edgeStack.popLast() {
        guard x >= 0, x < width, y >= 0, y < height else { continue }
        let idx = y * width + x
        guard !visited[idx] else { continue }
        let alpha = ptr[y * bytesPerRow + x * bytesPerPixel + 3]
        guard alpha > 0, alpha < 255 else { continue }

        visited[idx] = true

        edgeStack.append((x - 1, y))
        edgeStack.append((x + 1, y))
        edgeStack.append((x, y - 1))
        edgeStack.append((x, y + 1))
    }

    // Build grayscale mask: visited = white, others = black
    var maskPixels = [UInt8](repeating: 0, count: width * height)
    for i in 0..<(width * height) {
        if visited[i] { maskPixels[i] = 0xFF }
    }

    let maskData = Data(maskPixels) as CFData
    guard let provider = CGDataProvider(data: maskData),
          let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
          let maskImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          )
    else {
        return nil
    }

    return maskImage
}

func writeMaskPNG(image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
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

// Write region JSON output
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

// MARK: - Mask Generation

// Create Masks directory if needed
try? fm.createDirectory(at: masksDir, withIntermediateDirectories: true)

// Prune masks for bezels no longer on disk
if let maskFiles = try? fm.contentsOfDirectory(at: masksDir, includingPropertiesForKeys: nil) {
    for maskURL in maskFiles where maskURL.pathExtension.lowercased() == "png" {
        if !onDiskNames.contains(maskURL.lastPathComponent) {
            try? fm.removeItem(at: maskURL)
        }
    }
}

var maskNewCount = 0
var maskSkipCount = 0
var maskFailCount = 0
var maskFailures: [String] = []

for pngURL in pngFiles {
    let name = pngURL.lastPathComponent
    let maskURL = masksDir.appendingPathComponent(name)

    // Incremental: skip if mask exists and is newer than bezel
    if !forceRegenerate, fm.fileExists(atPath: maskURL.path) {
        if let bezelAttrs = try? fm.attributesOfItem(atPath: pngURL.path),
           let maskAttrs = try? fm.attributesOfItem(atPath: maskURL.path),
           let bezelDate = bezelAttrs[.modificationDate] as? Date,
           let maskDate = maskAttrs[.modificationDate] as? Date,
           maskDate >= bezelDate {
            maskSkipCount += 1
            continue
        }
    }

    if let mask = detectScreenMask(imageURL: pngURL) {
        if writeMaskPNG(image: mask, to: maskURL) {
            maskNewCount += 1
        } else {
            maskFailures.append(name)
            maskFailCount += 1
        }
    } else {
        maskFailures.append(name)
        maskFailCount += 1
    }
}

let maskTotal = maskNewCount + maskSkipCount
print("Screen masks: \(maskTotal) total, \(maskNewCount) new, \(maskSkipCount) skipped")
if !maskFailures.isEmpty {
    fputs("Failed masks (\(maskFailCount)):\n", stderr)
    for name in maskFailures {
        fputs("  - \(name)\n", stderr)
    }
    exit(1)
}
