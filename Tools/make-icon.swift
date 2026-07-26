#!/usr/bin/env swift
// Draws Eaves's app icon and writes AppIcon.icns.
//
// Committed as source rather than as a binary blob: the icon is ~80 lines of
// AppKit drawing, and keeping it that way means the palette can follow the
// app's own `sand` theme instead of drifting away from it every time either
// one is touched. Run via Tools/make-icon.sh.
//
// The design is the app in miniature: a warm note card, the accent line that
// separates chrome from list, and three rows in the state you most often see
// them — two done, one not.

import AppKit

// The macOS 11+ icon grid: the squircle occupies 824/1024 of the canvas, so
// icons sit at a consistent visual weight next to Apple's own in the Dock.
let canvas: CGFloat = 1024
let inset: CGFloat = 100
let corner: CGFloat = 185

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Straight from Palette.of(.sand) — same surface the app actually paints.
let cardTop = srgb(0.996, 0.988, 0.961)
let cardBottom = srgb(0.972, 0.949, 0.902)
let accent = srgb(0.90, 0.29, 0.31)      // NoteColor.red
let ink = srgb(0.18, 0.17, 0.15)
let inkFaint = srgb(0.55, 0.52, 0.47)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Everything below is authored against a 1024 canvas and scaled once, so
    // the 16pt icon is the same drawing rather than a separate simplified one.
    let k = size / canvas
    ctx.scaleBy(x: k, y: k)

    let body = NSRect(x: inset, y: inset,
                      width: canvas - inset * 2, height: canvas - inset * 2)
    let shape = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)

    // Contact shadow. Small and tight — a large soft shadow reads as a floating
    // sticker, and this is meant to look like paper lying on the desktop.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34,
                  color: srgb(0.20, 0.16, 0.10, 0.34).cgColor)
    cardBottom.setFill()
    shape.fill()
    ctx.restoreGState()

    NSGradient(colors: [cardTop, cardBottom])?.draw(in: shape, angle: -90)

    // Inner rim, so the card keeps an edge against a light wallpaper where the
    // shadow alone disappears.
    srgb(0.62, 0.55, 0.42, 0.30).setStroke()
    shape.lineWidth = 3
    shape.stroke()

    ctx.saveGState()
    shape.addClip()

    // The tab strip and its accent line — the app's own top chrome.
    let stripH: CGFloat = 132
    srgb(0.976, 0.953, 0.902).setFill()
    NSRect(x: body.minX, y: body.maxY - stripH, width: body.width, height: stripH).fill()
    accent.withAlphaComponent(0.85).setFill()
    // 62% filled: the progress line is only meaningful if it is visibly partial.
    NSRect(x: body.minX, y: body.maxY - stripH,
           width: body.width * 0.62, height: 14).fill()

    // Three checklist rows, vertically centred in what the strip leaves behind.
    // Laying them out from the top instead left a visibly heavier bottom margin,
    // which at 32pt reads as the icon being cropped.
    let rowH: CGFloat = 170
    let listSpace = NSRect(x: body.minX, y: body.minY,
                           width: body.width, height: body.height - stripH)
    let firstY = listSpace.midY + rowH
    let boxX = body.minX + 96
    let boxSide: CGFloat = 84

    for i in 0..<3 {
        let done = i < 2
        let cy = firstY - CGFloat(i) * rowH
        let box = NSRect(x: boxX, y: cy - boxSide / 2, width: boxSide, height: boxSide)
        let boxPath = NSBezierPath(roundedRect: box, xRadius: 26, yRadius: 26)

        if done {
            accent.setFill()
            boxPath.fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + 21, y: box.midY + 2))
            tick.line(to: NSPoint(x: box.midX - 4, y: box.minY + 22))
            tick.line(to: NSPoint(x: box.maxX - 18, y: box.maxY - 24))
            tick.lineWidth = 13
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.setStroke()
            tick.stroke()
        } else {
            srgb(0.60, 0.56, 0.50, 0.85).setStroke()
            boxPath.lineWidth = 9
            boxPath.stroke()
        }

        // The text line. Ragged lengths on purpose — three equal bars read as a
        // loading skeleton, not as writing. They run close to the right margin
        // so the card looks written-on rather than mostly empty.
        let widths: [CGFloat] = [488, 404, 452]
        let lineH: CGFloat = 36
        let line = NSRect(x: box.maxX + 54, y: cy - lineH / 2,
                          width: widths[i], height: lineH)
        (done ? inkFaint.withAlphaComponent(0.45) : ink.withAlphaComponent(0.72)).setFill()
        NSBezierPath(roundedRect: line, xRadius: lineH / 2, yRadius: lineH / 2).fill()

        // Strike-through on the completed rows, matching how the app renders them.
        if done {
            inkFaint.withAlphaComponent(0.55).setFill()
            NSRect(x: line.minX, y: cy - 3, width: line.width, height: 6).fill()
        }
    }

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Emit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = "\(out)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset,
                                         withIntermediateDirectories: true)

// The set iconutil expects: each logical size at 1x and 2x.
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                           (256, 1), (256, 2), (512, 1), (512, 2)]

for (pt, scale) in sizes {
    let px = pt * scale
    let rep = drawIcon(size: CGFloat(px))
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    try? data.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
}

// A standalone 512 for the README, where an .icns is not renderable.
if let data = drawIcon(size: 512).representation(using: .png, properties: [:]) {
    try? data.write(to: URL(fileURLWithPath: "\(out)/icon-512.png"))
}

print("wrote \(iconset)")
