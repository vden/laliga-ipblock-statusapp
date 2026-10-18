// Draws Resources/AppIcon.icns: a white ball on a pitch, on the standard macOS
// icon grid (824 pt rounded square centred on a 1024 pt canvas).
//
//   swift tools/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(
        starting: NSColor(srgbRed: 0.24, green: 0.68, blue: 0.36, alpha: 1),
        ending: NSColor(srgbRed: 0.10, green: 0.45, blue: 0.22, alpha: 1)
    )!.draw(in: body, angle: -90)

    // Mown stripes and the halfway line with its centre circle.
    NSColor.white.withAlphaComponent(0.05).setFill()
    for i in stride(from: 0, to: 8, by: 2) {
        NSRect(x: body.minX + CGFloat(i) * 103, y: body.minY, width: 103, height: body.height).fill()
    }
    NSColor.white.withAlphaComponent(0.35).setStroke()
    let lines = NSBezierPath()
    lines.lineWidth = 14
    lines.move(to: NSPoint(x: body.minX, y: 512))
    lines.line(to: NSPoint(x: body.maxX, y: 512))
    lines.appendOval(in: NSRect(x: 512 - 300, y: 512 - 300, width: 600, height: 600))
    lines.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    let ball = NSImage(systemSymbolName: "soccerball", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let side: CGFloat = 470
    let scale = side / max(ball.size.width, ball.size.height)
    let size = NSSize(width: ball.size.width * scale, height: ball.size.height * scale)
    NSGraphicsContext.saveGraphicsState()
    let ballShadow = NSShadow()
    ballShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    ballShadow.shadowOffset = NSSize(width: 0, height: -12)
    ballShadow.shadowBlurRadius = 20
    ballShadow.set()
    ball.draw(in: NSRect(x: 512 - size.width / 2, y: 512 - size.height / 2,
                         width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try render(pt).write(to: iconset.appending(path: "icon_\(pt)x\(pt).png"))
    try render(pt * 2).write(to: iconset.appending(path: "icon_\(pt)x\(pt)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
