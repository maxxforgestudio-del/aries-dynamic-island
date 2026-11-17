import AppKit
import SwiftUI
import EventKit
import AVFoundation
import ApplicationServices

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
        if let i = CommandLine.arguments.firstIndex(of: "--permissions-report"), i + 1 < CommandLine.arguments.count {
            let out = CommandLine.arguments[i + 1]
            let pc = PermissionCenter.shared
            pc.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                var lines = ["accessibilityTrusted=\(AXIsProcessTrusted())",
                             "calendarStatus=\(EKEventStore.authorizationStatus(for: .event).rawValue)",
                             "cameraStatus=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue)"]
                for k in PermissionCenter.Kind.allCases {
                    lines.append("\(k.rawValue)=\(String(describing: pc.statuses[k])) needed=\(pc.isNeeded(k))")
                }
                try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
                exit(0)
            }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-hype"), i + 2 < CommandLine.arguments.count {
            let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            let work = URL(fileURLWithPath: CommandLine.arguments[i + 2])
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            Task { @MainActor in
                if CommandLine.arguments.contains("--preview") {
                    let a = Hype.Assets(work: work)
                    var times: [Double] = [0.5] + [1.5, 3.5, 5, 6.2, 8, 10, 12, 14, 16, 18.5].map { Hype.Braw(4 + $0) }
                    times += Hype.segs.map { Hype.B($0.from) + 0.25 }
                    times += [Hype.B(53.2), Hype.B(56.5), Hype.drop + 0.3, Hype.endCard + 2.5]
                    if let j = CommandLine.arguments.firstIndex(of: "--times"), j + 1 < CommandLine.arguments.count {
                        times = CommandLine.arguments[j + 1].split(separator: ",").compactMap { Double($0) }
                    }
                    for t in times {
                        let r = ImageRenderer(content: HypeView(t: t, a: a).frame(width: Hype.size.width, height: Hype.size.height))
                        r.scale = t > Hype.endCard ? 0.6 : 0.25
                        if let cg = r.cgImage {
                            try? NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.85])?
                                .write(to: out.appendingPathComponent(String(format: "h%06.2f.jpg", t)))
                        }
                    }
                    exit(0)
                }
                if let j = CommandLine.arguments.firstIndex(of: "--from"), j + 1 < CommandLine.arguments.count,
                   let from = Double(CommandLine.arguments[j + 1]) {
                    // Render only the tail of the video, starting at `from` seconds (used to redo the end card).
                    let a = Hype.Assets(work: work)
                    do {
                        try IntroExporter.renderVideo(to: out.appendingPathComponent("hype-tail.mp4"), size: Hype.size, fps: 60,
                                                      duration: Hype.duration - from, frame: { t, sz in
                            let r = ImageRenderer(content: HypeView(t: from + t, a: a).frame(width: sz.width, height: sz.height))
                            r.scale = 1
                            r.proposedSize = ProposedViewSize(sz)
                            return r.cgImage
                        })
                        print("tail: done")
                    } catch { print("tail failed:", error) }
                    exit(0)
                }
                do { try Hype.render(outDir: out, work: work); print("hype: done") } catch { print("hype failed:", error) }
                exit(0)
            }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-ad-audio"), i + 2 < CommandLine.arguments.count {
            do {
                try AdAudio.render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]), vo: URL(fileURLWithPath: CommandLine.arguments[i + 2]))
                print("audio: done")
            } catch { print("audio failed:", error) }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-ad"), i + 2 < CommandLine.arguments.count {
            let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            let shots = URL(fileURLWithPath: CommandLine.arguments[i + 2])
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            Task { @MainActor in
                if CommandLine.arguments.contains("--preview") {
                    let a = Ad.loadAssets(shots)
                    for t in stride(from: 1.2, through: Ad.duration - 1, by: 1.6) {
                        let r = ImageRenderer(content: AdView(t: t, a: a).frame(width: Ad.size.width, height: Ad.size.height))
                        r.scale = 0.33
                        if let cg = r.cgImage {
                            try? NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.85])?
                                .write(to: out.appendingPathComponent(String(format: "a%05.1f.jpg", t)))
                        }
                    }
                    exit(0)
                }
                do { try Ad.render(outDir: out, shots: shots); print("ad: done") } catch { print("ad failed:", error) }
                exit(0)
            }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-trailer"), i + 2 < CommandLine.arguments.count {
            let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            let shots = URL(fileURLWithPath: CommandLine.arguments[i + 2])
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            Task { @MainActor in
                if CommandLine.arguments.contains("--preview") {
                    let images = Trailer.loadAll(shots)
                    let T = Trailer.self
                    var times = [T.welcomeStart + 3.4, T.hypeStart + 1.6, T.hypeStart + 3.4]
                    times += T.scenes.indices.map { T.featuresStart + Double($0) * T.sceneLen + 1.6 }
                    times += [T.montageStart + 0.4, T.montageStart + 6, T.endStart + 4]
                    for t in times {
                        let r = ImageRenderer(content: TrailerView(t: t, images: images).frame(width: 1920, height: 1080))
                        r.scale = 0.5
                        if let cg = r.cgImage {
                            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                                .write(to: out.appendingPathComponent(String(format: "t%05.1f.png", t)))
                        }
                    }
                    print("duration", T.duration)
                    exit(0)
                }
                do { try Trailer.render(outDir: out, shots: shots); print("trailer: done") }
                catch { print("trailer failed:", error) }
                exit(0)
            }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-frames"), i + 1 < CommandLine.arguments.count {
            // Every frame of the intro as numbered PNGs (frame-0001.png …).
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            let fps = i + 2 < CommandLine.arguments.count ? Int(CommandLine.arguments[i + 2]) ?? 60 : 60
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            Task { @MainActor in
                let total = Int(BrandIntro.duration * Double(fps))
                for f in 0...total {
                    autoreleasepool {
                        if let cg = IntroExporter.frame(t: Double(f) / Double(fps), size: CGSize(width: 1920, height: 1080)) {
                            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                                .write(to: dir.appendingPathComponent(String(format: "frame-%04d.png", f + 1)))
                        }
                    }
                }
                print("frames:", total + 1)
                exit(0)
            }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-intro"), i + 1 < CommandLine.arguments.count {
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            Task { @MainActor in
                for t in [1.5, 3.4, 4.4, 5.0, 5.7, 6.4, 7.0, 8.6] {
                    if let cg = IntroExporter.frame(t: t, size: CGSize(width: 1920, height: 1080)) {
                        let rep = NSBitmapImageRep(cgImage: cg)
                        try? rep.representation(using: .png, properties: [:])?
                            .write(to: dir.appendingPathComponent(String(format: "frame-%.1f.png", t)))
                    }
                }
                if !CommandLine.arguments.contains("--frames-only") {
                    do {
                        try IntroExporter.renderVideo(to: dir.appendingPathComponent("Aries-Intro-16x9.mp4"), size: CGSize(width: 1920, height: 1080))
                        try IntroExporter.renderVideo(to: dir.appendingPathComponent("Aries-Intro-9x16.mp4"), size: CGSize(width: 1080, height: 1920))
                        try IntroExporter.renderGIF(to: dir.appendingPathComponent("aries-intro.gif"), size: CGSize(width: 720, height: 405))
                        print("videos done")
                    } catch { print("video error:", error) }
                }
                exit(0)
            }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            system.start()
            Snapshotter.run(app: self, out: CommandLine.arguments[i + 1])
            return
        }
        music.start()
        system.start()
        model.startServices()
        registerHotkeys()
        PermissionCenter.shared.start()

        panelController = IslandPanelController(model: model)
        panelController.show()

        updateStatusItem()
        var lastHotkeys = Prefs.bool(Prefs.hotkeys)
        var permissionWork: DispatchWorkItem?
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateStatusItem()
            if Prefs.bool(Prefs.hotkeys) != lastHotkeys { lastHotkeys = Prefs.bool(Prefs.hotkeys); self?.registerHotkeys() }
            // A feature was switched on → ask for its permission right away.
            permissionWork?.cancel()
            let w = DispatchWorkItem {
                guard UserDefaults.standard.integer(forKey: Prefs.onboardingVersion) >= 1 else { return }
                PermissionCenter.shared.refresh()
                PermissionCenter.shared.requestNeeded()
            }
            permissionWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
        }

        if UserDefaults.standard.integer(forKey: Prefs.onboardingVersion) < 1 {
            openWelcome()
            UserDefaults.standard.set(Updater.currentVersion, forKey: Prefs.lastSeenVersion)
        } else if Prefs.string(Prefs.lastSeenVersion) != Updater.currentVersion {
            // Just updated: open the full-screen intro → "Welcome to <codename>" → What's New.
            UserDefaults.standard.set(Updater.currentVersion, forKey: Prefs.lastSeenVersion)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.openUpdateExperience() }
        } else {
            // Normal launch: ask for anything a turned-on feature still needs.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.checkPermissions() }
        }
    }

    /// aries:// links from Shortcuts, scripts and other apps.
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { model?.handle(url: u) }
    }

    // MARK: Menu bar item

    private func updateStatusItem() {
        let want = Prefs.bool(Prefs.showMenuBarIcon)
        if want, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let mark = Bundle.main.image(forResource: "MenuBarIcon") {
                // The Aries "A" — a template image, so it turns white/black with the menu bar.
                mark.size = NSSize(width: mark.size.width * 18 / mark.size.height, height: 18)
                mark.isTemplate = true
                mark.accessibilityDescription = "Aries Dynamic Island"
                item.button?.image = mark
            } else {
                item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Aries Dynamic Island")
                item.button?.image?.isTemplate = true
            }
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Island", action: #selector(menuIsland), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Full-Screen Player", action: #selector(menuLyrics), keyEquivalent: "l").target = self
            menu.addItem(withTitle: "New Note", action: #selector(menuNote), keyEquivalent: "n").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Welcome Tour…", action: #selector(menuWelcome), keyEquivalent: "").target = self
            menu.addItem(withTitle: "What's New", action: #selector(menuWhatsNew), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Patch Notes", action: #selector(menuPatchNotes), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Help & Support…", action: #selector(menuHelp), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Report a Bug…", action: #selector(menuReportBug), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Request a Feature…", action: #selector(menuFeature), keyEquivalent: "").target = self
            menu.addItem(withTitle: "MAXX FORGE STUDIO Website", action: #selector(menuStudio), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Share Aries with Friends…", action: #selector(menuShare), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Check for Updates…", action: #selector(menuUpdates), keyEquivalent: "").target = self
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
    @objc private func menuWhatsNew() { openWhatsNew() }
    @objc private func menuPatchNotes() { openSettings(pane: "patchnotes") }
    @objc private func menuReportBug() { NSWorkspace.shared.open(PatchNotes.reportBugURL) }
    @objc private func menuFeature() { NSWorkspace.shared.open(PatchNotes.requestFeatureURL) }
    @objc private func menuHelp() { NSWorkspace.shared.open(PatchNotes.supportURL()) }
    @objc private func menuStudio() { NSWorkspace.shared.open(Brand.website) }
    @objc private func menuShare() {
        // Let the menu close first, then show the share menu under the menu bar icon.
        DispatchQueue.main.async { [weak self] in Brand.share(from: self?.statusItem?.button) }
    }
    @objc private func menuUpdates() { Updater.shared.check(silent: false); openSettings(pane: "updates") }
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

    /// Asks for new permissions automatically; nudges once per launch about ones that were turned down.
    func checkPermissions() {
        let pc = PermissionCenter.shared
        pc.refresh()
        pc.requestNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            pc.refresh()
            guard let first = pc.missing.first(where: { pc.statuses[$0] == .denied }) else { return }
            self?.model.show(Toast(icon: "hand.raised.fill", tint: .orange,
                                   title: "Allow \(PermissionCenter.info(first).title)",
                                   detail: "Settings", detailIcon: "arrow.right.circle.fill"), for: 5)
            self?.pendingPermissionPane = true
        }
    }
    var pendingPermissionPane = false

    /// Lets a text field inside the island receive typing.
    func focusIsland() { panelController?.focus() }

    // MARK: Windows

    private var welcomeController: WelcomeWindowController?

    func openWelcome() {
        if welcomeController == nil {
            welcomeController = WelcomeWindowController(app: self) { [weak self] in
                self?.welcomeController = nil
                UserDefaults.standard.set(1, forKey: Prefs.onboardingVersion)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.checkPermissions() }
                self?.model.celebrate()
                self?.model.show(Toast(icon: "sparkles", tint: .yellow, title: "Welcome to Aries", detail: "Hover me",
                                       detailIcon: "hand.wave.fill"), for: 4)
            }
        }
        welcomeController?.show()
    }

    private var updateExperience: UpdateExperienceController?
    func openUpdateExperience() {
        guard updateExperience == nil else { return }
        let c = UpdateExperienceController()
        c.onClose = { [weak self] in
            DispatchQueue.main.async {
                self?.updateExperience = nil
                PermissionCenter.shared.refresh()
                if !PermissionCenter.shared.missing.isEmpty {
                    self?.openSettings(pane: "permissions")
                    PermissionCenter.shared.requestNeeded()
                }
                self?.model.celebrate()
            }
        }
        updateExperience = c
        c.show()
    }

    private var whatsNew: WhatsNewWindowController?
    func openWhatsNew() {
        if whatsNew == nil {
            whatsNew = WhatsNewWindowController()
            whatsNew?.onClose = { [weak self] in
                DispatchQueue.main.async {
                    self?.whatsNew = nil
                    // Take people straight to anything this update needs permission for.
                    PermissionCenter.shared.refresh()
                    if !PermissionCenter.shared.missing.isEmpty {
                        self?.openSettings(pane: "permissions")
                        PermissionCenter.shared.requestNeeded()
                    }
                }
            }
        }
        whatsNew?.show()
    }

    /// Closes Settings, What's New, the Welcome tour and the update screen (used by aries://windows/close).
    func closeAuxWindows() {
        settingsWindow?.close()
        whatsNew?.closeWindow()
        welcomeController?.closeWindow(); welcomeController = nil
        updateExperience?.close()
    }

    /// Opens Settings on a specific pane ("music", "updates", …).
    func openSettings(pane: String) {
        UserDefaults.standard.set(pane, forKey: "settingsPane")
        openSettings()
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
            w.setContentSize(NSSize(width: 800, height: 600))
            w.center()
            settingsWindow = w
        }
        settingsWindow?.presentInFront()
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

    func closeLyrics() { lyricsController?.close() }

    func toggleLyrics() {
        if let c = lyricsController { c.close() } else { openLyrics() }
    }
}
