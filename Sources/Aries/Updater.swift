import AppKit
import SwiftUI

/// Checks GitHub Releases for a newer version and installs it in place.
final class Updater: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = Updater()
    static let repo = "maxxforgestudio-del/aries-dynamic-island"

    enum State: Equatable {
        case idle, checking, upToDate, available, downloading(Double), installing, failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseNotes = ""
    @Published private(set) var lastChecked: Date?
    private var downloadURL: URL?
    var canInstallInPlace: Bool { downloadURL != nil }
    private var timer: Timer?
    private var session: URLSession?

    /// Called when a new version is found during a background check.
    var onAvailable: ((String) -> Void)?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var releasesPage: URL { URL(string: "https://github.com/\(Self.repo)/releases/latest")! }

    func startAutomaticChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.check(silent: true) }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.check(silent: true)
        }
    }

    func check(silent: Bool) {
        if silent && !Prefs.bool(Prefs.autoUpdateCheck) { return }
        if case .downloading = state { return }
        state = .checking
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("AriesDynamicIsland/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        Task {
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = j["tag_name"] as? String else {
                await MainActor.run { self.state = silent ? .idle : .failed("Couldn't reach GitHub") }
                return
            }
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let assets = (j["assets"] as? [[String: Any]]) ?? []
            let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }?["browser_download_url"] as? String
            await MainActor.run {
                self.lastChecked = Date()
                self.latestVersion = version
                self.releaseNotes = (j["body"] as? String) ?? ""
                self.downloadURL = zip.flatMap(URL.init(string:))
                if Self.isNewer(version, than: Self.currentVersion) {
                    self.state = .available
                    if silent { self.onAvailable?(version) }
                } else {
                    self.state = .upToDate
                }
            }
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Install

    func install() {
        guard let url = downloadURL else { NSWorkspace.shared.open(releasesPage); return }
        state = .downloading(0)
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        session = s
        s.downloadTask(with: url).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        state = .downloading(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { state = .failed(error.localizedDescription) }
        session.finishTasksAndInvalidate()
        self.session = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        state = .installing
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("AriesUpdate-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            try fm.moveItem(at: location, to: zip)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zip.path, work.path]
            try unzip.run(); unzip.waitUntilExit()
            guard unzip.terminationStatus == 0,
                  let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                      .first(where: { $0.pathExtension == "app" }),
                  Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier
            else { throw NSError(domain: "Aries", code: 1, userInfo: [NSLocalizedDescriptionKey: "The download didn't contain Aries"]) }

            let current = Bundle.main.bundleURL
            _ = try fm.replaceItemAt(current, withItemAt: newApp)
            relaunch(current)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }
}

// MARK: - What's New

final class WhatsNewWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    func closeWindow() { window.close() }
    var onClose: (() -> Void)?
    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: PermissionCenter.shared.missing.isEmpty ? 760 : 900),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        super.init()
        window.delegate = self
        window.contentView = NSHostingView(rootView: WhatsNewView { [weak self] in self?.window.close() })
    }
    func show() { window.presentInFront() }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

struct WhatsNewView: View {
    var done: () -> Void
    var showClose = false
    @ViewState private var shown = false

    static let items: [(String, Color, String, String)] = [
        ("drop.fill", .cyan, "Aquatic & Crystal glass", "A see-through glass island, popups and Settings, like Apple's Liquid Glass."),
        ("opticaldisc.fill", .pink, "Lyrics, reimagined", "Three full-screen styles: Apple Music–style Lyrics, a spinning Vinyl record, and Karaoke."),
        ("music.mic", .purple, "Karaoke with a score", "Big two-line karaoke with a countdown before the vocals, plus Sing Along scoring from your mic."),
        ("person.wave.2.fill", .green, "Deeper Spotify", "Artist pages with Follow and top songs, full album tracklists, Add to Playlist, Play Next and Recently Played."),
        ("waveform.badge.magnifyingglass", .green, "Lyrics that stay in sync", "Smarter timing keeps words right on the beat, and you can nudge any song with − / +."),
        ("sparkles.rectangle.stack.fill", .orange, "Living album art", "Artwork that gently moves while you listen, over a flowing background."),
        ("lock.fill", .indigo, "Lock Screen widgets", "See and control what's playing, plus weather, your next event and battery, while your Mac is locked."),
        ("rectangle.3.group.fill", .blue, "Desktop widgets", "Now Playing, Clock, Weather, Up Next, Battery and To-Dos, right on your wallpaper."),
        ("moon.fill", .indigo, "Focus modes", "The island shows when Do Not Disturb, Work, Sleep or any Focus turns on, just like iPhone."),
        ("square.grid.2x2.fill", .yellow, "New Tools tab", "Calculator and converter, Keep Awake, Color Picker, Screenshot, Dark Mode and a Coin Flip."),
        ("video.fill", .mint, "FaceTime & instant calls", "Rings the moment a call comes in, and knows FaceTime Audio, FaceTime Video and iPhone calls."),
        ("capslock.fill", .green, "More iPhone moments", "Caps Lock, Low Power Mode and offline alerts, plus a second activity in its own bubble."),
        ("bolt.horizontal.circle.fill", .orange, "Live Activities for everything", "Shortcuts, scripts and apps can start their own island activity with an aries:// link."),
        ("music.note.house.fill", .green, "Music Connections", "Spotify, Apple Music, plus YouTube Music, SoundCloud and more in your browser (beta)."),
        ("face.smiling.inverse", .pink, "Meet the new Aries", "Your ram got a full makeover, with new moods and smoother animations."),
        ("gearshape.2.fill", .blue, "All-new Settings & Accessibility", "Searchable Settings, plus reduce motion, transparency and more."),
        ("arrow.triangle.2.circlepath", .indigo, "Automatic updates", "Aries now keeps itself up to date, all by itself."),
    ]

