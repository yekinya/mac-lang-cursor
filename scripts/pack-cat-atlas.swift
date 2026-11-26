#!/usr/bin/env swift
import AppKit
import ImageIO

// Lossless sprite extraction/packing after Imagegen. Artwork is never redrawn here.
// Source gutters are measured explicitly: image generation does not guarantee cell alignment.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let species = CommandLine.arguments.dropFirst().first ?? "Cat"
let sourceURL = root.appendingPathComponent("Artwork/\(species)SpriteSource.png")
let outputURL = root.appendingPathComponent("Sources/LangCursor/Resources/\(species)SpriteAtlas.png")
let source = NSBitmapImageRep(data: try Data(contentsOf: sourceURL))!
let evenGrid = (0...8).map { $0 * source.pixelsWide / 8 }
let columns = species == "Cat" ? [20, 188, 338, 488, 638, 788, 938, 1088, 1254] : evenGrid
let rows = species == "Cat" ? [25, 178, 334, 486, 629, 766, 903, 1057, 1234] : evenGrid
let cell = 128
let atlas = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: cell * 8, pixelsHigh: cell * 8,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bitmapFormat: [],
    bytesPerRow: cell * 8 * 4, bitsPerPixel: 32
)!
memset(atlas.bitmapData!, 0, atlas.bytesPerRow * atlas.pixelsHigh)
precondition(source.pixelsWide == columns.last! && source.pixelsHigh == 1254)

var bounds: [[Int]] = []
for row in 0..<8 {
    for column in 0..<8 {
        var minX = columns[column + 1], minY = rows[row + 1], maxX = 0, maxY = 0
        // Ignore imperceptible alpha in the generator's transparent gutters.
        for y in rows[row]..<rows[row + 1] {
            for x in columns[column]..<columns[column + 1] {
                guard source.colorAt(x: x, y: y)!.alphaComponent >= 0.5 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        precondition(maxX > minX && maxY > minY, "Empty animation frame \(row),\(column)")
        bounds.append([minX, minY, maxX, maxY])
    }
}

let largest = bounds.map { max($0[2] - $0[0] + 1, $0[3] - $0[1] + 1) }.max()!
let scale = min(1, 110.0 / Double(largest))
for row in 0..<8 {
    for column in 0..<8 {
        // The transition ends on the exact seated pose used by the idle loop.
        let sourceIndex = row == 3 && column == 7 ? 4 * 8 : row * 8 + column
        let b = bounds[sourceIndex]
        let width = Int((Double(b[2] - b[0] + 1) * scale).rounded())
        let height = Int((Double(b[3] - b[1] + 1) * scale).rounded())
        let left = column * cell + (cell - width) / 2
        let top = row * cell + 116 - height
        for y in 0..<height {
            for x in 0..<width {
                let sx = min(b[2], b[0] + Int(Double(x) / scale))
                let sy = min(b[3], b[1] + Int(Double(y) / scale))
                let color = source.colorAt(x: sx, y: sy)!.usingColorSpace(.deviceRGB)!
                guard color.alphaComponent >= 0.5 else { continue }
                let offset = (top + y) * atlas.bytesPerRow + (left + x) * 4
                let alpha = color.alphaComponent
                atlas.bitmapData![offset] = UInt8(clamping: Int((color.redComponent * alpha * 255).rounded()))
                atlas.bitmapData![offset + 1] = UInt8(clamping: Int((color.greenComponent * alpha * 255).rounded()))
                atlas.bitmapData![offset + 2] = UInt8(clamping: Int((color.blueComponent * alpha * 255).rounded()))
                atlas.bitmapData![offset + 3] = UInt8(clamping: Int((alpha * 255).rounded()))
            }
        }
    }
}
try atlas.representation(using: .png, properties: [:])!.write(to: outputURL)
print("Packed 64 frames into \(outputURL.path) (1024 × 1024, 128px cells, baseline 116px)")
