import AppKit
import ApplicationServices
import Network
import SwiftUI

/// The Focus mode you're in (Do Not Disturb, Work, Sleep…), like the iPhone island shows it.
///
/// macOS has no public API for the current Focus. Aries reads it from the Focus item in
/// Control Center's menu bar (needs Accessibility, which call answering already uses), or from
/// the Focus database if you've given Aries Full Disk Access.
final class FocusMonitor: ObservableObject {
    struct Mode: Equatable { let name: String; let symbol: String; let color: Color }

    @Published private(set) var current: Mode?
    var onChange: ((Mode?, Mode?) -> Void)?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "aries.focus", qos: .utility)
    private var first = true

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        // Older/other system notifications that fire on Do Not Disturb changes — re-check right away.
        for n in ["com.apple.notificationcenterui.dndprefs_changed", "com.apple.donotdisturb.state.changed"] {
            DistributedNotificationCenter.default().addObserver(forName: .init(n), object: nil, queue: .main) { [weak self] _ in
                self?.poll()
            }
        }
    }

    private func poll() {
        guard Prefs.bool(Prefs.focusToasts) else { return }
        queue.async { [weak self] in
            let name = Self.fromDatabase() ?? Self.fromMenuBar()
            DispatchQueue.main.async {
                guard let self else { return }
                let mode = name.map(Self.mode(named:))
                if mode != self.current {
                    let old = self.current
                    self.current = mode
                    if !self.first { self.onChange?(old, mode) }
                }
                self.first = false
            }
        }
    }

    static func mode(named n: String) -> Mode {
        let l = n.lowercased()
        let table: [(String, String, Color)] = [
            ("do not disturb", "moon.fill", .indigo), ("sleep", "bed.double.fill", .mint),
            ("work", "briefcase.fill", .teal), ("personal", "person.fill", .purple),
            ("driving", "car.fill", .blue), ("fitness", "figure.run", .green),
            ("gaming", "gamecontroller.fill", .blue), ("mindful", "brain.head.profile", .cyan),
            ("reading", "book.fill", .orange), ("reduce interruptions", "apple.intelligence", .purple),
            ("study", "graduationcap.fill", .orange), ("school", "graduationcap.fill", .orange),
        ]
        let hit = table.first { l.contains($0.0) }
        return Mode(name: n, symbol: hit?.1 ?? "moon.fill", color: hit?.2 ?? .indigo)
    }

    /// ~/Library/DoNotDisturb/DB — readable only with Full Disk Access.
    private static func fromDatabase() -> String? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
        guard let a = try? Data(contentsOf: dir.appendingPathComponent("Assertions.json")),
              let aj = try? JSONSerialization.jsonObject(with: a) as? [String: Any],
              let data = (aj["data"] as? [[String: Any]])?.first,
              let records = data["storeAssertionRecords"] as? [[String: Any]],
              let id = (records.last?["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String
        else { return nil }
        if let m = try? Data(contentsOf: dir.appendingPathComponent("ModeConfigurations.json")),
           let mj = try? JSONSerialization.jsonObject(with: m) as? [String: Any],
           let configs = ((mj["data"] as? [[String: Any]])?.first?["modeConfigurations"]) as? [String: Any],
           let cfg = (configs[id] as? [String: Any])?["mode"] as? [String: Any],
           let name = cfg["name"] as? String {
            return name
        }
        return id.contains("default") ? "Do Not Disturb" : "Focus"
    }

    /// The Focus menu bar item in Control Center ("Focus, Work" while a Focus is on).
    private static func fromMenuBar() -> String? {
        guard AXIsProcessTrusted(),
              let cc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first
        else { return nil }
        let app = AXUIElementCreateApplication(cc.processIdentifier)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success,
              let barEl = bar, CFGetTypeID(barEl) == AXUIElementGetTypeID() else { return nil }
        var kids: CFTypeRef?
        AXUIElementCopyAttributeValue(barEl as! AXUIElement, kAXChildrenAttribute as CFString, &kids)
        for el in (kids as? [AXUIElement]) ?? [] {
            let ident = string(el, "AXIdentifier")?.lowercased() ?? ""
            let desc = string(el, kAXDescriptionAttribute) ?? string(el, kAXTitleAttribute) ?? ""
            guard ident.contains("focus") || desc.lowercased().hasPrefix("focus") else { continue }
            // "Focus" alone means the item is pinned but no Focus is on.
            let parts = desc.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, !parts[1].isEmpty { return parts[1] }
            if !desc.isEmpty, desc.lowercased() != "focus" { return desc }
        }
        return nil
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }
}

/// Little iPhone-style moments: Caps Lock, Low Power Mode, going offline/online, fully charged.
final class SystemExtras {
    var onToast: ((Toast, Double) -> Void)?
    private var capsTimer: Timer?
    private var caps = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private let path = NWPathMonitor()
    private var online: Bool?
    private var observers: [NSObjectProtocol] = []

    func start() {
        // Caps Lock (no permission needed: we only read the modifier state).
        capsTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
            guard now != self.caps else { return }
            self.caps = now
            guard Prefs.bool(Prefs.capsLockToast) else { return }
            self.onToast?(Toast(icon: now ? "capslock.fill" : "capslock", tint: now ? .green : .white,
                                title: "Caps Lock", detail: now ? "On" : "Off"), 1.4)
        }
        if let t = capsTimer { RunLoop.main.add(t, forMode: .common) }

        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let on = ProcessInfo.processInfo.isLowPowerModeEnabled
            guard on != self.lowPower else { return }
            self.lowPower = on
            guard Prefs.bool(Prefs.lowPowerToast) else { return }
            self.onToast?(Toast(icon: "battery.25percent", tint: on ? .yellow : .white,
                                title: "Low Power Mode", detail: on ? "On" : "Off"), 2.2)
        })

        path.pathUpdateHandler = { [weak self] p in
            let ok = p.status == .satisfied
            let wifi = p.usesInterfaceType(.wifi)
            DispatchQueue.main.async {
                guard let self else { return }
                defer { self.online = ok }
                guard let was = self.online, was != ok, Prefs.bool(Prefs.networkToast) else { return }
                self.onToast?(ok
                    ? Toast(icon: wifi ? "wifi" : "network", tint: .blue, title: "Back Online", detail: wifi ? "Wi-Fi" : "Connected",
                            detailIcon: "checkmark.circle.fill")
                    : Toast(icon: "wifi.slash", tint: .red, title: "No Internet", detail: "Offline"), 2.4)
            }
        }
        path.start(queue: DispatchQueue(label: "aries.net"))
    }
}
