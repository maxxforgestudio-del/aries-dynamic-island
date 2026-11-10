import AppKit
import SwiftUI
import EventKit
import CoreAudio

// MARK: - Shelf (drop files on the notch, drag them back out later)

final class ShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = []
    private let key = "shelfItems"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        var changed = false
        for u in urls where !items.contains(u) {
            items.append(u); changed = true
        }
        if changed { save() }
    }

    func remove(_ url: URL) { items.removeAll { $0 == url }; save() }
    func clear() { items.removeAll(); save() }

    func airDrop(_ urls: [URL]? = nil) {
        let list = urls ?? items
        guard !list.isEmpty, let s = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        s.perform(withItems: list)
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    private func save() { UserDefaults.standard.set(items.map(\.path), forKey: key) }

    static func icon(for url: URL) -> NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

// MARK: - Timer

final class TimerModel: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: Double?
    @Published private(set) var total: Double = 0

    var onFinish: (() -> Void)?
    private var ticker: Timer?

    var isRunning: Bool { endDate != nil }
    var isActive: Bool { endDate != nil || pausedRemaining != nil }

    func remaining(at d: Date = Date()) -> Double {
        if let e = endDate { return max(0, e.timeIntervalSince(d)) }
        return pausedRemaining ?? 0
    }

    func progress(at d: Date = Date()) -> Double {
        total > 0 ? 1 - remaining(at: d) / total : 0
    }

    func start(minutes: Double) {
        total = minutes * 60
        endDate = Date().addingTimeInterval(total)
        pausedRemaining = nil
        UserDefaults.standard.set(minutes, forKey: Prefs.lastTimerMinutes)
        schedule()
    }

    func pause() {
        guard let e = endDate else { return }
        pausedRemaining = max(0, e.timeIntervalSinceNow)
        endDate = nil
        ticker?.invalidate()
    }

    func resume() {
        guard let r = pausedRemaining else { return }
        endDate = Date().addingTimeInterval(r)
        pausedRemaining = nil
        schedule()
    }

    func addMinute() {
        if let e = endDate { endDate = e.addingTimeInterval(60) }
        else if let r = pausedRemaining { pausedRemaining = r + 60 }
        total += 60
    }

    func stop() {
        endDate = nil; pausedRemaining = nil; total = 0
        ticker?.invalidate()
    }

    private func schedule() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let e = self.endDate, e <= Date() else { return }
            self.stop()
            self.onFinish?()
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    static func format(_ s: Double) -> String {
        let t = Int(s.rounded(.up))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Calendar

struct EventInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    let joinURL: URL?
}

final class CalendarModel: ObservableObject {
    @Published private(set) var authorized = false
    @Published private(set) var upcoming: [EventInfo] = []

    var onSoon: ((EventInfo) -> Void)?
    private let store = EKEventStore()
    private var alerted = Set<String>()
    private var timer: Timer?

    var next: EventInfo? { upcoming.first }
    var statusDenied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted
    }

    func start() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard authorized, Prefs.bool(Prefs.showCalendar) else {
            if !upcoming.isEmpty { upcoming = [] }
            return
        }
        let now = Date()
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-3600),
                                            end: now.addingTimeInterval(36 * 3600), calendars: nil)
        let events = store.events(matching: pred)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(4)
            .map { e in
                EventInfo(id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                          title: e.title ?? "Event", start: e.startDate, end: e.endDate,
                          color: Color(nsColor: e.calendar?.color ?? .systemBlue),
                          joinURL: Self.meetingLink(e))
            }
        if upcoming != Array(events) { upcoming = Array(events) }

        if Prefs.bool(Prefs.meetingAlerts) {
            for e in events where !alerted.contains(e.id) {
                let mins = e.start.timeIntervalSince(now) / 60
                if mins > 0 && mins <= 5 {
                    alerted.insert(e.id)
                    onSoon?(e)
                }
            }
        }
    }

    private static func meetingLink(_ e: EKEvent) -> URL? {
        let hosts = "zoom\\.us|meet\\.google\\.com|teams\\.microsoft\\.com|teams\\.live\\.com|webex\\.com|facetime\\.apple\\.com|whereby\\.com"
        let pattern = "https?://[^\\s<>\"]*(\(hosts))[^\\s<>\"]*"
        let text = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        guard let r = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return URL(string: String(text[r]))
    }

    static func relative(_ d: Date, now: Date = Date()) -> String {
        let m = Int((d.timeIntervalSince(now) / 60).rounded(.up))
        if m <= 0 { return "now" }
        if m < 60 { return "in \(m) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "in \(h) hr" : "in \(h) hr \(r) min"
    }
}

// MARK: - Audio output (volume HUD + "AirPods connected")

final class AudioMonitor {
    var onVolume: ((Float, Bool) -> Void)?
    var onDevice: ((String, String) -> Void)?   // (name, symbol)

    private var device = AudioObjectID(0)
    private var deviceName = ""
    private var ready = false
    private var lastVolume: Float = -1
    private var lastMute = false
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func start() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.deviceChanged() }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        attach()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.ready = true }
    }

    private func deviceChanged() {
        let old = deviceName
        attach()
        guard ready, deviceName != old, !deviceName.isEmpty else { return }
        onDevice?(deviceName, Self.symbol(for: deviceName, device: device))
    }

    private func attach() {
        for (obj, a, b) in listeners {
            var addr = a
            AudioObjectRemovePropertyListenerBlock(obj, &addr, .main, b)
        }
        listeners.removeAll()

        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return }
        device = id
        deviceName = Self.name(of: id)
        lastVolume = volume().0
        lastMute = volume().1

        for sel in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for el in [kAudioObjectPropertyElementMain, 1, 2] as [UInt32] {
                var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioDevicePropertyScopeOutput, mElement: el)
                guard AudioObjectHasProperty(id, &a) else { continue }
                let b: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
                if AudioObjectAddPropertyListenerBlock(id, &a, .main, b) == noErr { listeners.append((id, a, b)) }
            }
        }
    }

    private func volumeChanged() {
        let (v, m) = volume()
        guard ready, abs(v - lastVolume) > 0.001 || m != lastMute else { return }
        lastVolume = v; lastMute = m
        onVolume?(v, m)
    }

    private func volume() -> (Float, Bool) {
        var v: Float = 0
        var found = false
        for el in [kAudioObjectPropertyElementMain, 1] as [UInt32] {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioDevicePropertyScopeOutput, mElement: el)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(device, &a), AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr {
                found = true; break
            }
        }
        var mute: UInt32 = 0
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                           mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &a) { AudioObjectGetPropertyData(device, &a, 0, nil, &size, &mute) }
        return (found ? v : 0, mute != 0)
    }

    private static func name(of id: AudioObjectID) -> String {
        var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ref) == noErr, let r = ref else { return "" }
        return r.takeRetainedValue() as String
    }

    static func symbol(for name: String, device: AudioObjectID) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("macbook") || n.contains("built-in") { return "laptopcomputer" }
        if n.contains("homepod") { return "homepod.fill" }
        if n.contains("tv") || n.contains("display") || n.contains("hdmi") { return "tv" }
        if n.contains("headphone") || n.contains("buds") || n.contains("wh-") || n.contains("bose") { return "headphones" }
        return "hifispeaker.fill"
    }

    static func volumeSymbol(_ v: Float, muted: Bool) -> String {
        if muted || v < 0.01 { return "speaker.slash.fill" }
        if v < 0.34 { return "speaker.wave.1.fill" }
        if v < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
