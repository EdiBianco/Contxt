// One-off asset generator for the app icon (not part of the app).
// Run: swift scripts/make-app-icon.swift <out-dir>, then: iconutil -c icns <out-dir>/AppIcon.iconset
// Matches the website favicon: eight dots on a ring around a blue center, on a dark squircle.

import AppKit

func draw(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = size / 1024
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    // Soft elevation shadow under the body.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.23, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(calibratedRed: 0.17, green: 0.21, blue: 0.44, alpha: 1),
                        NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.23, alpha: 1)])!
        .draw(in: squircle, angle: -90)

    let center = CGPoint(x: 512 * s, y: 512 * s)
    NSColor.white.withAlphaComponent(0.96).setFill()
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4
        let x = center.x + sin(angle) * 257 * s
        let y = center.y + cos(angle) * 257 * s
        NSBezierPath(ovalIn: CGRect(x: x - 67 * s, y: y - 67 * s, width: 134 * s, height: 134 * s)).fill()
    }
    NSColor(calibratedRed: 0.43, green: 0.66, blue: 1, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: center.x - 88 * s, y: center.y - 88 * s, width: 176 * s, height: 176 * s)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
let set = "\(out)/AppIcon.iconset"
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(size: CGFloat(px)).write(to: URL(fileURLWithPath: "\(set)/icon_\(name).png"))
}
print("wrote \(set)")
