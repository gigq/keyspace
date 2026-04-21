#!/usr/bin/env swift
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
          data: nil,
          width: Int(size),
          height: Int(size),
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    fputs("failed to create context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1.0) -> NSColor {
    NSColor(srgbRed: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: a)
}

let bg = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
    xRadius: size * 0.2237,
    yRadius: size * 0.2237
)

let bgGradient = NSGradient(colors: [
    rgb(79, 96, 196),
    rgb(47, 56, 138)
])!
bgGradient.draw(in: bg, angle: -90)

let innerShadow = NSShadow()
innerShadow.shadowColor = NSColor(white: 0, alpha: 0.25)
innerShadow.shadowOffset = NSSize(width: 0, height: -8)
innerShadow.shadowBlurRadius = 24

let keycapInset: CGFloat = size * 0.18
let keycapRect = NSRect(
    x: keycapInset,
    y: keycapInset,
    width: size - keycapInset * 2,
    height: size - keycapInset * 2
)
let keycapRadius = size * 0.09

NSGraphicsContext.current?.saveGraphicsState()
let dropShadow = NSShadow()
dropShadow.shadowColor = NSColor(white: 0, alpha: 0.35)
dropShadow.shadowOffset = NSSize(width: 0, height: -12)
dropShadow.shadowBlurRadius = 32
dropShadow.set()

let keycapSide = NSBezierPath(roundedRect: keycapRect, xRadius: keycapRadius, yRadius: keycapRadius)
let keycapSideGradient = NSGradient(colors: [
    rgb(232, 234, 244),
    rgb(184, 190, 214)
])!
keycapSideGradient.draw(in: keycapSide, angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

let topInset: CGFloat = size * 0.04
let topRect = NSRect(
    x: keycapRect.minX + topInset,
    y: keycapRect.minY + topInset * 2,
    width: keycapRect.width - topInset * 2,
    height: keycapRect.height - topInset * 2.5
)
let topRadius = keycapRadius * 0.85
let keycapTop = NSBezierPath(roundedRect: topRect, xRadius: topRadius, yRadius: topRadius)
let keycapTopGradient = NSGradient(colors: [
    rgb(255, 255, 255),
    rgb(222, 226, 240)
])!
keycapTopGradient.draw(in: keycapTop, angle: -90)

let gridCols = 3
let gridRows = 3
let gridPadding: CGFloat = topRect.width * 0.13
let gridGap: CGFloat = topRect.width * 0.04
let gridArea = NSRect(
    x: topRect.minX + gridPadding,
    y: topRect.minY + gridPadding,
    width: topRect.width - gridPadding * 2,
    height: topRect.height - gridPadding * 2
)
let cellW = (gridArea.width - gridGap * CGFloat(gridCols - 1)) / CGFloat(gridCols)
let cellH = (gridArea.height - gridGap * CGFloat(gridRows - 1)) / CGFloat(gridRows)
let cellRadius = min(cellW, cellH) * 0.22

let activeCol = 1
let activeRow = 1

for row in 0..<gridRows {
    for col in 0..<gridCols {
        let cell = NSRect(
            x: gridArea.minX + CGFloat(col) * (cellW + gridGap),
            y: gridArea.minY + CGFloat(gridRows - 1 - row) * (cellH + gridGap),
            width: cellW,
            height: cellH
        )
        let path = NSBezierPath(roundedRect: cell, xRadius: cellRadius, yRadius: cellRadius)
        if row == activeRow && col == activeCol {
            let activeGradient = NSGradient(colors: [
                rgb(93, 114, 232),
                rgb(62, 82, 196)
            ])!
            activeGradient.draw(in: path, angle: -90)
        } else {
            rgb(200, 206, 226, 0.85).setFill()
            path.fill()
        }
    }
}

let highlightRect = NSRect(
    x: topRect.minX,
    y: topRect.maxY - topRect.height * 0.22,
    width: topRect.width,
    height: topRect.height * 0.22
)
NSGraphicsContext.current?.saveGraphicsState()
NSBezierPath(roundedRect: topRect, xRadius: topRadius, yRadius: topRadius).addClip()
let highlight = NSGradient(colors: [
    NSColor(white: 1, alpha: 0.55),
    NSColor(white: 1, alpha: 0.0)
])!
highlight.draw(in: highlightRect, angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()

guard let cgImage = ctx.makeImage() else {
    fputs("failed to make image\n", stderr)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to encode png\n", stderr)
    exit(1)
}
let url = URL(fileURLWithPath: outPath)
do {
    try data.write(to: url)
    print("wrote \(outPath)")
} catch {
    fputs("failed to write: \(error)\n", stderr)
    exit(1)
}
