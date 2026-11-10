import AppKit

// Draws Aries Dynamic Island's app icon: a glossy gradient squircle with a black island and a music note.
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.36, blue: 0.55, alpha: 1),
                        NSColor(srgbRed: 0.55, green: 0.32, blue: 0.98, alpha: 1),
                        NSColor(srgbRed: 0.16, green: 0.62, blue: 0.98, alpha: 1)])!
        .draw(in: squircle, angle: -60)
    let iw = rect.width * 0.62, ih = rect.width * 0.2
    let island = NSRect(x: rect.midX - iw / 2, y: rect.maxY - rect.height * 0.2 - ih, width: iw, height: ih)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: island, xRadius: ih / 2, yRadius: ih / 2).fill()
    let dot = ih * 0.36
    NSColor(srgbRed: 0.3, green: 0.95, blue: 0.5, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: island.maxX - ih * 0.5 - dot / 2, y: island.midY - dot / 2, width: dot, height: dot)).fill()
    let cfg = NSImage.SymbolConfiguration(pointSize: rect.width * 0.36, weight: .bold)
    if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: note.size, flipped: false) { r in
            note.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
        }
        let ns = tinted.size
        tinted.draw(in: NSRect(x: rect.midX - ns.width / 2, y: rect.minY + rect.height * 0.16, width: ns.width, height: ns.height))
    }
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
