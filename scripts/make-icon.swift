#!/usr/bin/env swift
// Generates assets/icon-1024.png — the Fumble icon: a single keycap knocked slightly askew
// (a fumbled key), on a deep blue tile. Run: swift scripts/make-icon.swift

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

// Deep blue-slate gradient, darker at the bottom for depth.
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.24, blue: 0.48, alpha: 1),
    NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.24, alpha: 1),
])!
gradient.draw(in: tile, angle: -90)

// The fumbled keycap: a chunky key with a visible 3D base, rotated a few degrees off true.
// The tilt IS the logo — a key caught mid-fumble.
let capSize = tile.width * 0.52
let capRect = CGRect(x: -capSize / 2, y: -capSize / 2, width: capSize, height: capSize)
let capRadius = capSize * 0.18

context.saveGState()
context.translateBy(x: tile.midX, y: tile.midY)
context.rotate(by: -8 * .pi / 180)

// Drop shadow under the whole key.
context.setShadow(offset: CGSize(width: 0, height: -capSize * 0.05),
                  blur: capSize * 0.12,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)

// Key base (the darker slab visible below the cap face).
let basePath = NSBezierPath(
    roundedRect: capRect.offsetBy(dx: 0, dy: -capSize * 0.06),
    xRadius: capRadius, yRadius: capRadius
)
NSColor(calibratedRed: 0.72, green: 0.76, blue: 0.84, alpha: 1).setFill()
basePath.fill()
context.setShadow(offset: .zero, blur: 0, color: nil)

// Cap face, slightly smaller and raised, with a soft top-lit gradient. The face clip lives in
// its own GState so it can't leak into (or wipe out) the letter drawing below.
let faceRect = capRect.insetBy(dx: capSize * 0.035, dy: capSize * 0.035)
    .offsetBy(dx: 0, dy: capSize * 0.03)
let facePath = NSBezierPath(roundedRect: faceRect, xRadius: capRadius * 0.9, yRadius: capRadius * 0.9)
context.saveGState()
facePath.addClip()
NSGradient(colors: [
    NSColor(calibratedRed: 0.99, green: 0.99, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.95, alpha: 1),
])!.draw(in: faceRect, angle: -90)
context.restoreGState()

// The letter, printed on the cap face — dark ink, tilted with the key.
let letter = "F" as NSString
let font = NSFont.monospacedSystemFont(ofSize: capSize * 0.52, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.30, alpha: 1),
]
let textSize = letter.size(withAttributes: attributes)
letter.draw(at: NSPoint(x: faceRect.midX - textSize.width / 2,
                        y: faceRect.midY - textSize.height / 2),
            withAttributes: attributes)

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
