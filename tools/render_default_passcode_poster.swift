import AppKit

// The source artwork is AI-generated. AppKit places the numerals on the same
// 915 × 1148 grid that KeypadSlicer uses, so the labels survive exact slicing.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Resources/DefaultPasscodeBackground.png")
let destination = root.appendingPathComponent("Resources/DefaultPasscodePoster.png")
guard let artwork = NSImage(contentsOf: source) else {
    fatalError("Could not load \(source.path)")
}

let width = 915
let height = 1148
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create the poster canvas")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
artwork.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
             from: .zero, operation: .copy, fraction: 1)

let labels = [
    ("壹", 0, 0), ("贰", 0, 1), ("叁", 0, 2),
    ("肆", 1, 0), ("伍", 1, 1), ("陆", 1, 2),
    ("柒", 2, 0), ("捌", 2, 1), ("玖", 2, 2),
    ("零", 3, 1),
]
let font = NSFont(name: "Songti SC", size: 106)
    ?? NSFont.systemFont(ofSize: 106, weight: .medium)
let gold = NSColor(calibratedRed: 0.86, green: 0.72, blue: 0.48, alpha: 1)
let ivory = NSColor(calibratedRed: 1, green: 0.94, blue: 0.78, alpha: 1)

for (glyph, row, column) in labels {
    let center = NSPoint(x: (CGFloat(column) + 0.5) * 305,
                         y: CGFloat(height) - (CGFloat(row) + 0.5) * 287)
    let disc = NSRect(x: center.x - 110, y: center.y - 110,
                      width: 220, height: 220)

    let halo = NSBezierPath(ovalIn: disc.insetBy(dx: -5, dy: -5))
    NSColor(calibratedRed: 0.78, green: 0.65, blue: 0.39, alpha: 0.11).setFill()
    halo.fill()

    let circle = NSBezierPath(ovalIn: disc)
    NSColor(calibratedRed: 0.035, green: 0.085, blue: 0.14, alpha: 0.90).setFill()
    circle.fill()
    gold.setStroke()
    circle.lineWidth = 2.5
    circle.stroke()

    let inner = NSBezierPath(ovalIn: disc.insetBy(dx: 7, dy: 7))
    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    inner.lineWidth = 1
    inner.stroke()

    let text = NSAttributedString(string: glyph, attributes: [
        .font: font,
        .foregroundColor: ivory,
        .shadow: {
            let shadow = NSShadow()
            shadow.shadowColor = gold.withAlphaComponent(0.45)
            shadow.shadowBlurRadius = 8
            return shadow
        }(),
    ])
    let textSize = text.size()
    text.draw(at: NSPoint(x: center.x - textSize.width / 2,
                          y: center.y - textSize.height / 2 + 7))
}

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the poster")
}
try png.write(to: destination)
print(destination.path)
