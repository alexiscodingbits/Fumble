#!/usr/bin/env swift
// Renders five deliberately different minimal logo directions for Fumble into
// assets/logo-options/option-N.png, plus a numbered contact sheet (sheet.png).
// Each is a full 1024 macOS-style tile so the winner can drop straight into the
// icon pipeline. Run: swift scripts/make-logo-options.swift

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

func fill(_ rect: CGRect, _ color: NSColor, radius: CGFloat = 0, rotation: CGFloat = 0,
          in context: CGContext) {
    context.saveGState()
    context.translateBy(x: rect.midX, y: rect.midY)
    context.rotate(by: rotation * .pi / 180)
    color.setFill()
    let centered = CGRect(x: -rect.width / 2, y: -rect.height / 2,
                          width: rect.width, height: rect.height)
    NSBezierPath(roundedRect: centered, xRadius: radius, yRadius: radius).fill()
    context.restoreGState()
}

// ── 1. Monoline keycap — thin white outline keycap with an F, tilted, on flat ink navy.
let option1 = tileCanvas { context, tile in
    NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.16, alpha: 1).setFill()
    context.fill(tile)

    context.saveGState()
    context.translateBy(x: tile.midX, y: tile.midY)
    context.rotate(by: -7 * .pi / 180)

    let cap = tile.width * 0.54
    let stroke = cap * 0.075
    NSColor.white.setStroke()

    let capPath = NSBezierPath(
        roundedRect: CGRect(x: -cap / 2, y: -cap / 2, width: cap, height: cap),
        xRadius: cap * 0.2, yRadius: cap * 0.2
    )
    capPath.lineWidth = stroke
    capPath.stroke()

    // Monoline F: stem + two arms, round caps.
    let f = NSBezierPath()
    f.lineWidth = stroke
    f.lineCapStyle = .round
    let h = cap * 0.46, w = cap * 0.30
    f.move(to: NSPoint(x: -w / 2, y: -h / 2)); f.line(to: NSPoint(x: -w / 2, y: h / 2))
    f.move(to: NSPoint(x: -w / 2, y: h / 2)); f.line(to: NSPoint(x: w / 2, y: h / 2))
    f.move(to: NSPoint(x: -w / 2, y: h * 0.06)); f.line(to: NSPoint(x: w * 0.28, y: h * 0.06))
    f.stroke()
    context.restoreGState()
}

// ── 2. Bauhaus F — flat geometric F on warm paper; the middle bar has slipped out of the
//      letter, tilted, in orange. No shadows, hard edges.
let option2 = tileCanvas { context, tile in
    NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.91, alpha: 1).setFill()
    context.fill(tile)

    let ink = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1)
    let orange = NSColor(calibratedRed: 0.99, green: 0.48, blue: 0.25, alpha: 1)

    let bar = tile.width * 0.155
    let stemH = tile.height * 0.60
    let topW = tile.width * 0.44
    let x = tile.midX - topW * 0.42
    let top = tile.midY + stemH / 2

    fill(CGRect(x: x, y: top - stemH, width: bar, height: stemH), ink, in: context)
    fill(CGRect(x: x, y: top - bar, width: topW, height: bar), ink, in: context)
    // The fumbled middle bar: slid right and down, rotated.
    fill(CGRect(x: x + bar + tile.width * 0.10, y: top - stemH * 0.62,
                width: topW * 0.62, height: bar),
         orange, rotation: -14, in: context)
}

