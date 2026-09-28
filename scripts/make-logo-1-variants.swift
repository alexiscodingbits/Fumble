#!/usr/bin/env swift
// Variants of logo option 1 (tilted monoline keycap with F), crossed with the pixel-mosaic
// wallpaper DNA: the same keycap traced in small tone-on-tone squares. Renders
// assets/logo-options/keycap-1..5.png + keycap-sheet.png.
// Run: swift scripts/make-logo-1-variants.swift

import AppKit

let size = 1024.0

func tileCanvas(_ draw: (CGContext, CGRect) -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    let padding = size * 0.09
    let tile = CGRect(x: padding, y: padding, width: size - 2 * padding, height: size - 2 * padding)
    NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.2237, yRadius: tile.width * 0.2237).addClip()
    draw(context, tile)
    image.unlockFocus()
    return image
}

// The keycap-with-F as a 15×15 pixel pattern: rounded 1-px border, F left-of-centre on the
// cap, matching the monoline composition.
let keycapPattern = [
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

func drawPixelKeycap(in context: CGContext, tile: CGRect, pixel: NSColor) {
    let cell = 34.0, gap = 6.0
    let pitch = cell + gap
    let span = 15 * pitch - gap

    context.saveGState()
    context.translateBy(x: tile.midX, y: tile.midY)
    context.rotate(by: -7 * .pi / 180)
    context.setShadow(offset: CGSize(width: 0, height: -cell * 0.10),
                      blur: cell * 0.18,
                      color: NSColor.black.withAlphaComponent(0.20).cgColor)
    pixel.setFill()
    for (row, line) in keycapPattern.enumerated() {
        for (col, ch) in line.enumerated() where ch == "#" {
            let rect = CGRect(x: -span / 2 + CGFloat(col) * pitch,
                              y: span / 2 - CGFloat(row) * pitch - cell,
                              width: cell, height: cell)
            NSBezierPath(roundedRect: rect, xRadius: cell * 0.18, yRadius: cell * 0.18).fill()
        }
    }
    context.restoreGState()
}

func drawMonolineKeycap(in context: CGContext, tile: CGRect, line: NSColor) {
    context.saveGState()
    context.translateBy(x: tile.midX, y: tile.midY)
    context.rotate(by: -7 * .pi / 180)

    let cap = tile.width * 0.56
    let stroke = cap * 0.08
    line.setStroke()

    let capPath = NSBezierPath(
        roundedRect: CGRect(x: -cap / 2, y: -cap / 2, width: cap, height: cap),
        xRadius: cap * 0.2, yRadius: cap * 0.2
    )
    capPath.lineWidth = stroke
    capPath.stroke()

    let f = NSBezierPath()
    f.lineWidth = stroke
    f.lineCapStyle = .round
    let h = cap * 0.50, w = cap * 0.33
    f.move(to: NSPoint(x: -w / 2, y: -h / 2)); f.line(to: NSPoint(x: -w / 2, y: h / 2))
    f.move(to: NSPoint(x: -w / 2, y: h / 2)); f.line(to: NSPoint(x: w / 2, y: h / 2))
    f.move(to: NSPoint(x: -w / 2, y: h * 0.05)); f.line(to: NSPoint(x: w * 0.30, y: h * 0.05))
    f.stroke()
    context.restoreGState()
}

func gradientBackground(_ top: NSColor, _ bottom: NSColor, in tile: CGRect) {
    NSGradient(colors: [top, bottom])!.draw(in: tile, angle: -90)
}

// ── 1. YC-orange, pixel keycap (tone-on-tone, wallpaper DNA).
let v1 = tileCanvas { context, tile in
    gradientBackground(NSColor(calibratedRed: 0.97, green: 0.58, blue: 0.28, alpha: 1),
                       NSColor(calibratedRed: 0.94, green: 0.49, blue: 0.18, alpha: 1), in: tile)
    drawPixelKeycap(in: context, tile: tile,
                    pixel: NSColor(calibratedRed: 0.70, green: 0.34, blue: 0.09, alpha: 1))
}

// ── 2. YC-orange, white monoline keycap.
let v2 = tileCanvas { context, tile in
    gradientBackground(NSColor(calibratedRed: 0.99, green: 0.49, blue: 0.16, alpha: 1),
                       NSColor(calibratedRed: 0.95, green: 0.40, blue: 0.08, alpha: 1), in: tile)
    drawMonolineKeycap(in: context, tile: tile, line: .white)
}

// ── 3. Light blue, pixel keycap (tone-on-tone, the blue wallpaper palette).
let v3 = tileCanvas { context, tile in
    gradientBackground(NSColor(calibratedRed: 0.46, green: 0.67, blue: 0.90, alpha: 1),
                       NSColor(calibratedRed: 0.36, green: 0.57, blue: 0.84, alpha: 1), in: tile)
    drawPixelKeycap(in: context, tile: tile,
                    pixel: NSColor(calibratedRed: 0.20, green: 0.40, blue: 0.68, alpha: 1))
}

// ── 4. Light blue, white monoline keycap.
let v4 = tileCanvas { context, tile in
    gradientBackground(NSColor(calibratedRed: 0.44, green: 0.65, blue: 0.89, alpha: 1),
                       NSColor(calibratedRed: 0.33, green: 0.54, blue: 0.82, alpha: 1), in: tile)
    drawMonolineKeycap(in: context, tile: tile, line: .white)
}

// ── 5. Navy, white pixel keycap.
let v5 = tileCanvas { context, tile in
    gradientBackground(NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.24, alpha: 1),
                       NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.17, alpha: 1), in: tile)
    drawPixelKeycap(in: context, tile: tile,
                    pixel: NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1))
}

// ── Write files + contact sheet.
let variants = [v1, v2, v3, v4, v5]
let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("assets/logo-options")
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func writePNG(_ image: NSImage, to url: URL) {
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

for (i, image) in variants.enumerated() {
    writePNG(image, to: outDir.appendingPathComponent("keycap-\(i + 1).png"))
}

let thumb = 460.0, margin = 40.0, labelBand = 70.0
let sheet = NSImage(size: NSSize(width: margin + 5 * (thumb + margin),
                                 height: thumb + 2 * margin + labelBand))
sheet.lockFocus()
NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: sheet.size)).fill()
for (i, image) in variants.enumerated() {
    let x = margin + CGFloat(i) * (thumb + margin)
    image.draw(in: NSRect(x: x, y: margin + labelBand, width: thumb, height: thumb))
    let label = "\(i + 1)" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 44, weight: .bold),
        .foregroundColor: NSColor.black,
    ]
    let labelSize = label.size(withAttributes: attrs)
    label.draw(at: NSPoint(x: x + thumb / 2 - labelSize.width / 2, y: margin / 2),
               withAttributes: attrs)
}
sheet.unlockFocus()
writePNG(sheet, to: outDir.appendingPathComponent("keycap-sheet.png"))
print("Wrote \(outDir.path): keycap-1..5.png + keycap-sheet.png")
