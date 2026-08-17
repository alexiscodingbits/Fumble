#!/usr/bin/env swift
// Generates assets/icon-1024.png — a simple, legible app icon with no external design assets.
// A macOS-style rounded tile with a gradient and a bold monospace "F". Redesign later; this is
// a clean placeholder that reads well down to 16px. Run: swift scripts/make-icon.swift

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

// Vertical gradient — confident blue.
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.29, green: 0.56, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.11, green: 0.31, blue: 0.85, alpha: 1),
])!
gradient.draw(in: tile, angle: -90)

// A subtle keycap plate behind the letter, for a "typing" feel.
let capInset = tile.width * 0.26
let cap = tile.insetBy(dx: capInset, dy: capInset)
let capPath = NSBezierPath(roundedRect: cap, xRadius: cap.width * 0.18, yRadius: cap.width * 0.18)
NSColor.white.withAlphaComponent(0.12).setFill()
capPath.fill()

// Bold "F".
let letter = "F" as NSString
let font = NSFont.monospacedSystemFont(ofSize: size * 0.44, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let textSize = letter.size(withAttributes: attributes)
let textOrigin = NSPoint(
    x: tile.midX - textSize.width / 2,
    y: tile.midY - textSize.height / 2
)
letter.draw(at: textOrigin, withAttributes: attributes)

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
