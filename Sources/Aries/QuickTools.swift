import AppKit
import SwiftUI
import IOKit.pwr_mgt

/// The Tools tab: little one-tap helpers that live in the notch.
final class ToolsModel: ObservableObject {
    // MARK: Keep Awake

    /// When the Mac may sleep again. `.distantFuture` means "until I turn it off".
    @Published private(set) var awakeUntil: Date?
    private var assertion: IOPMAssertionID = 0
    private var awakeTimer: Timer?

    var isAwake: Bool { awakeUntil != nil }

    func keepAwake(minutes: Double?) {
        stopAwake()
        let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "Aries Keep Awake" as CFString, &assertion)
        guard ok == kIOReturnSuccess else { return }
        if let m = minutes {
            awakeUntil = Date().addingTimeInterval(m * 60)
            awakeTimer = Timer.scheduledTimer(withTimeInterval: m * 60, repeats: false) { [weak self] _ in self?.stopAwake() }
        } else {
            awakeUntil = .distantFuture
        }
    }

    func stopAwake() {
        awakeTimer?.invalidate(); awakeTimer = nil
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        if awakeUntil != nil { awakeUntil = nil }
    }

    func awakeLabel(at d: Date = Date()) -> String {
        guard let u = awakeUntil else { return "Off" }
        if u == .distantFuture { return "On" }
        let m = max(1, Int(ceil(u.timeIntervalSince(d) / 60)))
        return m >= 60 ? "\(m / 60)h \(m % 60)m left" : "\(m)m left"
    }

    // MARK: Colour picker

    @Published private(set) var colors: [String] = UserDefaults.standard.stringArray(forKey: "tools.colors") ?? []

    func pickColor(_ done: @escaping (String?) -> Void) {
        NSColorSampler().show { [weak self] c in
            guard let self, let c = c?.usingColorSpace(.sRGB) else { done(nil); return }
            let hex = String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                             Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
            self.copy(hex)
            self.colors.removeAll { $0 == hex }
            self.colors.insert(hex, at: 0)
            self.colors = Array(self.colors.prefix(6))
            UserDefaults.standard.set(self.colors, forKey: "tools.colors")
            done(hex)
        }
    }

    func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    // MARK: System helpers

    static var isDarkMode: Bool { UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" }

    /// Flips Light/Dark for the whole Mac (macOS asks once to let Aries use System Events).
    func toggleDarkMode(_ done: @escaping (Bool?) -> Void) {
        LocalPlayers.queue.async {
            let s = NSAppleScript(source: """
                tell application "System Events" to tell appearance preferences
                    set dark mode to not dark mode
                    return dark mode
                end tell
                """)
            var err: NSDictionary?
            let r = s?.executeAndReturnError(&err)
            DispatchQueue.main.async { done(err == nil ? r?.booleanValue : nil) }
        }
    }

    func sleepScreen() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
    }

    func screenshot() {
        let app = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Calculator & converter

/// A tiny, safe calculator: + − × ÷ ^ %, brackets, sqrt/sin/cos/tan/log/ln, pi and e —
/// plus unit conversions like "5 km to mi", "72 f in c" or "2 cups to ml".
enum QuickMath {
    static func evaluate(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let c = convert(s) { return c }
        var p = Parser(s.lowercased())
        guard let v = p.parse(), v.isFinite else { return nil }
        // A bare number isn't worth echoing back.
        if Double(s.replacingOccurrences(of: ",", with: "")) != nil { return nil }
        return format(v)
    }

    static func format(_ v: Double) -> String {
        if abs(v) >= 1e15 || (abs(v) < 1e-6 && v != 0) { return String(format: "%.6g", v) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = abs(v) < 1 ? 8 : 6
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    // MARK: Units

    private struct Unit { let names: [String]; let kind: String; let factor: Double }
    private static let units: [Unit] = [
        .init(names: ["mm", "millimeter", "millimeters"], kind: "len", factor: 0.001),
        .init(names: ["cm", "centimeter", "centimeters"], kind: "len", factor: 0.01),
        .init(names: ["m", "meter", "meters", "metre", "metres"], kind: "len", factor: 1),
        .init(names: ["km", "kilometer", "kilometers", "kilometre", "kilometres"], kind: "len", factor: 1000),
        .init(names: ["in", "inch", "inches", "\""], kind: "len", factor: 0.0254),
        .init(names: ["ft", "foot", "feet", "'"], kind: "len", factor: 0.3048),
        .init(names: ["yd", "yard", "yards"], kind: "len", factor: 0.9144),
        .init(names: ["mi", "mile", "miles"], kind: "len", factor: 1609.344),
        .init(names: ["mg", "milligram", "milligrams"], kind: "mass", factor: 0.000001),
        .init(names: ["g", "gram", "grams"], kind: "mass", factor: 0.001),
        .init(names: ["kg", "kilo", "kilos", "kilogram", "kilograms"], kind: "mass", factor: 1),
        .init(names: ["oz", "ounce", "ounces"], kind: "mass", factor: 0.028349523125),
        .init(names: ["lb", "lbs", "pound", "pounds"], kind: "mass", factor: 0.45359237),
        .init(names: ["st", "stone"], kind: "mass", factor: 6.35029318),
        .init(names: ["ml", "milliliter", "milliliters"], kind: "vol", factor: 0.001),
        .init(names: ["l", "liter", "liters", "litre", "litres"], kind: "vol", factor: 1),
        .init(names: ["floz", "fl oz"], kind: "vol", factor: 0.0295735295625),
        .init(names: ["cup", "cups"], kind: "vol", factor: 0.2365882365),
        .init(names: ["qt", "quart", "quarts"], kind: "vol", factor: 0.946352946),
        .init(names: ["gal", "gallon", "gallons"], kind: "vol", factor: 3.785411784),
        .init(names: ["kmh", "km/h", "kph"], kind: "speed", factor: 1 / 3.6),
        .init(names: ["mph"], kind: "speed", factor: 0.44704),
        .init(names: ["m/s", "mps"], kind: "speed", factor: 1),
        .init(names: ["kn", "knot", "knots"], kind: "speed", factor: 0.514444),
        .init(names: ["kb"], kind: "data", factor: 1e3),
        .init(names: ["mb"], kind: "data", factor: 1e6),
        .init(names: ["gb"], kind: "data", factor: 1e9),
        .init(names: ["tb"], kind: "data", factor: 1e12),
        .init(names: ["s", "sec", "secs", "second", "seconds"], kind: "time", factor: 1),
        .init(names: ["min", "mins", "minute", "minutes"], kind: "time", factor: 60),
        .init(names: ["h", "hr", "hrs", "hour", "hours"], kind: "time", factor: 3600),
        .init(names: ["d", "day", "days"], kind: "time", factor: 86400),
        .init(names: ["wk", "week", "weeks"], kind: "time", factor: 604800),
    ]
    private static let temps: [String: String] = ["c": "c", "°c": "c", "celsius": "c", "f": "f", "°f": "f",
                                                  "fahrenheit": "f", "k": "k", "kelvin": "k"]

    private static func convert(_ s: String) -> String? {
        let pattern = #"^\s*(-?[\d.,]+)\s*([a-z°/"' ]+?)\s+(?:to|in|as|=)\s+([a-z°/"' ]+?)\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges == 4,
              let r1 = Range(m.range(at: 1), in: s), let r2 = Range(m.range(at: 2), in: s), let r3 = Range(m.range(at: 3), in: s),
              let value = Double(s[r1].replacingOccurrences(of: ",", with: ""))
        else { return nil }
        let from = s[r2].lowercased().trimmingCharacters(in: .whitespaces)
        let to = s[r3].lowercased().trimmingCharacters(in: .whitespaces)

        if let a = temps[from], let b = temps[to] {
            let c: Double = a == "c" ? value : (a == "f" ? (value - 32) * 5 / 9 : value - 273.15)
            let out: Double = b == "c" ? c : (b == "f" ? c * 9 / 5 + 32 : c + 273.15)
            return "\(format(out)) °\(b.uppercased())"
        }
        guard let a = units.first(where: { $0.names.contains(from) }),
              let b = units.first(where: { $0.names.contains(to) }), a.kind == b.kind else { return nil }
        return "\(format(value * a.factor / b.factor)) \(b.names[0])"
    }

    // MARK: Expression parser (recursive descent; never evaluates code)

    private struct Parser {
        let c: [Character]
        var i = 0
        init(_ s: String) {
            c = Array(s.replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "π", with: "pi")
                .replacingOccurrences(of: " of ", with: "*")
                .filter { !$0.isWhitespace })
        }

        mutating func parse() -> Double? {
            guard let v = expr(), i == c.count else { return nil }
            return v
        }

        private var peek: Character? { i < c.count ? c[i] : nil }

        private mutating func expr() -> Double? {
            guard var v = term() else { return nil }
            while let ch = peek, ch == "+" || ch == "-" {
                i += 1
                guard let r = term() else { return nil }
                v = ch == "+" ? v + r : v - r
            }
            return v
        }

        private mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while let ch = peek, ch == "*" || ch == "/" || ch == "x" || (ch == "(" ) || ch.isLetter {
                if ch == "(" || (ch.isLetter && ch != "x") {           // implicit multiply: 2(3), 2pi
                    guard let r = power() else { return nil }
                    v *= r
                    continue
                }
                i += 1
                guard let r = power() else { return nil }
                v = ch == "/" ? v / r : v * r
            }
            return v
        }

        private mutating func power() -> Double? {
            guard let b = unary() else { return nil }
            if peek == "^" {
                i += 1
                guard let e = power() else { return nil }
                return pow(b, e)
            }
            return b
        }

        private mutating func unary() -> Double? {
            if peek == "-" { i += 1; return unary().map { -$0 } }
            if peek == "+" { i += 1; return unary() }
            return postfix()
        }

        private mutating func postfix() -> Double? {
            guard var v = primary() else { return nil }
            while peek == "%" { i += 1; v /= 100 }
            return v
        }

        private mutating func primary() -> Double? {
            guard let ch = peek else { return nil }
            if ch == "(" {
                i += 1
                let v = expr()
                guard peek == ")" else { return nil }
                i += 1
                return v
            }
            if ch.isNumber || ch == "." {
                var s = ""
                while let d = peek, d.isNumber || d == "." { s.append(d); i += 1 }
                return Double(s)
            }
            if ch.isLetter {
                var name = ""
                while let d = peek, d.isLetter { name.append(d); i += 1 }
                switch name {
                case "pi": return .pi
                case "e": return M_E
                default: break
                }
                let fns: [String: (Double) -> Double] = [
                    "sqrt": { $0.squareRoot() }, "sin": { sin($0 * .pi / 180) }, "cos": { cos($0 * .pi / 180) },
                    "tan": { tan($0 * .pi / 180) }, "log": { log10($0) }, "ln": { log($0) }, "abs": { abs($0) },
                    "round": { $0.rounded() },
                ]
                guard let f = fns[name], let arg = postfix() else { return nil }
                return f(arg)
            }
            return nil
        }
    }
}

// MARK: - Tab

struct ToolsTab: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var tools: ToolsModel
    @ViewState private var input = ""
    @ViewState private var coin: Bool? = nil
    @ViewState private var spin = 0.0
    @ViewState private var dark = ToolsModel.isDarkMode
    @FocusState private var focused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            calculator.frame(width: 214)
            LazyVGrid(columns: columns, spacing: 7) {
                awakeTile
                ToolTile(icon: "eyedropper.halffull", title: "Color Picker",
                         detail: tools.colors.first ?? "Pick any pixel", tint: .pink,
                         swatch: tools.colors.first.map(Self.color)) {
                    tools.pickColor { hex in
                        guard let hex else { return }
                        model.confirm("eyedropper.full", "\(hex) copied")
                    }
                }
                ToolTile(icon: "camera.viewfinder", title: "Screenshot", detail: "Capture area", tint: .cyan) {
                    model.collapse()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { tools.screenshot() }
                }
                ToolTile(icon: dark ? "moon.fill" : "sun.max.fill", title: "Appearance",
                         detail: dark ? "Dark" : "Light", tint: .indigo, active: dark) {
                    tools.toggleDarkMode { r in
                        if let r { withAnimation(.spring) { dark = r } }
                        else { model.confirm("exclamationmark.triangle.fill", "Allow System Events in Settings") }
                    }
                }
                ToolTile(icon: "lock.display", title: "Sleep Screen", detail: "Lock now", tint: .teal) {
                    model.collapse()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { tools.sleepScreen() }
                }
                coinTile
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .onChange(of: focused) { _, f in model.isEditing = f }
        .onAppear { dark = ToolsModel.isDarkMode }
    }

    // MARK: Calculator

    private var calculator: some View {
        let result = QuickMath.evaluate(input)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "function").font(.system(size: 12, weight: .bold)).foregroundStyle(.orange)
                TextField("Calculate or convert…", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit { if let r = result { copyResult(r) } }
                if !input.isEmpty {
                    Button { input = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(focused ? 0.13 : 0.08)))
            .onTapGesture { AppDelegate.shared.focusIsland(); focused = true }

            Group {
                if let r = result {
                    Button { copyResult(r) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("=").foregroundStyle(.orange)
                            Text(r).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                                .contentTransition(.numericText())
                        }
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    }
                    .buttonStyle(.plain)
                    .help("Click or press Return to copy")
                } else {
                    Text(input.isEmpty ? "Try 18% of 240, (12+8)/3,\n5 km to mi or 72 f to c" : "…")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: result)

            if !tools.colors.isEmpty {
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text("Colors").font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                    ForEach(tools.colors, id: \.self) { hex in
                        Button { tools.copy(hex); model.confirm("eyedropper.full", "\(hex) copied") } label: {
                            Circle().fill(Self.color(hex)).frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("\(hex) — click to copy")
                    }
                }
                .padding(.horizontal, 4).padding(.bottom, 4)
            }
        }
        .frame(maxHeight: 150, alignment: .top)
    }

    private func copyResult(_ r: String) {
        tools.copy(r)
        model.confirm("doc.on.doc.fill", "\(r) copied")
    }

    // MARK: Tiles

    private var awakeTile: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            ToolTile(icon: tools.isAwake ? "cup.and.saucer.fill" : "cup.and.saucer", title: "Keep Awake",
                     detail: tools.awakeLabel(at: ctx.date), tint: .orange, active: tools.isAwake) {
                if tools.isAwake { tools.stopAwake(); model.confirm("moon.zzz.fill", "Mac can sleep again") }
                else { tools.keepAwake(minutes: nil); model.confirm("cup.and.saucer.fill", "Mac stays awake") }
            }
            .contextMenu {
                Button("For 30 minutes") { tools.keepAwake(minutes: 30) }
                Button("For 1 hour") { tools.keepAwake(minutes: 60) }
                Button("For 2 hours") { tools.keepAwake(minutes: 120) }
                Button("Until I turn it off") { tools.keepAwake(minutes: nil) }
                if tools.isAwake { Divider(); Button("Turn Off") { tools.stopAwake() } }
            }
            .help("Click to toggle, right-click for a time limit")
        }
    }

    private var coinTile: some View {
        ToolTile(icon: "centsign.circle.fill", title: "Coin Flip",
                 detail: coin.map { $0 ? "Heads" : "Tails" } ?? "Can't decide?", tint: .yellow,
                 spin: spin) {
            let r = Bool.random()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) { spin += 720 + (r ? 0 : 180) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { withAnimation(.spring) { coin = r } }
        }
    }

    static func color(_ hex: String) -> Color { LiveActivityCenter.color(hex) }
}

private struct ToolTile: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    var active = false
    var swatch: Color? = nil
    var spin = 0.0
    let action: () -> Void
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(active ? .black : tint)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(active ? tint : tint.opacity(0.18)))
                        .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0))
                        .contentTransition(.symbolEffect(.replace))
                    Spacer(minLength: 0)
                    if let swatch {
                        Circle().fill(swatch).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                    }
                }
                Text(title).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail).font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(active ? tint : .white.opacity(0.45)).lineLimit(1)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.white.opacity(hover ? 0.12 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(active ? tint.opacity(0.55) : .clear, lineWidth: 1))
            .scaleEffect(hover ? 1.03 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hover = h } }
        .accessibilityLabel("\(title), \(detail)")
    }
}
