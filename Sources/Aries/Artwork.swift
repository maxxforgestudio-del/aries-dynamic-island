import AppKit
import SwiftUI
import CoreImage

enum ArtworkLoader {
    static func load(url: URL) async -> NSImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }

    /// Fallback for tracks without embedded art: look it up in the iTunes catalog.
    static func lookup(title: String, artist: String) async -> NSImage? {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [.init(name: "term", value: "\(artist) \(title)"),
                        .init(name: "entity", value: "song"), .init(name: "limit", value: "1")]
        guard let url = c.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let art = first["artworkUrl100"] as? String,
              let big = URL(string: art.replacingOccurrences(of: "100x100", with: "600x600"))
        else { return nil }
        return await load(url: big)
    }
}

extension NSImage {
    var cgImageValue: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }

    /// A vivid colour pulled from the artwork (favours saturated, bright pixels).
    func accentColor() -> NSColor {
        guard let cg = cgImageValue else { return .white }
        let n = 24
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .white }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))

        var scored: [(score: CGFloat, color: NSColor)] = []
        for i in 0..<(n * n) {
            let r = CGFloat(px[i * 4]) / 255, g = CGFloat(px[i * 4 + 1]) / 255, b = CGFloat(px[i * 4 + 2]) / 255
            let c = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            scored.append((s * 0.75 + v * 0.25 - (v < 0.2 ? 1 : 0), c))
        }
        scored.sort { $0.score > $1.score }
        let top = scored.prefix(max(1, scored.count / 8))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for t in top {
            r += t.color.redComponent; g += t.color.greenComponent; b += t.color.blueComponent
        }
        let k = CGFloat(top.count)
        let avg = NSColor(srgbRed: r / k, green: g / k, blue: b / k, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        avg.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        if s < 0.12 { return NSColor(white: 0.92, alpha: 1) }  // greyscale art → soft white
        return NSColor(hue: h, saturation: min(max(s, 0.38), 0.8), brightness: max(v, 0.88), alpha: 1)
    }

    /// A handful of distinct, pleasant colours from the artwork (for the Apple Music–style mesh background).
    func palette(count: Int = 6) -> [Color] {
        guard let cg = cgImageValue else { return [] }
        let n = 12
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var buckets: [Int: (r: Double, g: Double, b: Double, c: Int)] = [:]
        for i in 0..<(n * n) {
            let r = Double(px[i * 4]), g = Double(px[i * 4 + 1]), b = Double(px[i * 4 + 2])
            let key = Int(r / 64) * 16 + Int(g / 64) * 4 + Int(b / 64)
            var e = buckets[key] ?? (0, 0, 0, 0)
            e.r += r; e.g += g; e.b += b; e.c += 1
            buckets[key] = e
        }
        let colors = buckets.values.sorted { $0.c > $1.c }.prefix(count).map { e -> Color in
            let c = NSColor(srgbRed: e.r / Double(e.c) / 255, green: e.g / Double(e.c) / 255, blue: e.b / Double(e.c) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            return Color(nsColor: NSColor(hue: h, saturation: min(1, s * 1.15), brightness: max(0.22, min(0.85, v)), alpha: 1))
        }
        var out = Array(colors)
        while out.count < count, let f = out.first { out.append(f.opacity(0.85)) }
        return out
    }

    /// Small, heavily blurred version used for the animated lyrics backdrop.
    func blurredBackdrop() -> NSImage? {
        guard let cg = cgImageValue else { return nil }
        let ci = CIImage(cgImage: cg)
        let scale = 220 / max(ci.extent.width, 1)
        let small = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 18])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5, kCIInputBrightnessKey: -0.04])
            .cropped(to: small.extent)
        let ctx = CIContext()
        guard let out = ctx.createCGImage(blurred, from: small.extent) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }
}
