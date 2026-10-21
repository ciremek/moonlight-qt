// Draws the DMG window background, at 1x and 2x, then combines them into
// background.tiff next to this script:
//   swift scripts/dmg/make-background.swift
//
// The layout matches package-moonvibe.sh: a 660x400 window with Moonvibe's icon
// centered at (170, 170) and the Applications link at (490, 170), top-left origin.

import AppKit

let size = NSSize(width: 660, height: 400)
let indigo = NSColor(srgbRed: 0x4F / 255, green: 0x5B / 255, blue: 0xD5 / 255, alpha: 1)
let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                               pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Drawing uses a bottom-left origin: y = size.height - top
    func y(_ top: CGFloat) -> CGFloat { size.height - top }

    // Soft lavender, lighter at the top
    NSGradient(starting: NSColor(srgbRed: 0.973, green: 0.973, blue: 0.992, alpha: 1),
               ending: NSColor(srgbRed: 0.918, green: 0.922, blue: 0.973, alpha: 1))!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // A faint halo behind each icon slot
    for center in [CGPoint(x: 170, y: y(170)), CGPoint(x: 490, y: y(170))] {
        let halo = NSGradient(starting: indigo.withAlphaComponent(0.10), ending: indigo.withAlphaComponent(0))!
        halo.draw(fromCenter: center, radius: 0, toCenter: center, radius: 110, options: [])
    }

    // The arrow, from Moonvibe toward Applications
    let arrow = NSBezierPath()
    arrow.lineWidth = 6
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: CGPoint(x: 268, y: y(170)))
    arrow.line(to: CGPoint(x: 388, y: y(170)))
    arrow.move(to: CGPoint(x: 366, y: y(148)))
    arrow.line(to: CGPoint(x: 390, y: y(170)))
    arrow.line(to: CGPoint(x: 366, y: y(192)))
    indigo.withAlphaComponent(0.85).setStroke()
    arrow.stroke()

    // Caption, English then French
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = NSAttributedString(string: "Drag Moonvibe to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.22, green: 0.24, blue: 0.36, alpha: 1),
        .paragraphStyle: paragraph,
    ])
    let subtitle = NSAttributedString(string: "Glisse Moonvibe dans Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(srgbRed: 0.42, green: 0.44, blue: 0.56, alpha: 1),
        .paragraphStyle: paragraph,
    ])
    title.draw(in: NSRect(x: 0, y: y(312), width: size.width, height: 24))
    subtitle.draw(in: NSRect(x: 0, y: y(334), width: size.width, height: 18))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (scale, name) in [(CGFloat(1), "background.png"), (CGFloat(2), "background@2x.png")] {
    try! render(scale: scale).representation(using: .png, properties: [:])!
        .write(to: directory.appendingPathComponent(name))
}

let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", "background.png", "background@2x.png", "-out", "background.tiff"]
tiffutil.currentDirectoryURL = directory
try! tiffutil.run()
tiffutil.waitUntilExit()
for name in ["background.png", "background@2x.png"] {
    try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
}
print("Wrote", directory.appendingPathComponent("background.tiff").path)
