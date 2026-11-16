import AppKit
import SwiftUI
import EventKit
import AVFoundation
import ApplicationServices

/// Knows every permission Aries uses, asks for them automatically when a feature needs
/// one, and can jump straight to the right page of System Settings.
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    enum Kind: String, CaseIterable, Identifiable {
        case spotify, music, calendar, accessibility, camera, downloads
        var id: String { rawValue }
    }

    enum Status { case granted, notAsked, denied, unavailable }

    struct Info {
        let title: String
        let why: String
        let icon: String
        let color: Color
        let pane: String
    }

    @Published private(set) var statuses: [Kind: Status] = [:]
    private var timer: Timer?

    static func info(_ k: Kind) -> Info {
        switch k {
        case .spotify: return .init(title: "Control Spotify", why: "See what's playing in Spotify on this Mac and control it.",
                                    icon: "music.note", color: .green, pane: "Privacy_Automation")
        case .music: return .init(title: "Control Music", why: "See what's playing in Apple Music and control it.",
                                  icon: "music.note.list", color: .pink, pane: "Privacy_Automation")
        case .calendar: return .init(title: "Calendars", why: "Show your next event and a heads-up before meetings.",
                                     icon: "calendar", color: .red, pane: "Privacy_Calendars")
        case .accessibility: return .init(title: "Accessibility", why: "Answer and decline iPhone calls, and end calls, from the island.",
                                          icon: "accessibility", color: .blue, pane: "Privacy_Accessibility")
        case .camera: return .init(title: "Camera", why: "Only for the Mirror tab, and only while it's open.",
                                   icon: "camera.fill", color: .gray, pane: "Privacy_Camera")
        case .downloads: return .init(title: "Downloads Folder", why: "Show download progress in the notch.",
                                      icon: "arrow.down.circle.fill", color: .mint, pane: "Privacy_FilesAndFolders")
        }
    }

    /// Whether a feature you've switched on depends on this permission.
    func isNeeded(_ k: Kind) -> Bool {
        switch k {
        case .spotify: return LocalPlayers.isRunning(LocalPlayers.spotifyID) || statuses[k] == .denied
        case .music: return LocalPlayers.isRunning(LocalPlayers.musicID) || statuses[k] == .denied
        case .calendar: return Prefs.bool(Prefs.showCalendar)
        case .accessibility: return Prefs.bool(Prefs.callBanner)
        case .camera: return Prefs.bool(Prefs.showMirror) && statuses[k] == .denied
        case .downloads: return Prefs.bool(Prefs.downloadsActivity)
        }
    }

    /// Permissions that are needed but not granted.
    /// Only counts permissions we've actually checked — "not checked yet" is never "missing".
    var missing: [Kind] {
        Kind.allCases.filter { k in
            guard isNeeded(k), let st = statuses[k] else { return false }
            return st == .notAsked || st == .denied
        }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        var s: [Kind: Status] = statuses
        // Apple Events checks can wait on an open consent prompt — never on the main thread.
        DispatchQueue.global(qos: .utility).async {
            let sp = Self.automation(LocalPlayers.spotifyID)
            let mu = Self.automation(LocalPlayers.musicID)
            DispatchQueue.main.async {
                if self.statuses[.spotify] != sp { self.statuses[.spotify] = sp }
                if self.statuses[.music] != mu { self.statuses[.music] = mu }
            }
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: s[.calendar] = .granted
        case .notDetermined: s[.calendar] = .notAsked
        default: s[.calendar] = .denied
        }
        s[.accessibility] = AXIsProcessTrusted() ? .granted : (asked(.accessibility) ? .denied : .notAsked)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: s[.camera] = .granted
        case .notDetermined: s[.camera] = .notAsked
        default: s[.camera] = .denied
        }
        if !Prefs.bool(Prefs.downloadsActivity) { s[.downloads] = nil }
        if s != statuses { statuses = s }
        // Checking the Downloads folder can block on a macOS prompt, so do it in the background.
        guard Prefs.bool(Prefs.downloadsActivity) else { return }
        DispatchQueue.global(qos: .utility).async {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            let ok = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) != nil
            DispatchQueue.main.async {
                let v: Status = ok ? .granted : .denied
                if self.statuses[.downloads] != v { self.statuses[.downloads] = v }
            }
        }
    }

    // MARK: Asking

    /// Asks for everything an enabled feature needs that hasn't been asked yet — one at a time.
    func requestNeeded() {
        let queue = Kind.allCases.filter { isNeeded($0) && statuses[$0] == .notAsked && $0 != .camera }
        var delay = 0.0
        for k in queue {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.request(k) }
            delay += 2.5
        }
    }

    /// Opens a music app in the background (if needed) and asks for permission to control it.
    func connectApp(_ k: Kind, bundleID: String) {
        markAsked(k)
        if statuses[k] == .denied { openSettings(k); return }
        guard !LocalPlayers.isRunning(bundleID),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            request(k); return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        cfg.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.request(k) }
        }
    }

    func request(_ k: Kind) {
        markAsked(k)
        switch k {
        case .spotify, .music:
            let bid = k == .spotify ? LocalPlayers.spotifyID : LocalPlayers.musicID
            if statuses[k] == .denied { openSettings(k); return }
            LocalPlayers.queue.async {
                _ = Self.automation(bid, ask: true)
                DispatchQueue.main.async { self.refresh() }
            }
        case .calendar:
            if statuses[k] == .denied { openSettings(k); return }
            AppDelegate.shared.model.calendar.requestAccess()
        case .accessibility:
            if statuses[k] == .denied { openSettings(k); return }
            AppDelegate.shared.model.calls.requestAccessibility()
        case .camera:
            if statuses[k] == .denied { openSettings(k); return }
            AVCaptureDevice.requestAccess(for: .video) { _ in DispatchQueue.main.async { self.refresh() } }
        case .downloads:
            // Touching the folder makes macOS show its "access Downloads" prompt.
            AppDelegate.shared.model.downloads.setEnabled(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
            if statuses[k] == .denied { openSettings(k) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refresh() }
    }

    /// macOS sometimes keeps an old copy of Aries switched on in System Settings (from an
    /// earlier build). Clear that stale entry, then ask again so the toggle applies to this copy.
    func fix(_ k: Kind) {
        let service: String
        switch k {
        case .accessibility: service = "Accessibility"
        case .calendar: service = "Calendar"
        case .camera: service = "Camera"
        case .spotify, .music: service = "AppleEvents"
        case .downloads: service = "SystemPolicyDownloadsFolder"
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", service, Bundle.main.bundleIdentifier ?? "app.aries.dynamicisland"]
        try? p.run()
        p.waitUntilExit()
        UserDefaults.standard.set(false, forKey: "asked.\(k.rawValue)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.request(k)
            if k == .accessibility { self.openSettings(k) }
        }
    }

    func openSettings(_ k: Kind) {
        let pane = Self.info(k).pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func asked(_ k: Kind) -> Bool { UserDefaults.standard.bool(forKey: "asked.\(k.rawValue)") }
    private func markAsked(_ k: Kind) { UserDefaults.standard.set(true, forKey: "asked.\(k.rawValue)") }

    /// Apple Events permission for controlling another app.
    private static func automation(_ bundleID: String, ask: Bool = false) -> Status {
        guard LocalPlayers.isRunning(bundleID) else {
            return UserDefaults.standard.bool(forKey: "automation.ok.\(bundleID)") ? .granted : .unavailable
        }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let r = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
        switch r {
        case noErr:
            UserDefaults.standard.set(true, forKey: "automation.ok.\(bundleID)")
            return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        default: return .unavailable
        }
    }
}

// MARK: - UI

/// A row for one permission: what it's for, its status, and one button to fix it.
struct PermissionRow: View {
    let kind: PermissionCenter.Kind
    @ObservedObject var center: PermissionCenter
    var dark = false

    var body: some View {
        let info = PermissionCenter.info(kind)
        let status = center.statuses[kind] ?? .notAsked
        HStack(spacing: 12) {
            Image(systemName: info.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(info.color.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title).font(.system(size: 13.5, weight: .semibold))
                Text(info.why).font(.system(size: 11.5)).opacity(0.6).fixedSize(horizontal: false, vertical: true)
                if status == .denied {
                    Text("Already switched on in System Settings? Click Fix: macOS is remembering an older copy of Aries.")
                        .font(.system(size: 10.5)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            switch status {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
            case .unavailable:
                Text("Open the app first").font(.system(size: 11.5)).opacity(0.5)
            case .denied:
                HStack(spacing: 6) {
                    Button("Fix") { center.fix(kind) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .help("Already on in System Settings? macOS may be remembering an older copy of Aries. Fix clears it and asks again.")
                    Button("Open Settings") { center.openSettings(kind) }
                        .controlSize(.small)
                }
            case .notAsked:
                Button("Allow") { center.request(kind) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .foregroundStyle(dark ? .white : .primary)
    }
}
