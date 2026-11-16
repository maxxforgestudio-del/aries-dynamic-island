import AppKit

// Builds the Aries app icon from the brand logo (Resources/Branding/AriesLogo.png):
// the chrome "A" mark on a deep black macOS squircle with a soft rim light.
let logoPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/Branding/AriesLogo.png"
guard let logo = NSImage(contentsOfFile: logoPath),
      let cg = logo.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("logo not found") }

// The "A" + orbit area of the 1254×1254 artwork (top-left origin).
let scaleK = CGFloat(cg.width) / 1254
let markRect = CGRect(x: 185 * scaleK, y: 225 * scaleK, width: 900 * scaleK, height: 580 * scaleK)
let rawMark = cg.cropping(to: markRect)!

// Feather the crop's edges so the artwork's black background melts into the tile.
let mark: NSImage = {
    let size = NSSize(width: rawMark.width, height: rawMark.height)
    let img = NSImage(size: size)
    img.lockFocus()
    NSImage(cgImage: rawMark, size: size).draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.current?.compositingOperation = .destinationIn
    NSGradient(colorsAndLocations: (NSColor.white, 0.0), (NSColor.white, 0.72), (NSColor.white.withAlphaComponent(0), 1.0))!
        .draw(in: NSRect(x: -size.width * 0.08, y: -size.height * 0.12, width: size.width * 1.16, height: size.height * 1.24),
              relativeCenterPosition: .zero)
    img.unlockFocus()
    return img
}()

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.098
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.02, alpha: 1)])!.draw(in: rect, angle: -90)
    // soft top glow
    NSGradient(colors: [NSColor(white: 1, alpha: 0.10), NSColor(white: 1, alpha: 0)])!
        .draw(fromCenter: NSPoint(x: rect.midX, y: rect.maxY), radius: 0,
              toCenter: NSPoint(x: rect.midX, y: rect.maxY), radius: rect.width * 0.7, options: [])
    let w = rect.width * 0.86
    let h = w * mark.size.height / mark.size.width
    mark.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2 + rect.height * 0.02, width: w, height: h),
              from: .zero, operation: .screen, fraction: 1)
    NSGraphicsContext.current?.restoreGraphicsState()

    // rim light
    NSColor(white: 1, alpha: 0.16).setStroke()
    squircle.lineWidth = max(1, s * 0.004)
    squircle.stroke()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
