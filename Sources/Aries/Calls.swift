import AppKit
import ApplicationServices
import Combine
import CoreAudio

struct CallInfo: Equatable {
    enum Kind: Equatable { case incoming, active }
    var kind: Kind
    var title: String          // caller name or app name
    var subtitle: String       // "iPhone", "Zoom", …
    var symbol: String
    var bundleID: String?
    var startedAt: Date
    var isVideo: Bool
}

/// Live call activity.
/// • Ongoing calls: detected from which app is using the microphone (FaceTime/iPhone
///   Continuity, Zoom, Teams, Discord, Slack huddles, Webex, WhatsApp, …).
/// • Incoming iPhone/FaceTime calls: read from the system's call banner via Accessibility
///   (optional permission), which also lets Aries press Accept / Decline for you.
/// macOS has no public call API (CallKit is iOS-only), so this is best-effort.
final class CallMonitor: ObservableObject {
    @Published private(set) var call: CallInfo?
    @Published private(set) var micMuted = false
    @Published private(set) var axTrusted = AXIsProcessTrusted()

    private struct KnownApp { let match: String; let name: String; let symbol: String }
    private static let callApps: [KnownApp] = [
        .init(match: "facetime", name: "FaceTime", symbol: "phone.fill"),
        .init(match: "callservices", name: "iPhone", symbol: "phone.fill"),
        .init(match: "telephony", name: "iPhone", symbol: "phone.fill"),
        .init(match: "avconference", name: "FaceTime", symbol: "phone.fill"),
        .init(match: "us.zoom", name: "Zoom", symbol: "video.fill"),
        .init(match: "zoom.us", name: "Zoom", symbol: "video.fill"),
        .init(match: "com.microsoft.teams", name: "Teams", symbol: "video.fill"),
        .init(match: "discord", name: "Discord", symbol: "headphones"),
        .init(match: "slack", name: "Slack Huddle", symbol: "headphones"),
        .init(match: "webex", name: "Webex", symbol: "video.fill"),
        .init(match: "whatsapp", name: "WhatsApp", symbol: "phone.fill"),
        .init(match: "telegram", name: "Telegram", symbol: "phone.fill"),
        .init(match: "skype", name: "Skype", symbol: "phone.fill"),
        .init(match: "signal", name: "Signal", symbol: "phone.fill"),
        .init(match: "messenger", name: "Messenger", symbol: "phone.fill"),
    ]
    private static let browsers = ["com.google.chrome", "com.apple.safari", "company.thebrowser", "org.mozilla.firefox",
                                   "com.microsoft.edgemac", "com.brave.browser", "com.operasoftware", "com.vivaldi"]

    private weak var system: SystemMonitor?
    private var bag = Set<AnyCancellable>()
    private var bannerTimer: Timer?
    private var lastSeen = Date.distantPast
    private var accept: (AXUIElement, String)?
    private var decline: (AXUIElement, String)?

