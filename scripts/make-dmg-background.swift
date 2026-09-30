// Draws the DMG window background: a soft gradient with an arrow from the app to the Applications folder.
// Writes a 1x and a 2x PNG that `make-dmg.sh` combines into one Retina TIFF.
// Usage: swift scripts/make-dmg-background.swift <output-directory>
import AppKit

// Must match the window size and icon positions in make-dmg.sh.
let windowSize = CGSize(width: 540, height: 380)
let appCenter = CGPoint(x: 140, y: 180)
let applicationsCenter = CGPoint(x: 400, y: 180)

func render(scale: Int) -> Data {
    let width = Int(windowSize.width) * scale
    let height = Int(windowSize.height) * scale
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    // Size in points: this makes the 2x image report 144 dpi, and drawing below is in points too.
    rep.size = windowSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    draw(in: ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func draw(in ctx: CGContext) {
    let space = CGColorSpaceCreateDeviceRGB()
    // Light, calm background: Finder draws icon labels in black on DMG windows.
    let colors = [CGColor(red: 0.96, green: 0.96, blue: 1.0, alpha: 1), CGColor(red: 0.89, green: 0.94, blue: 0.97, alpha: 1)] as CFArray
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!,
                           start: CGPoint(x: 0, y: windowSize.height), end: CGPoint(x: 0, y: 0), options: [])

    // Finder's coordinates are top-left; CoreGraphics' are bottom-left.
    let y = windowSize.height - appCenter.y
    let start = CGPoint(x: appCenter.x + 78, y: y)
    let end = CGPoint(x: applicationsCenter.x - 78, y: y)

    let indigo = CGColor(red: 0.26, green: 0.22, blue: 0.79, alpha: 1)
    let teal = CGColor(red: 0.05, green: 0.45, blue: 0.56, alpha: 1)
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Shaft as a gradient stroke from indigo to teal.
    ctx.saveGState()
    ctx.move(to: start)
    ctx.addLine(to: CGPoint(x: end.x - 6, y: y))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: [indigo, teal] as CFArray, locations: [0, 1])!,
                           start: start, end: end, options: [])
    ctx.restoreGState()

    // Arrow head.
    ctx.setStrokeColor(teal)
    ctx.move(to: CGPoint(x: end.x - 16, y: y + 14))
    ctx.addLine(to: end)
    ctx.addLine(to: CGPoint(x: end.x - 16, y: y - 14))
    ctx.strokePath()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let text = NSAttributedString(
        string: "Drag FocusFollow to Applications",
        attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1),
            .paragraphStyle: paragraph,
        ])
    let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    text.draw(in: CGRect(x: 0, y: windowSize.height - 78, width: windowSize.width, height: 24))
    NSGraphicsContext.restoreGraphicsState()
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-dmg-background.swift <output-directory>\n".utf8))
    exit(1)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try render(scale: 1).write(to: directory.appendingPathComponent("background.png"))
try render(scale: 2).write(to: directory.appendingPathComponent("background@2x.png"))
print("Wrote background.png and background@2x.png to \(directory.path)")
