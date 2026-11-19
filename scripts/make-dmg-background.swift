// One-off asset generator for the installer window background (not part of the app).
// Run: swift scripts/make-dmg-background.swift <out-dir>
// Produces <out-dir>/dmg-background.tiff (1x + 2x). Layout must match Resources/dmg-settings.py.

import AppKit

let width: CGFloat = 660
let height: CGFloat = 400

func draw() {
    let canvas = NSRect(x: 0, y: 0, width: width, height: height)

    NSGradient(colors: [NSColor(calibratedRed: 0.105, green: 0.14, blue: 0.22, alpha: 1),
                        NSColor(calibratedRed: 0.075, green: 0.10, blue: 0.17, alpha: 1)])!
        .draw(in: canvas, angle: -90)

    // Soft glow under the illustration.
    let glow = NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.80, alpha: 0.42),
                                   NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.80, alpha: 0)])!
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: width / 2, yBy: 285)
    transform.scaleX(by: 1.7, yBy: 0.62)
    transform.concat()
    glow.draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: 150, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Ring motif (matches the app icon): six dots around a center dot.
    let center = CGPoint(x: width / 2, y: 290)
    NSColor(calibratedRed: 0.353, green: 0.549, blue: 1, alpha: 1).setFill()
    for i in 0..<6 {
        let angle = CGFloat(i) * 2 * .pi / 6 - .pi / 2
        let x = center.x + cos(angle) * 40
        let y = center.y - sin(angle) * 40
        NSBezierPath(ovalIn: CGRect(x: x - 12, y: y - 12, width: 24, height: 24)).fill()
    }
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)).fill()

    // Title.
    let title = "Contxt" as NSString
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 26, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
    let titleSize = title.size(withAttributes: titleAttrs)
    title.draw(at: NSPoint(x: (width - titleSize.width) / 2, y: 205), withAttributes: titleAttrs)

    // Arrow between the two icons (icons sit at y=265 from the top, i.e. 135 from the bottom).
    NSColor.white.withAlphaComponent(0.9).setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 272, y: 135))
    arrow.line(to: NSPoint(x: 388, y: 135))
    arrow.move(to: NSPoint(x: 370, y: 152))
    arrow.line(to: NSPoint(x: 389, y: 135))
    arrow.line(to: NSPoint(x: 370, y: 118))
    arrow.stroke()

    // Plates under the Finder labels so they stay readable.
    NSColor.white.withAlphaComponent(0.93).setFill()
    for x: CGFloat in [180, 480] {
        NSBezierPath(roundedRect: NSRect(x: x - 72, y: 49, width: 144, height: 24), xRadius: 12, yRadius: 12).fill()
    }

    // Instruction.
    let text = "Drag Contxt to your Applications" as NSString
    let textAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.88),
    ]
    let textSize = text.size(withAttributes: textAttrs)
    text.draw(at: NSPoint(x: (width - textSize.width) / 2, y: 14), withAttributes: textAttrs)
}

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .tiff, properties: [:])!
}

let out = CommandLine.arguments[1]
try! FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
try! render(scale: 1).write(to: URL(fileURLWithPath: "\(out)/bg.tiff"))
try! render(scale: 2).write(to: URL(fileURLWithPath: "\(out)/bg@2x.tiff"))
print("wrote \(out)")