// ── 3. Terminal — monospace "f" with a block cursor and a spellcheck squiggle. Dev-dark.
let option3 = tileCanvas { context, tile in
    NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.09, alpha: 1).setFill()
    context.fill(tile)

    let glyph = "f" as NSString
    let font = NSFont.monospacedSystemFont(ofSize: tile.width * 0.52, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let textSize = glyph.size(withAttributes: attrs)
    let origin = NSPoint(x: tile.midX - textSize.width * 0.92,
                         y: tile.midY - textSize.height / 2 + tile.height * 0.03)
    glyph.draw(at: origin, withAttributes: attrs)

    // Block cursor after the glyph.
    fill(CGRect(x: origin.x + textSize.width * 1.15, y: origin.y + textSize.height * 0.22,
                width: tile.width * 0.13, height: textSize.height * 0.52),
         NSColor(calibratedRed: 0.25, green: 0.69, blue: 0.31, alpha: 1),
         radius: tile.width * 0.012, in: context)

    // Spellcheck squiggle under the f — the typo.
    let squiggle = NSBezierPath()
    squiggle.lineWidth = tile.width * 0.018
    squiggle.lineCapStyle = .round
    let y0 = origin.y + textSize.height * 0.13
    let x0 = origin.x + textSize.width * 0.10
    let width = textSize.width * 0.85
    squiggle.move(to: NSPoint(x: x0, y: y0))
    let waves = 4
    for i in 0..<waves {
        let step = width / CGFloat(waves)
        let cx = x0 + step * (CGFloat(i) + 0.5)
        let up = i % 2 == 0
        squiggle.curve(
            to: NSPoint(x: x0 + step * CGFloat(i + 1), y: y0),
            controlPoint1: NSPoint(x: cx, y: y0 + (up ? 1 : -1) * tile.height * 0.022),
            controlPoint2: NSPoint(x: cx, y: y0 + (up ? 1 : -1) * tile.height * 0.022)
        )
    }
    NSColor(calibratedRed: 0.97, green: 0.32, blue: 0.29, alpha: 1).setStroke()
    squiggle.stroke()
}

// ── 4. Misaligned key — a 3×3 key grid, every key seated except one caught mid-fumble,
//      tilted in its slot, in coral. Flat monochrome otherwise.
let option4 = tileCanvas { context, tile in
    NSColor(calibratedRed: 0.91, green: 0.92, blue: 0.93, alpha: 1).setFill()
    context.fill(tile)

    let key = tile.width * 0.20
    let gap = tile.width * 0.055
    let pitch = key + gap
    let gridSpan = 3 * pitch - gap
    let originX = tile.midX - gridSpan / 2
    let originY = tile.midY - gridSpan / 2
    let slate = NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.27, alpha: 1)
    let coral = NSColor(calibratedRed: 0.99, green: 0.48, blue: 0.25, alpha: 1)

    for row in 0..<3 {
        for col in 0..<3 {
            let fumbled = row == 1 && col == 1
            fill(CGRect(x: originX + CGFloat(col) * pitch + (fumbled ? key * 0.10 : 0),
                        y: originY + CGFloat(CGFloat(2 - row)) * pitch + (fumbled ? -key * 0.06 : 0),
                        width: key, height: key),
                 fumbled ? coral : slate,
                 radius: key * 0.22,
                 rotation: fumbled ? 17 : 0,
                 in: context)
        }
    }
}

// ── 5. Gradient glyph — iOS-modern: vivid blue→violet gradient, rounded white bar-built F
//      whose middle arm droops. Softest of the five.
let option5 = tileCanvas { context, tile in
    NSGradient(colors: [
        NSColor(calibratedRed: 0.31, green: 0.55, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.96, alpha: 1),
    ])!.draw(in: tile, angle: -60)

    let bar = tile.width * 0.14
    let stemH = tile.height * 0.56
    let topW = tile.width * 0.40
    let x = tile.midX - topW * 0.40
    let top = tile.midY + stemH / 2
    let radius = bar / 2

    context.setShadow(offset: CGSize(width: 0, height: -tile.height * 0.012),
                      blur: tile.width * 0.03,
                      color: NSColor.black.withAlphaComponent(0.25).cgColor)
    fill(CGRect(x: x, y: top - stemH, width: bar, height: stemH),
         .white, radius: radius, in: context)
    fill(CGRect(x: x, y: top - bar, width: topW, height: bar),
         .white, radius: radius, in: context)
    // The drooping middle arm — the stumble built into the letterform.
    fill(CGRect(x: x + bar * 0.9, y: top - stemH * 0.56, width: topW * 0.66, height: bar),
         .white, radius: radius, rotation: -12, in: context)
}

// ── Write files + contact sheet.
let options = [option1, option2, option3, option4, option5]
let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("assets/logo-options")
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func writePNG(_ image: NSImage, to url: URL) {
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

for (i, image) in options.enumerated() {
    writePNG(image, to: outDir.appendingPathComponent("option-\(i + 1).png"))
}

let thumb = 460.0, margin = 40.0, labelBand = 70.0
let sheet = NSImage(size: NSSize(width: margin + 5 * (thumb + margin),
                                 height: thumb + 2 * margin + labelBand))
sheet.lockFocus()
NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: sheet.size)).fill()
for (i, image) in options.enumerated() {
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
writePNG(sheet, to: outDir.appendingPathComponent("sheet.png"))
print("Wrote \(outDir.path): option-1..5.png + sheet.png")