    var body: some View {
        ZStack {
            GlowBackground()
            if showClose {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: done) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .glassCircle()
                        }
                        .buttonStyle(PressableStyle(hoverFill: .clear))
                        .keyboardShortcut(.cancelAction)
                        .help("Close")
                    }
                    Spacer()
                }
                .padding(28)
            }
            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    Text("WHAT'S NEW IN ARIES")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.6))
                    WelcomeLettering(text: Brand.codename.isEmpty ? "Aries" : Brand.codename, duration: 2.0)
                        .frame(width: 300, height: 92)
                    Text(Brand.versionLine)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(Array(Self.items.enumerated()), id: \.offset) { i, it in
                        HStack(spacing: 14) {
                            Image(systemName: it.0)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(it.1)
                                .frame(width: 42, height: 42)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(it.1.opacity(0.18)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(it.2).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                Text(it.3).font(.system(size: 12.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .opacity(shown ? 1 : 0)
                        .offset(x: shown ? 0 : -20)
                        .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.1 + Double(i) * 0.07), value: shown)
                    }
                }
                .frame(maxWidth: 480, alignment: .leading)
                PermissionsCallout(center: PermissionCenter.shared)
                    .frame(maxWidth: 520)
                    .padding(.top, 8)
                }
                .frame(maxHeight: 520)
                Button(action: done) {
                    Text("Continue")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 34).padding(.vertical, 10)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(PressableStyle(hoverFill: .clear))
                .keyboardShortcut(.defaultAction)
                MadeByMaxxForge(compact: true).foregroundStyle(.white.opacity(0.55))
            }
            .padding(36)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { shown = true }
    }
}


/// "Finish setting up": any permission a feature still needs, with one-click fixes.
struct PermissionsCallout: View {
    @ObservedObject var center: PermissionCenter
    var body: some View {
        let missing = center.missing
        Group {
            if !missing.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("FINISH SETTING UP", systemImage: "hand.raised.fill")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.orange)
                    ForEach(missing) { k in PermissionRow(kind: k, center: center, dark: true) }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.orange.opacity(0.35)))
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: missing)
        .onAppear { center.refresh() }
    }
}


// MARK: - Update experience (opens by itself after every update)

/// Full-screen, Apple-style: the brand intro plays, "Welcome to <codename>" writes itself,
/// then Continue glides into What's New.
final class UpdateExperienceController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    var onClose: (() -> Void)?

    override init() {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main!
        window = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.setFrame(screen.frame, display: true)
        window.contentView = NSHostingView(rootView: UpdateExperienceView { [weak self] in self?.close() })
        window.alphaValue = 0
    }

    func show() {
        NSCursor.setHiddenUntilMouseMoves(true)
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window.orderFrontRegardless()
        window.makeKey()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.6; window.animator().alphaValue = 1 }
    }

    func close() {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.45; window.animator().alphaValue = 0 },
                                            completionHandler: { [weak self] in
            self?.window.orderOut(nil)
            self?.onClose?()
        })
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}

private final class KeyableWindow: NSWindow { override var canBecomeKey: Bool { true } }

struct UpdateExperienceView: View {
    var close: () -> Void
    private enum Phase { case intro, welcome, whatsNew }
    @ViewState private var phase: Phase = .intro
    @ViewState private var welcomeDone = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch phase {
            case .intro:
                BrandIntroPlayer {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { go(.welcome) }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            case .welcome:
                welcome
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)),
                                            removal: .opacity.combined(with: .scale(scale: 0.94))))
            case .whatsNew:
                WhatsNewView(done: close, showClose: true)
                    .frame(maxWidth: 720, maxHeight: 820)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.12)))
                    .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
                    .padding(40)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .offset(y: 40)),
                                            removal: .opacity))
            }
            if phase != .whatsNew {
                VStack {
                    HStack {
                        Spacer()
                        Button("Skip") { go(.whatsNew) }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                }
                .padding(32)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("WELCOME TO")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .tracking(6)
                .foregroundStyle(.white.opacity(0.6))
            WelcomeLettering(text: Brand.codename.isEmpty ? "Aries" : Brand.codename, duration: 2.6) {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { welcomeDone = true }
            }
            .frame(width: 620, height: 210)
            Text("Aries \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .opacity(welcomeDone ? 1 : 0)
            Button { go(.whatsNew) } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 40).padding(.vertical, 13)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(PressableStyle(hoverFill: .clear))
            .keyboardShortcut(.defaultAction)
            .opacity(welcomeDone ? 1 : 0)
            .scaleEffect(welcomeDone ? 1 : 0.85)
            Spacer()
            MadeByMaxxForge(compact: true).foregroundStyle(.white.opacity(0.5)).padding(.bottom, 30)
        }
    }

    private func go(_ p: Phase) {
        withAnimation(.spring(response: 0.75, dampingFraction: 0.86)) { phase = p }
    }
}
