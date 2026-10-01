#!/usr/bin/env swift
// Generates packaging/dmg/background.png — the DMG window background: a near-white canvas
// with a right-pointing arrow in the icon's pixel-square style, sitting between where the
// Fumble.app icon (150, 180) and the /Applications drop target (450, 180) are pinned by
// packaging/dmg/DS_Store. Rendered at 2x with a 144-dpi size hint so Finder draws it crisp
// on Retina at the logical 600×400 window size.
// Run: swift scripts/make-dmg-background.swift  (then scripts/make-dmg-layout.sh to re-pin icons)

import AppKit

let width = 600.0, height = 400.0, scale = 2.0

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    fatalError("failed to create bitmap")
}
rep.size = NSSize(width: width, height: height)   // pixels/points = 2 → 144 dpi in the PNG

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("no graphics context")
}
// With rep.size set, this context already maps points → pixels; don't scale again.
NSGraphicsContext.current = context

// Near-white gradient, subtly lighter at the top — lets the light-blue icon and the blue
// Applications folder carry the colour.
NSGradient(colors: [
    NSColor(calibratedRed: 0.984, green: 0.988, blue: 0.992, alpha: 1),
    NSColor(calibratedRed: 0.945, green: 0.953, blue: 0.965, alpha: 1),
])!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

// Right-pointing arrow traced in small rounded squares — same language as the icon grid.
let pattern = [
    "......#..",
    ".......#.",
    "........#",
    "#########",
    "........#",
    ".......#.",
    "......#..",
]

let cell = 9.0, gap = 2.5
let pitch = cell + gap
let cols = Double(pattern[0].count), rows = Double(pattern.count)
let spanX = cols * pitch - gap, spanY = rows * pitch - gap

// Centred between the two icon positions; Finder's y=180 (top origin) is AppKit y=220.
let originX = 300.0 - spanX / 2
let originY = (height - 180.0) - spanY / 2

NSColor(calibratedRed: 0.72, green: 0.75, blue: 0.80, alpha: 1).setFill()
for (row, line) in pattern.enumerated() {
    for (col, ch) in line.enumerated() where ch == "#" {
        let rect = CGRect(x: originX + CGFloat(col) * pitch,
                          y: originY + spanY - CGFloat(row + 1) * pitch + gap,
                          width: cell, height: cell)
        NSBezierPath(roundedRect: rect, xRadius: cell * 0.18, yRadius: cell * 0.18).fill()
    }
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render png")
}

let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("packaging/dmg/background.png")
try! FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true
)
try! png.write(to: output)
print("Wrote \(output.path)")
