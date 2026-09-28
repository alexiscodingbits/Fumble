#!/usr/bin/env swift
// Generates assets/icon-1024.png — the Fumble icon: a pixel-mosaic "F" with one pixel
// knocked loose and tumbling away (the fumble). Light-blue tile, darker-blue pixel squares,
// slight tilt — the same flavour as the pixel-grid macOS wallpaper it's matched to.
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
let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
tilePath.addClip()

// Light-blue gradient, subtly lighter at the top — matched to the pixel-grid wallpaper.
NSGradient(colors: [
    NSColor(calibratedRed: 0.46, green: 0.67, blue: 0.90, alpha: 1),
    NSColor(calibratedRed: 0.36, green: 0.57, blue: 0.84, alpha: 1),
])!.draw(in: tile, angle: -90)

let pixelColor = NSColor(calibratedRed: 0.22, green: 0.42, blue: 0.70, alpha: 1)

// The "F", drawn on a pixel grid. Rows top-to-bottom; '#' is a pixel. The end pixel of the
// middle bar is missing — it's the one tumbling away below.
let pattern = [
    "######",
    "######",
    "##....",
    "##....",
    "#####.",
    "####..",
    "##....",
    "##....",
    "##....",
]

let cell = 62.0     // pixel square edge
let gap = 10.0      // grid gap, visible like the wallpaper's
let pitch = cell + gap
let cols = 6.0, rows = 9.0
let gridWidth = cols * pitch - gap
let gridHeight = rows * pitch - gap

// Whole grid tilted a few degrees, like the wallpaper (and the old fumbled-keycap logo).
context.saveGState()
context.translateBy(x: tile.midX, y: tile.midY)
context.rotate(by: -6 * .pi / 180)

// F sits just left of centre so the loose pixel has empty space to fall into.
let originX = -gridWidth / 2 - tile.width * 0.03
let originY = gridHeight / 2

func drawPixel(x: CGFloat, y: CGFloat, rotation: CGFloat = 0, airborne: Bool = false) {
    context.saveGState()
    context.translateBy(x: x + cell / 2, y: y + cell / 2)
    context.rotate(by: rotation * .pi / 180)
    // Grounded pixels get the wallpaper's tight soft shadow; the airborne one floats higher.
    context.setShadow(
        offset: CGSize(width: 0, height: airborne ? -cell * 0.22 : -cell * 0.09),
        blur: airborne ? cell * 0.38 : cell * 0.16,
        color: NSColor.black.withAlphaComponent(airborne ? 0.35 : 0.22).cgColor
    )
    let rect = CGRect(x: -cell / 2, y: -cell / 2, width: cell, height: cell)
    pixelColor.setFill()
    NSBezierPath(roundedRect: rect, xRadius: cell * 0.18, yRadius: cell * 0.18).fill()
    context.restoreGState()
}

for (row, line) in pattern.enumerated() {
    for (col, ch) in line.enumerated() where ch == "#" {
        drawPixel(
            x: originX + CGFloat(col) * pitch,
            y: originY - CGFloat(row) * pitch - cell
        )
    }
}

// The fumbled pixel: fallen out of the end of the middle bar (row 5, col 4 — the gap in the
// pattern), caught mid-tumble just below and to the right of where it came from.
drawPixel(
    x: originX + 4.85 * pitch,
    y: originY - 6.55 * pitch - cell,
    rotation: 26,
    airborne: true
)

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