    func start(system: SystemMonitor) {
        self.system = system
        system.$micClients.combineLatest(system.$cameraActive)
            .receive(on: RunLoop.main)
            .sink { [weak self] clients, cam in self?.evaluate(clients: clients, camera: cam) }
            .store(in: &bag)
        micMuted = Self.inputMuted()
        bannerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.scanBanner() }
    }

    func debugSet(_ c: CallInfo?) { call = c }

    // MARK: Ongoing calls

    private func evaluate(clients: [MicClient], camera: Bool) {
        guard Prefs.bool(Prefs.callActivity) else {
            if call?.kind == .active { call = nil }
            return
        }
        var found: CallInfo?
        for c in clients {
            let id = (c.bundleID + " " + c.name).lowercased()
            if let k = Self.callApps.first(where: { id.contains($0.match) }) {
                found = CallInfo(kind: .active, title: k.name == "iPhone" ? "Phone Call" : k.name,
                                 subtitle: k.name == "iPhone" ? "iPhone" : "On a call",
                                 symbol: camera ? "video.fill" : k.symbol, bundleID: c.bundleID,
                                 startedAt: Date(), isVideo: camera)
                break
            }
            if camera, Self.browsers.contains(where: { id.contains($0) }) {
                found = CallInfo(kind: .active, title: "Video Call", subtitle: c.name, symbol: "video.fill",
                                 bundleID: c.bundleID, startedAt: Date(), isVideo: true)
            }
        }
        if var f = found {
            lastSeen = Date()
            if let existing = call, existing.kind == .active, existing.bundleID == f.bundleID {
                f.startedAt = existing.startedAt
                if existing.title == "Phone Call", f.title == "Phone Call" { f.title = existing.title }
            } else if let existing = call, existing.kind == .incoming {
                // Answered: keep the caller's name.
                f.title = existing.title
                f.subtitle = existing.subtitle
            }
            if f != call { call = f }
            micMuted = Self.inputMuted()
        } else if call?.kind == .active, Date().timeIntervalSince(lastSeen) > 2.5 {
            call = nil
        }
    }

    // MARK: Incoming banner (Accessibility)

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        axTrusted = AXIsProcessTrustedWithOptions(opts)
    }

    private func scanBanner() {
        let trusted = AXIsProcessTrusted()
        if trusted != axTrusted { axTrusted = trusted }
        guard trusted, Prefs.bool(Prefs.callBanner),
              let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
        else { return }

        let app = AXUIElementCreateApplication(nc.processIdentifier)
        var texts: [String] = []
        var acceptEl: (AXUIElement, String)?
        var declineEl: (AXUIElement, String)?
        for w in Self.children(app, kAXWindowsAttribute) {
            Self.walk(w, depth: 0) { el in
                let role = Self.string(el, kAXRoleAttribute) ?? ""
                let label = [Self.string(el, kAXTitleAttribute), Self.string(el, kAXDescriptionAttribute)]
                    .compactMap { $0?.lowercased() }.joined(separator: " ")
                if role == kAXButtonRole as String {
                    if acceptEl == nil, ["accept", "answer"].contains(where: label.contains) { acceptEl = (el, kAXPressAction as String) }
                    if declineEl == nil, label.contains("decline") { declineEl = (el, kAXPressAction as String) }
                }
                var names: CFArray?
                if AXUIElementCopyActionNames(el, &names) == .success, let list = names as? [String] {
                    for n in list {
                        let l = n.lowercased()
                        if acceptEl == nil, l.contains("accept") || l.contains("answer") { acceptEl = (el, n) }
                        if declineEl == nil, l.contains("decline") { declineEl = (el, n) }
                    }
                }
                if role == kAXStaticTextRole as String, let v = Self.string(el, kAXValueAttribute), !v.isEmpty {
                    texts.append(v)
                }
            }
        }

        if acceptEl != nil || declineEl != nil {
            accept = acceptEl; decline = declineEl
            let skip = ["facetime", "iphone", "incoming", "audio", "video", "call", "accept", "decline", "now"]
            let caller = texts.first { t in !skip.contains(where: { t.lowercased() == $0 || t.lowercased().hasPrefix($0 + " ") }) }
                ?? texts.first ?? "Incoming Call"
            let video = texts.contains { $0.lowercased().contains("video") }
            let info = CallInfo(kind: .incoming, title: caller, subtitle: video ? "FaceTime Video" : "iPhone",
                                symbol: video ? "video.fill" : "phone.fill", bundleID: "com.apple.FaceTime",
                                startedAt: call?.kind == .incoming ? call!.startedAt : Date(), isVideo: video)
            if info != call { call = info }
        } else if call?.kind == .incoming {
            accept = nil; decline = nil
            call = nil
        }
    }

    func acceptCall() {
        if let (el, action) = accept { AXUIElementPerformAction(el, action as CFString) }
        else { openCallApp() }
    }

    func declineCall() {
        if let (el, action) = decline { AXUIElementPerformAction(el, action as CFString) }
        call = nil
    }

    /// Tries to press the call app's own End/Leave button; otherwise brings the app forward.
    func endCall() {
        guard let bid = call?.bundleID, AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first else {
            openCallApp(); return
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var pressed = false
        for w in Self.children(root, kAXWindowsAttribute) where !pressed {
            Self.walk(w, depth: 0) { el in
                guard !pressed, Self.string(el, kAXRoleAttribute) == kAXButtonRole as String else { return }
                let label = [Self.string(el, kAXTitleAttribute), Self.string(el, kAXDescriptionAttribute)]
                    .compactMap { $0?.lowercased() }.joined(separator: " ")
                if ["end", "leave", "hang up", "end call"].contains(where: { label == $0 || label.hasPrefix($0 + " ") }) {
                    AXUIElementPerformAction(el, kAXPressAction as CFString)
                    pressed = true
                }
            }
        }
        if !pressed { openCallApp() }
    }

    func openCallApp() {
        guard let bid = call?.bundleID else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: Mic mute (system-wide, default input device)

    func toggleMute() {
        let target = !Self.inputMuted()
        Self.setInputMuted(target)
        micMuted = Self.inputMuted()
    }

    private static func defaultInput() -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    static func inputMuted() -> Bool {
        guard let dev = defaultInput() else { return false }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(dev, &addr), AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &muted) == noErr {
            return muted != 0
        }
        addr.mSelector = kAudioDevicePropertyVolumeScalar
        var v: Float32 = 1
        size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(dev, &addr), AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr { return v < 0.01 }
        return false
    }

    private static var savedInputVolume: Float32 = 0.75

    static func setInputMuted(_ on: Bool) {
        guard let dev = defaultInput() else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(dev, &addr), AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue {
            var v: UInt32 = on ? 1 : 0
            AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
            return
        }
        addr.mSelector = kAudioDevicePropertyVolumeScalar
        guard AudioObjectHasProperty(dev, &addr) else { return }
        var size = UInt32(MemoryLayout<Float32>.size)
        if on {
            var cur: Float32 = 0
            if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &cur) == noErr, cur > 0.01 { savedInputVolume = cur }
            var zero: Float32 = 0
            AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &zero)
        } else {
            var v = savedInputVolume
            AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &v)
        }
    }

    // MARK: AX helpers

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func children(_ el: AXUIElement, _ attr: String = kAXChildrenAttribute) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return [] }
        return (v as? [AXUIElement]) ?? []
    }

    private static func walk(_ el: AXUIElement, depth: Int, _ visit: (AXUIElement) -> Void) {
        guard depth < 10 else { return }
        visit(el)
        for c in children(el) { walk(c, depth: depth + 1, visit) }
    }
}
