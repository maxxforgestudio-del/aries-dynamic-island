import AppKit
import SwiftUI

@main
enum AriesMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    let music = MusicController()
    let system = SystemMonitor()
    private(set) var model: IslandModel!
    private var panelController: IslandPanelController!
    private var settingsWindow: NSWindow?
    private var lyricsController: LyricsWindowController?
    private var statusItem: NSStatusItem?
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        Prefs.register()

        model = IslandModel(music: music, system: system)
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            system.start()
            Snapshotter.run(app: self, out: CommandLine.arguments[i + 1])
            return
        }
        music.start()
        system.start()
        model.startServices()
        registerHotkeys()

        panelController = IslandPanelController(model: model)
        panelController.show()

        updateStatusItem()
        var lastHotkeys = Prefs.bool(Prefs.hotkeys)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateStatusItem()
            if Prefs.bool(Prefs.hotkeys) != lastHotkeys { lastHotkeys = Prefs.bool(Prefs.hotkeys); self?.registerHotkeys() }
        }

        if UserDefaults.standard.integer(forKey: Prefs.onboardingVersion) < 1 {
            openWelcome()
        }
    }

    // MARK: Menu bar item

    private func updateStatusItem() {
        let want = Prefs.bool(Prefs.showMenuBarIcon)
        if want, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Aries Dynamic Island")
            item.button?.image?.isTemplate = true
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Island", action: #selector(menuIsland), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Full-Screen Player", action: #selector(menuLyrics), keyEquivalent: "l").target = self
            menu.addItem(withTitle: "New Note", action: #selector(menuNote), keyEquivalent: "n").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Welcome Tour…", action: #selector(menuWelcome), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Aries", action: #selector(menuQuit), keyEquivalent: "q").target = self
            item.menu = menu
            statusItem = item
        } else if !want, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func menuLyrics() { openLyrics() }
    @objc private func menuIsland() { model.expand() }
    @objc private func menuNote() { model.newNote() }
    @objc private func menuWelcome() { openWelcome() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: Shortcuts

    private func registerHotkeys() {
        Hotkeys.shared.register([
            1: { [weak self] in self?.model.toggle() },
            2: { [weak self] in self?.music.playPause() },
            3: { [weak self] in self?.toggleLyrics() },
            4: { [weak self] in self?.model.newNote() },
            5: { [weak self] in
                guard let self else { return }
                self.model.calls.toggleMute()
                let muted = self.model.calls.micMuted
                self.model.show(Toast(icon: muted ? "mic.slash.fill" : "mic.fill", tint: muted ? .red : .green,
                                      title: muted ? "Mic muted" : "Mic on", detail: ""), for: 1.6)
            },
            6: { [weak self] in self?.music.toggleLike() },
        ])
    }

    /// Lets a text field inside the island receive typing.
    func focusIsland() { panelController?.focus() }

    // MARK: Windows

    private var welcomeController: WelcomeWindowController?

    func openWelcome() {
        if welcomeController == nil {
            welcomeController = WelcomeWindowController(app: self) { [weak self] in
                self?.welcomeController = nil
                UserDefaults.standard.set(1, forKey: Prefs.onboardingVersion)
                self?.model.celebrate()
                self?.model.show(Toast(icon: "sparkles", tint: .yellow, title: "Welcome to Aries", detail: "Hover me",
                                       detailIcon: "hand.wave.fill"), for: 4)
            }
        }
        welcomeController?.show()
    }

    func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(music: music, spotify: SpotifyWeb.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "Aries Dynamic Island Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 560, height: 720))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func openLyrics() {
        model.collapse()
        if lyricsController == nil {
            lyricsController = LyricsWindowController(music: music) { [weak self] in
                self?.lyricsController = nil
            }
        }
        lyricsController?.show()
    }

    func toggleLyrics() {
        if let c = lyricsController { c.close() } else { openLyrics() }
    }
}
