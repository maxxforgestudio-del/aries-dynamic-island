import AppKit
import SwiftUI

/// Privacy protections that apply across the whole app.
final class PrivacyGuard {
    static let shared = PrivacyGuard()
    private var timer: Timer?

    /// Keeps every Aries window (island, player, widgets, settings) out of screenshots,
    /// screen recordings and screen sharing when "Hide from screen sharing" is on.
    func start() {
        apply()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.apply() }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    func apply() {
        let hide = Prefs.bool(Prefs.hideFromCapture)
        let want: NSWindow.SharingType = hide ? .none : .readOnly
        for w in NSApp.windows where w.sharingType != want { w.sharingType = want }
    }

    /// Every place Aries keeps something about you on this Mac.
    static var dataFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aries Dynamic Island", isDirectory: true)
    }

    /// Signs out of Spotify, deletes notes, caches and settings, then quits.
    static func eraseEverything() {
        SpotifyWeb.shared.disconnect()
        try? FileManager.default.removeItem(at: dataFolder)
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
            UserDefaults.standard.synchronize()
        }
        URLCache.shared.removeAllCachedResponses()
        NSApp.terminate(nil)
    }
}

struct PrivacySecuritySection: View {
    @AppStorage(Prefs.hideFromCapture) private var hideFromCapture = false
    @AppStorage(Prefs.privateLockScreen) private var privateLockScreen = false
    @ObservedObject private var spotify = SpotifyWeb.shared
    @ViewState private var confirmErase = false

    var body: some View {
        Section {
            Toggle(isOn: $hideFromCapture) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide Aries from screen sharing & recordings")
                    Text("The island, player and widgets won't show up in screenshots, recordings, Zoom, Meet or FaceTime screen sharing. You still see them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: hideFromCapture) { _, _ in PrivacyGuard.shared.apply() }
            Toggle(isOn: $privateLockScreen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Private Lock Screen")
                    Text("While your Mac is locked, widgets hide your calendar events and to-dos.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Protection")
        }

        Section {
            row("checkmark.shield.fill", .green, "Verified updates",
                "Before installing an update, Aries checks it came from GitHub, matches its published SHA-256 checksum, is signed as Aries and is newer than what you have. Anything else is rejected.")
            row("lock.fill", .blue, "Private sign-in",
                "Your Spotify sign-in is stored in a file only your Mac account can read. Aries never sees or stores your password.")
            row("eye.slash.fill", .purple, "No tracking",
                "No analytics, ads, accounts or tracking. Aries only talks to Spotify (if you connect it), LRCLIB for lyrics, Apple for album art, Open-Meteo for weather and GitHub for updates and patch notes.")
        } header: {
            Text("How Aries protects you")
        }

        Section {
            HStack {
                Text("Spotify account")
                Spacer()
                if spotify.isConnected {
                    Button("Sign Out") { spotify.disconnect() }.controlSize(.small)
                } else {
                    Text("Not signed in").foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Aries data on this Mac")
                Spacer()
                Button("Show in Finder") {
                    try? FileManager.default.createDirectory(at: PrivacyGuard.dataFolder, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([PrivacyGuard.dataFolder])
                }.controlSize(.small)
                Button("Erase All…", role: .destructive) { confirmErase = true }.controlSize(.small)
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Erase All signs you out of Spotify and deletes your notes, saved settings and caches, then quits Aries.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Erase all Aries data?", isPresented: $confirmErase) {
            Button("Erase and Quit", role: .destructive) { PrivacyGuard.eraseEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This signs you out of Spotify and deletes your notes, settings and caches. It can't be undone.")
        }
    }

    private func row(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
