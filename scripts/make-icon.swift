// Draws the FocusFollow app icon and writes every size the asset catalog needs.
// Usage: swift scripts/make-icon.swift FocusFollow/Assets.xcassets/AppIcon.appiconset
import AppKit

let size: CGFloat = 1024

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / size
    ctx.scaleBy(x: scale, y: scale)
    draw(in: ctx, scale: scale)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// `scale` is the pixels-per-point factor; shadows are specified in device pixels, so they need it explicitly.
func draw(in ctx: CGContext, scale: CGFloat) {
    let space = CGColorSpaceCreateDeviceRGB()
    let inset: CGFloat = 100
    let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 28 * scale, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.5, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient, deep indigo at the top to teal at the bottom.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let colors = [CGColor(red: 0.27, green: 0.22, blue: 0.78, alpha: 1),
                  CGColor(red: 0.05, green: 0.55, blue: 0.80, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
    // Gentle highlight on the top half.
    let glow = [CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0)] as CFArray
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: glow, locations: [0, 1])!,
                           start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: 512), options: [])
    ctx.restoreGState()

    // Focus brackets in the four corners of the tile.
    let arm: CGFloat = 120, gap: CGFloat = 130, thickness: CGFloat = 34
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
    ctx.setLineWidth(thickness)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let left = tile.minX + gap, right = tile.maxX - gap, bottom = tile.minY + gap, top = tile.maxY - gap
    for (cx, cy, dx, dy) in [(left, top, 1.0, -1.0), (right, top, -1.0, -1.0), (left, bottom, 1.0, 1.0), (right, bottom, -1.0, 1.0)] {
        ctx.move(to: CGPoint(x: cx + dx * arm, y: cy))
        ctx.addLine(to: CGPoint(x: cx, y: cy))
        ctx.addLine(to: CGPoint(x: cx, y: cy + dy * arm))
    }
    ctx.strokePath()

    // Eye: almond outline filled white.
    let eyeW: CGFloat = 400, eyeH: CGFloat = 250
    let c = CGPoint(x: 512, y: 512)
    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: c.x - eyeW / 2, y: c.y))
    eye.addQuadCurve(to: CGPoint(x: c.x + eyeW / 2, y: c.y), control: CGPoint(x: c.x, y: c.y + eyeH * 1.05))
    eye.addQuadCurve(to: CGPoint(x: c.x - eyeW / 2, y: c.y), control: CGPoint(x: c.x, y: c.y - eyeH * 1.05))
    eye.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 14 * scale, color: CGColor(gray: 0, alpha: 0.25))
    ctx.addPath(eye)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Iris and pupil, clipped to the eye.
    ctx.saveGState()
    ctx.addPath(eye)
    ctx.clip()
    let irisR: CGFloat = 112
    let iris = CGRect(x: c.x - irisR, y: c.y - irisR, width: irisR * 2, height: irisR * 2)
    ctx.setFillColor(CGColor(red: 0.10, green: 0.42, blue: 0.85, alpha: 1))
    ctx.fillEllipse(in: iris)
    let pupilR: CGFloat = 52
    ctx.setFillColor(CGColor(red: 0.04, green: 0.08, blue: 0.25, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: c.x - pupilR, y: c.y - pupilR, width: pupilR * 2, height: pupilR * 2))
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: c.x + 22, y: c.y + 26, width: 40, height: 40))
    ctx.restoreGState()
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <AppIcon.appiconset dir>\n".utf8))
    exit(1)
}
let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let files: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for file in files {
    try render(pixels: file.pixels).write(to: dir.appendingPathComponent(file.name))
}
print("Wrote \(files.count) icons to \(dir.path)")
