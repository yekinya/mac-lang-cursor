#!/usr/bin/env swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let species = CommandLine.arguments.dropFirst().first ?? "Cat"
let url = root.appendingPathComponent("Sources/LangCursor/Resources/\(species)SpriteAtlas.png")
let atlas = NSBitmapImageRep(data: try Data(contentsOf: url))!
precondition(atlas.pixelsWide == 1024 && atlas.pixelsHigh == 1024 && atlas.hasAlpha)
var count = 0
for row in 0..<8 {
    for column in 0..<8 {
        var occupied = 0, minX = 128, minY = 128, maxX = -1, maxY = -1
        for y in 0..<128 {
            for x in 0..<128 {
                guard atlas.colorAt(x: column * 128 + x, y: row * 128 + y)!.alphaComponent > 0 else { continue }
                occupied += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        precondition(occupied > 1500, "Missing or partial sprite at \(row),\(column)")
        precondition(minX >= 8 && maxX < 120 && minY >= 4 && maxY < 120,
                     "Clipped sprite at \(row),\(column): \(minX),\(minY)–\(maxX),\(maxY)")
        precondition(maxY == 115, "Inconsistent ground baseline at \(row),\(column)")
        count += 1
    }
}
// Sit-down must end on exactly the same image as the first idle frame.
for y in 0..<128 {
    for x in 0..<128 {
        precondition(atlas.colorAt(x: 7 * 128 + x, y: 3 * 128 + y) ==
                     atlas.colorAt(x: x, y: 4 * 128 + y))
    }
}
print("PASS: \(count) populated transparent frames, complete padding, shared baseline, seamless sit/idle boundary")
