#!/usr/bin/env swift
// Generates assets/icon-1024.png — the Fumble icon: a tilted keycap with an F, traced in
// small tone-on-tone pixel squares (the pixel-grid wallpaper aesthetic), on a light-blue
// tile. Chosen from variants in scripts/make-logo-1-variants.swift (keycap-3).
// Run: swift scripts/make-icon.swift

import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}

// Rounded tile inset to the macOS icon grid (~10% padding), corner radius ~22.37% of the tile.
let padding = size * 0.09
let tile = CGRect(x: padding, y: padding, width: size - 2 * padding, height: size - 2 * padding)
let radius = tile.width * 0.2237
NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius).addClip()

// Light-blue gradient, subtly lighter at the top — matched to the pixel-grid wallpaper.
NSGradient(colors: [
    NSColor(calibratedRed: 0.46, green: 0.67, blue: 0.90, alpha: 1),
    NSColor(calibratedRed: 0.36, green: 0.57, blue: 0.84, alpha: 1),
])!.draw(in: tile, angle: -90)

// The keycap-with-F as a 15×15 pixel pattern: rounded 1-px border, F left-of-centre on the
// cap, like a real keycap legend.
let pattern = [
    "..###########..",
    ".#...........#.",
    "#.............#",
    "#.............#",
    "#....#####....#",
    "#....#........#",
    "#....#........#",
    "#....####.....#",
    "#....#........#",
    "#....#........#",
    "#....#........#",
    "#.............#",
    "#.............#",
    ".#...........#.",
    "..###########..",
]

let cell = 34.0, gap = 6.0
let pitch = cell + gap
let span = 15 * pitch - gap

context.saveGState()
context.translateBy(x: tile.midX, y: tile.midY)
context.rotate(by: -7 * .pi / 180)   // the tilt IS the logo — a key caught mid-fumble
context.setShadow(offset: CGSize(width: 0, height: -cell * 0.10),
                  blur: cell * 0.18,
                  color: NSColor.black.withAlphaComponent(0.20).cgColor)
NSColor(calibratedRed: 0.20, green: 0.40, blue: 0.68, alpha: 1).setFill()
for (row, line) in pattern.enumerated() {
    for (col, ch) in line.enumerated() where ch == "#" {
        let rect = CGRect(x: -span / 2 + CGFloat(col) * pitch,
                          y: span / 2 - CGFloat(row) * pitch - cell,
                          width: cell, height: cell)
        NSBezierPath(roundedRect: rect, xRadius: cell * 0.18, yRadius: cell * 0.18).fill()
    }
}
context.restoreGState()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render png")
}

let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("assets/icon-1024.png")
try! FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true
)
try! png.write(to: output)
print("Wrote \(output.path)")
