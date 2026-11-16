import SwiftUI
import ServiceManagement

private struct Pane: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    var keywords: String = ""
    var blurb: String { paneBlurbs[id] ?? "" }
    /// Glow/tint color for the page (black and gray icons get a livelier accent).
    var accent: Color {
        switch id {
        case "island": return Color(red: 0.32, green: 0.86, blue: 1.0)
        case "general": return Color(red: 0.45, green: 0.58, blue: 0.85)
        default: return color
        }
    }
}

private let paneBlurbs: [String: String] = [
    "general": "Start-up, menu bar and the basics.",
    "island": "Shape, glass and glow — make the notch yours.",
    "widgets": "What lives inside the island.",
    "desktop": "Widgets on your desktop and Lock Screen.",
    "music": "How your music shows up in the notch.",
    "spotify": "Connect Spotify, Apple Music and the web.",
    "lyrics": "Karaoke, vinyl and word-by-word sync.",
    "calls": "Answer calls and FaceTime from the notch.",
    "popups": "Little moments, just like iPhone.",
    "shortcuts": "Keys and gestures to drive Aries.",
    "accessibility": "Motion, contrast and spoken feedback.",
    "permissions": "Your data stays yours.",
    "updates": "Always on the newest Aries.",
    "patchnotes": "What's new, what's fixed, what's next.",
    "about": "Made by Maxx Forge Studio.",
]

private let panes: [Pane] = [
    .init(id: "general", title: "General", icon: "gearshape.fill", color: .gray, keywords: "login startup menu bar haptics quit"),
    .init(id: "island", title: "Island", icon: "capsule.fill", color: Color(white: 0.2), keywords: "glass aquatic classic hover look glow notes visualizer style"),
    .init(id: "widgets", title: "Widgets", icon: "square.grid.2x2.fill", color: .blue, keywords: "home weather calendar notes shelf timer mirror clipboard ram buddy"),
    .init(id: "desktop", title: "Desktop & Lock Screen", icon: "rectangle.3.group.fill", color: .orange, keywords: "widgets desktop lock screen now playing clock weather battery to-dos"),
    .init(id: "music", title: "Music", icon: "music.note", color: .pink, keywords: "player lyrics announce lock screen"),
    .init(id: "spotify", title: "Music Connections", icon: "music.note.house.fill", color: Color(red: 0.11, green: 0.73, blue: 0.33), keywords: "connect spotify apple music youtube soundcloud tidal deezer amazon pandora account phone premium web"),
    .init(id: "lyrics", title: "Lyrics", icon: "quote.bubble.fill", color: .purple, keywords: "full screen karaoke vinyl sing timing sync offset behind ahead animated artwork size"),
    .init(id: "calls", title: "Calls", icon: "phone.fill", color: .green, keywords: "facetime zoom answer decline mute"),
    .init(id: "popups", title: "Popups & Indicators", icon: "bell.badge.fill", color: .red, keywords: "volume airpods charging unlock downloads mic camera battery focus do not disturb caps lock low power offline wifi"),
    .init(id: "shortcuts", title: "Shortcuts & Gestures", icon: "command", color: .indigo, keywords: "keyboard swipe scroll hotkeys"),
    .init(id: "accessibility", title: "Accessibility", icon: "accessibility", color: .blue, keywords: "reduce motion transparency contrast larger voiceover"),
    .init(id: "permissions", title: "Privacy & Security", icon: "hand.raised.fill", color: .teal, keywords: "privacy security protection screen sharing recording hide lock screen erase data sign out allow access automation calendar accessibility camera tracking"),
    .init(id: "updates", title: "Software Update", icon: "arrow.triangle.2.circlepath", color: .cyan, keywords: "update version automatic install"),
    .init(id: "patchnotes", title: "Patch Notes", icon: "doc.text.fill", color: Color(red: 0.2, green: 0.6, blue: 0.55), keywords: "patch notes changelog changes fixes bugs known issues report bug release notes"),
    .init(id: "about", title: "About", icon: "info.circle.fill", color: .orange, keywords: "maxx forge studio version license support"),
]

struct SettingsView: View {
    @ObservedObject var music: MusicController
    @ObservedObject var spotify: SpotifyWeb
    @ObservedObject private var patchNotes = PatchNotes.shared
    @AppStorage("settingsPane") private var pane = "general"
    @ViewState private var search = ""
    @Namespace private var ns

    private var current: Pane { panes.first { $0.id == pane } ?? panes[0] }
    private var filtered: [Pane] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return panes }
        return panes.filter { ($0.title + " " + $0.keywords).lowercased().contains(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 250)
                .background(GlassBackdrop(material: .sidebar))
            VStack(alignment: .leading, spacing: 0) {
                if patchNotes.isUnsupported {
                    UnsupportedBanner()
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.red.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.red.opacity(0.35)))
                        .padding(.horizontal, 22).padding(.top, 34)
                }
                SettingsHero(pane: current)
                    .padding(.horizontal, 22)
                    .padding(.top, patchNotes.isUnsupported ? 14 : 34)
                    .padding(.bottom, 6)
                    .id(pane)
                    .transition(.asymmetric(insertion: .settingsIn, removal: .opacity))

                Group {
                    switch pane {
                    case "island": IslandPane()
                    case "widgets": WidgetsPane()
                    case "desktop": DesktopWidgetsPane()
                    case "music": MusicPane()
                    case "spotify": SpotifyPane(spotify: spotify)
                    case "lyrics": LyricsPane()
                    case "calls": CallsPane(calls: AppDelegate.shared.model.calls)
                    case "popups": PopupsPane()
                    case "shortcuts": ShortcutsPane()
                    case "accessibility": AccessibilityPane()
                    case "permissions": PermissionsPane(center: PermissionCenter.shared)
                    case "updates": UpdatesPane(updater: Updater.shared)
                    case "patchnotes": PatchNotesPane(notes: PatchNotes.shared)
                    case "about": AboutPane(music: music)
                    default: GeneralPane(music: music)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .id(pane)
                .transition(.asymmetric(insertion: .settingsIn.animation(.spring(response: 0.5, dampingFraction: 0.86).delay(0.04)),
                                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                ZStack {
                    Color(nsColor: .windowBackgroundColor).opacity(0.9)
                    SettingsAurora(color: current.accent)
                }
                .ignoresSafeArea()
            )
        }
        .animation(A11y.reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86), value: pane)
        .frame(minWidth: 820, minHeight: 600)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Profile card (Windows 11 style)
            HStack(spacing: 11) {
                Group {
                    if let logo = Brand.appLogo {
                        Image(nsImage: logo).resizable().scaledToFill()
                    } else {
                        Image(nsImage: NSApp.applicationIconImage).resizable()
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.15)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Aries Dynamic Island").font(.system(size: 13, weight: .bold))
                    Text(Brand.versionLine).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Text("by Maxx Forge Studio").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.06)))
            .padding(.top, 40)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a setting", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.07)))
            .overlay(alignment: .bottom) {
                Capsule().fill(Color.accentColor).frame(height: 2).padding(.horizontal, 6).opacity(search.isEmpty ? 0 : 1)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(filtered) { p in
                        SidebarRow(p: p, selected: pane == p.id, unread: p.id == "patchnotes" && patchNotes.hasUnread, ns: ns) {
                            pane = p.id
                            if filtered.count == 1 { search = "" }
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pane)
            }
            MadeByMaxxForge(compact: true).foregroundStyle(.secondary).padding(.bottom, 14)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    @ObservedObject var music: MusicController
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Prefs.hideInFullscreen) private var hideInFullscreen = false
    @AppStorage(Prefs.haptics) private var haptics = true
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var loginError: String?

    var body: some View {
        Form {
            Section { AppHeader(music: music) }
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                Toggle("Hide during full-screen apps", isOn: $hideInFullscreen)
                Toggle("Haptic feedback on trackpad", isOn: $haptics)
            }
            Section {
                HStack {
                    Button("Welcome Tour") { AppDelegate.shared.openWelcome() }
                    Button("What's New") { AppDelegate.shared.openWhatsNew() }
                    Spacer()
                    Button("Quit Aries") { NSApp.terminate(nil) }
                }
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription). Move Aries to Applications and try again."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct AppHeader: View {
    @ObservedObject var music: MusicController
    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .shadow(color: music.accent.opacity(0.4), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text("Aries Dynamic Island").font(.system(size: 22, weight: .bold))
                Text(music.track.map { "Now playing: \($0.title) — \($0.artist)" } ?? "Your notch, alive.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct IslandPane: View {
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = true
    @AppStorage(Prefs.hoverDelay) private var hoverDelay = 0.12
    @AppStorage(Prefs.hoverBounce) private var hoverBounce = true
    @AppStorage(Prefs.musicGlow) private var musicGlow = true
    @AppStorage(Prefs.showNotes) private var showNotes = true
    @AppStorage(Prefs.notesIntensity) private var notesIntensity = 0.35
    @AppStorage(Prefs.showVisualizer) private var showVisualizer = true
    @AppStorage(Prefs.artworkAccent) private var artworkAccent = true
    @AppStorage(Prefs.islandStyle) private var islandStyle = "aquatic"

    var body: some View {
        Form {
            Section("Opening") {
                Toggle("Expand when hovering", isOn: $expandOnHover)
                if expandOnHover {
                    LabeledContent("Hover delay") {
                        Slider(value: $hoverDelay, in: 0...0.6) { EmptyView() }
                            minimumValueLabel: { Text("Instant").font(.caption) }
                            maximumValueLabel: { Text("Relaxed").font(.caption) }
                            .frame(width: 240)
                    }
                } else {
                    Text("Click the island to open it.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Bouncy hover", isOn: $hoverBounce)
            }
            Section("Look") {
                Picker("Island style", selection: $islandStyle) {
                    Text("Aquatic").tag("aquatic")
                    Text("Crystal").tag("crystal")
                    Text("Classic").tag("classic")
                }
                .pickerStyle(.segmented)
                Text(islandStyle == "crystal" ? "Crystal: the whole island is see-through glass, even when closed."
                     : islandStyle == "aquatic" ? "Aquatic: glass when open, solid black where it meets the notch so it blends into the camera."
                     : "Classic: solid black, like iPhone.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Tint with album colors", isOn: $artworkAccent)
                Toggle("Live visualizer", isOn: $showVisualizer)
                Toggle("Soft glow while playing", isOn: $musicGlow)
                Toggle("Music notes effect", isOn: $showNotes)
                if showNotes {
                    LabeledContent("Notes intensity") {
                        Slider(value: $notesIntensity, in: 0...1) { EmptyView() }
                            minimumValueLabel: { Image(systemName: "music.note").font(.caption) }
                            maximumValueLabel: { Image(systemName: "music.note.list").font(.caption) }
                            .frame(width: 240)
                    }
                }
            }
        }
    }
}

private struct WidgetsPane: View {
    @AppStorage(Prefs.showBuddy) private var showBuddy = true
    @AppStorage(Prefs.showWeather) private var showWeather = true
    @AppStorage(Prefs.fahrenheit) private var fahrenheit = true
    @AppStorage(Prefs.showCalendar) private var showCalendar = true
    @AppStorage(Prefs.meetingAlerts) private var meetingAlerts = true
    @AppStorage(Prefs.showNotesTab) private var showNotesTab = true
    @AppStorage(Prefs.showShelf) private var showShelf = true
    @AppStorage(Prefs.showTimer) private var showTimer = true
    @AppStorage(Prefs.timerSound) private var timerSound = true
    @AppStorage(Prefs.showMirror) private var showMirror = true
    @AppStorage(Prefs.showClipboard) private var showClipboard = false
    @AppStorage(Prefs.showTools) private var showTools = true
    @ViewState private var cityDraft = Prefs.string(Prefs.weatherCity)

    var body: some View {
        let model = AppDelegate.shared.model!
        Form {
            Section("Home") {
                Toggle(isOn: $showBuddy) { Label("Aries the ram", systemImage: "face.smiling") }
                Toggle(isOn: $showWeather) { Label("Weather", systemImage: "cloud.sun") }
                if showWeather {
                    HStack {
                        TextField("City", text: $cityDraft).textFieldStyle(.roundedBorder)
                            .onSubmit { model.weather.setCity(cityDraft) }
                        Button("Set") { model.weather.setCity(cityDraft) }
                        Toggle("°F", isOn: $fahrenheit).toggleStyle(.checkbox)
                            .onChange(of: fahrenheit) { _, _ in model.weather.refresh() }
                    }
                }
                Toggle(isOn: $showCalendar) { Label("Next calendar event", systemImage: "calendar") }
                    .onChange(of: showCalendar) { _, _ in model.calendar.refresh() }
                if showCalendar {
                    Toggle(isOn: $meetingAlerts) { Label("Heads-up 5 min before events", systemImage: "bell.badge") }
                    if !model.calendar.authorized {
                        Button("Allow Calendar Access") { model.calendar.requestAccess() }
                    }
                }
            }
            Section("Tabs") {
                Toggle(isOn: $showNotesTab) { Label("Notes & to-dos", systemImage: "note.text") }
                Toggle(isOn: $showShelf) { Label("File Shelf", systemImage: "tray.full") }
                Toggle(isOn: $showTimer) { Label("Timer", systemImage: "timer") }
                if showTimer {
                    Toggle(isOn: $timerSound) { Label("Chime when done", systemImage: "speaker.wave.2") }
                }
                Toggle(isOn: $showTools) { Label("Tools (calculator, keep awake, color picker…)", systemImage: "square.grid.2x2") }
                Toggle(isOn: $showMirror) { Label("Mirror (camera check)", systemImage: "person.crop.square") }
                Toggle(isOn: $showClipboard) { Label("Clipboard history", systemImage: "doc.on.clipboard") }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Clipboard history stays in memory only and skips password managers. The Mirror camera turns off when the island closes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct MusicPane: View {
    @AppStorage(Prefs.preferredSource) private var preferredSource = "auto"
    @AppStorage(Prefs.showLyricLine) private var showLyricLine = true
    @AppStorage(Prefs.liveLyrics) private var liveLyrics = true
    @AppStorage(Prefs.announceSongs) private var announceSongs = true
    @AppStorage(Prefs.lockScreenMirror) private var lockScreenMirror = true
    @AppStorage(Prefs.pausedLinger) private var pausedLinger = 20.0

    var body: some View {
        Form {
            Section {
                Picker("Preferred player", selection: $preferredSource) {
                    Text("Automatic").tag("auto")
                    Text("Spotify").tag("spotify")
                    Text("Apple Music").tag("music")
                }
                LabeledContent("Keep player after pausing") {
                    Picker("", selection: $pausedLinger) {
                        Text("5 sec").tag(5.0); Text("20 sec").tag(20.0); Text("1 min").tag(60.0); Text("5 min").tag(300.0)
                    }
                    .labelsHidden().frame(width: 120)
                }
            }
            Section("In the notch") {
                Toggle("Live lyrics under the notch", isOn: $liveLyrics)
                Toggle("Current lyric in the expanded player", isOn: $showLyricLine)
                Toggle("Announce new songs", isOn: $announceSongs)
            }
            Section {
                Toggle("Show phone playback on Lock Screen & Control Center", isOn: $lockScreenMirror)
            } footer: {
                Text("When music plays on your iPhone, Aries publishes it to macOS's Now Playing, so it appears on the lock screen and your keyboard's ⏯ keys control it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SpotifyPane: View {
    @ObservedObject var spotify: SpotifyWeb
    @AppStorage(Prefs.usePhoneSpotify) private var usePhoneSpotify = true
    @AppStorage(Prefs.spotifyClientID) private var clientID = ""

    @AppStorage(Prefs.webPlayers) private var webPlayers = false
    @ObservedObject private var perms = PermissionCenter.shared
    @ViewState private var showSetup = false

    var body: some View {
        Form {
            Section {
                serviceRow("Spotify app", icon: "music.note", color: Color(red: 0.11, green: 0.73, blue: 0.33),
                           detail: "Now playing and controls for the Spotify app on this Mac.", kind: .spotify,
                           bundleID: LocalPlayers.spotifyID)
                serviceRow("Apple Music app", icon: "music.note.list", color: .pink,
                           detail: "Now playing and controls for the Music app on this Mac.", kind: .music,
                           bundleID: LocalPlayers.musicID)
            } header: {
                Text("Apps on this Mac")
            } footer: {
                Text("One click each. macOS asks once to let Aries control the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $webPlayers) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Web players (beta)")
                        Text("YouTube Music, YouTube, SoundCloud, TIDAL, Deezer, Amazon Music, Pandora and Spotify's web player in Safari, Chrome, Arc, Edge or Brave.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if webPlayers {
                    HStack(spacing: 6) {
                        ForEach(WebPlayers.services.prefix(7), id: \.name) { svc in
                            Text(svc.name).font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(.primary.opacity(0.08)))
                        }
                    }
                    Text("macOS asks once per browser to let Aries read its tabs. Play, pause and skip use your Mac's media keys, which needs Accessibility.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("In your browser")
            }
            Section {
                accountCard
                if spotify.isConnected {
                    Toggle("Show music playing on my phone and other devices", isOn: $usePhoneSpotify)
                }
            } header: {
                Text("Spotify account")
            } footer: {
                Text("Your account adds music on your iPhone and other devices, artist & album pages, your playlists, Up Next, Like, Search and Play on…. Controlling phone playback needs Spotify Premium. Apple Music on iPhone can't be read from a Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var accountCard: some View {
        if spotify.isConnected {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 22)).foregroundStyle(Color(red: 0.11, green: 0.73, blue: 0.33))
                VStack(alignment: .leading, spacing: 2) {
                    Text(spotify.accountName.map { "Signed in as \($0)" } ?? "Signed in").font(.system(size: 13.5, weight: .semibold))
                    Text("Phone playback, artist pages and playlists are on.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sign Out", role: .destructive) { spotify.disconnect() }.controlSize(.small)
            }
        } else if spotify.hasClientID && !showSetup {
            // Already set up once: signing in is a single click.
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle").font(.system(size: 22)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not signed in").font(.system(size: 13.5, weight: .semibold))
                    Text(spotify.status == "Not connected" ? "Sign in to see your phone's music, artist pages and playlists." : spotify.status)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Change App…") { showSetup = true }.buttonStyle(.borderless).controlSize(.small)
                Button("Connect Spotify") { spotify.connect() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.11, green: 0.73, blue: 0.33))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("One-time setup — about a minute").font(.callout.weight(.semibold))
                step(1, "Click **Start Setup**. Aries copies the Redirect URI for you and opens Spotify's dashboard.") {
                    Button(spotify.waitingForClientID ? "Open Dashboard Again" : "Start Setup") { spotify.beginSetup() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.11, green: 0.73, blue: 0.33))
                }
                step(2, "Name the app anything, paste into **Redirect URIs** (⌘V), tick **Web API**, and click **Save**.") {
                    HStack {
                        Text(SpotifyWeb.redirectURI)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SpotifyWeb.redirectURI, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy")
                    }
                }
                step(3, "Copy the **Client ID** (⌘C). That's it — Aries picks it up and connects by itself.") {
                    HStack {
                        if spotify.waitingForClientID {
                            ProgressView().controlSize(.small)
                            Text("Watching for your Client ID…").font(.caption).foregroundStyle(.secondary)
                        }
                        TextField("", text: $clientID, prompt: Text("or paste it here"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: clientID) { _, v in
                                if SpotifyWeb.looksLikeClientID(v.trimmingCharacters(in: .whitespaces)) {
                                    spotify.stopWaiting(); showSetup = false; spotify.connect()
                                }
                            }
                    }
                }
                HStack {
                    Text(spotify.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if showSetup { Button("Cancel") { showSetup = false }.controlSize(.small) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func step<C: View>(_ n: Int, _ text: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.secondary))
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.callout)
                content()
            }
        }
    }

    private func serviceRow(_ name: String, icon: String, color: Color, detail: String,
                            kind: PermissionCenter.Kind, bundleID: String) -> some View {
        let st = perms.statuses[kind]
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch st {
            case .granted?:
                Label("Connected", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(.green)
            case .denied?:
                Button("Fix") { perms.fix(kind) }.buttonStyle(.borderedProminent).controlSize(.small)
            case .notAsked?:
                Button("Connect") { perms.request(kind) }.buttonStyle(.borderedProminent).controlSize(.small)
            default:
                // Not running yet: open it quietly in the background, then ask for permission.
                Button("Connect") { perms.connectApp(kind, bundleID: bundleID) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }
}

private struct LyricsPane: View {
    @AppStorage(Prefs.lyricsSize) private var lyricsSize = 42.0
    @AppStorage(Prefs.lyricsStyle) private var style = "lyrics"
    @AppStorage(Prefs.lyricsOffset) private var offset = 0.0
    @AppStorage(Prefs.animatedArt) private var animatedArt = true
    var body: some View {
        Form {
            Section("Style") {
                Picker("Full-screen style", selection: $style) {
                    ForEach(LyricsStyle.allCases) { s in Label(s.title, systemImage: s.icon).tag(s.rawValue) }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $animatedArt) { Label("Animated album art", systemImage: "sparkles.rectangle.stack") }
            }
            Section {
                LabeledContent("Lyrics timing") {
                    HStack {
                        Slider(value: $offset, in: -1.5...1.5, step: 0.05).frame(width: 200)
                        Text(offset == 0 ? "In sync" : String(format: "%+.2fs", offset)).monospacedDigit().frame(width: 64)
                        Button("Reset") { offset = 0 }.controlSize(.small).disabled(offset == 0)
                    }
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("If lyrics are always a little behind or ahead on your Mac, slide this (+ makes lyrics earlier). For one song, use the − / + timing control at the top of the full-screen player or press [ and ]; Aries remembers it for that song.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Text size") {
                    Slider(value: $lyricsSize, in: 28...64) { EmptyView() }
                        minimumValueLabel: { Text("A").font(.system(size: 11, weight: .bold)) }
                        maximumValueLabel: { Text("A").font(.system(size: 17, weight: .bold)) }
                        .frame(width: 240)
                }
                Button("Open Full-Screen Player") { AppDelegate.shared.openLyrics() }
            } footer: {
                Text("Synced lyrics come from LRCLIB, a free open lyrics library. Words light up with real timing when the lyrics include it. In the full-screen player: 1 2 3 or L switch Lyrics / Vinyl / Karaoke, click a line to jump to it, right-click to copy it, − + text size, [ ] timing, space play/pause, ← → skip, ↑ ↓ volume, esc to close.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct CallsPane: View {
    @ObservedObject var calls: CallMonitor
    @AppStorage(Prefs.callActivity) private var callActivity = true
    @AppStorage(Prefs.callBanner) private var callBanner = true
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $callActivity) { Label("Show calls in the island", systemImage: "phone.fill") }
                Toggle(isOn: $callBanner) { Label("Answer iPhone calls from the island", systemImage: "phone.arrow.down.left") }
                if callBanner {
                    LabeledContent("Accessibility") {
                        if calls.axTrusted {
                            Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Allow…") { calls.requestAccessibility() }
                        }
                    }
                }
            } footer: {
                Text("Aries notices FaceTime, iPhone (Continuity), Zoom, Teams, Discord, Slack, Webex and WhatsApp calls by which app is using your mic, and shows a timer with mute and end buttons. Answering needs Accessibility so Aries can press the call banner's buttons.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PopupsPane: View {
    @AppStorage(Prefs.volumeHUD) private var volumeHUD = true
    @AppStorage(Prefs.deviceToasts) private var deviceToasts = true
    @AppStorage(Prefs.unlockAnimation) private var unlockAnimation = true
    @AppStorage(Prefs.chargingToast) private var chargingToast = true
    @AppStorage(Prefs.showMic) private var showMic = true
    @AppStorage(Prefs.showCamera) private var showCamera = true
    @AppStorage(Prefs.showBattery) private var showBattery = true
    @AppStorage(Prefs.downloadsActivity) private var downloadsActivity = false
    @AppStorage(Prefs.downloadsToShelf) private var downloadsToShelf = true
    @AppStorage(Prefs.focusToasts) private var focusToasts = true
    @AppStorage(Prefs.capsLockToast) private var capsLockToast = true
    @AppStorage(Prefs.lowPowerToast) private var lowPowerToast = true
    @AppStorage(Prefs.networkToast) private var networkToast = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $focusToasts) { Label("Focus modes (Do Not Disturb, Work, Sleep…)", systemImage: "moon.fill") }
                Toggle(isOn: $capsLockToast) { Label("Caps Lock", systemImage: "capslock.fill") }
                Toggle(isOn: $lowPowerToast) { Label("Low Power Mode", systemImage: "battery.25percent") }
                Toggle(isOn: $networkToast) { Label("Going offline / back online", systemImage: "wifi") }
            } header: {
                Text("Like iPhone")
            } footer: {
                Text("Focus is read from the Focus icon in your menu bar (uses the Accessibility permission). For the most reliable Focus detection, also give Aries Full Disk Access in Privacy & Security.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Popups") {
                Toggle(isOn: $volumeHUD) { Label("Volume", systemImage: "speaker.wave.3.fill") }
                Toggle(isOn: $deviceToasts) { Label("AirPods & audio devices connecting", systemImage: "airpodspro") }
                Toggle(isOn: $chargingToast) { Label("Charging", systemImage: "bolt.fill") }
                Toggle(isOn: $unlockAnimation) { Label("Unlock greeting", systemImage: "lock.open.fill") }
            }
            Section {
                Toggle(isOn: $downloadsActivity) { Label("Download progress", systemImage: "arrow.down.circle.fill") }
                    .onChange(of: downloadsActivity) { _, on in AppDelegate.shared.model.downloads.setEnabled(on) }
                if downloadsActivity {
                    Toggle(isOn: $downloadsToShelf) { Label("Put finished downloads on the Shelf", systemImage: "tray.and.arrow.down") }
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text("Watches your Downloads folder for files that are still downloading in Safari, Chrome, Arc, Edge, Brave or Firefox. macOS will ask to let Aries see the Downloads folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Indicators") {
                Toggle(isOn: $showMic) { Label("Microphone in use", systemImage: "mic.fill") }
                Toggle(isOn: $showCamera) { Label("Camera in use", systemImage: "video.fill") }
                Toggle(isOn: $showBattery) { Label("Battery level & low-battery alerts", systemImage: "battery.75percent") }
            }
        }
    }
}

private struct ShortcutsPane: View {
    @AppStorage(Prefs.hotkeys) private var hotkeys = true
    @AppStorage(Prefs.gestures) private var gestures = true
    var body: some View {
        Form {
            Section("Keyboard") {
                Toggle("Enable shortcuts", isOn: $hotkeys)
                if hotkeys {
                    ForEach(Hotkeys.all, id: \.id) { s in
                        LabeledContent(s.title) {
                            Text(s.glyph).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Toggle("Trackpad gestures on the island", isOn: $gestures)
                if gestures {
                    LabeledContent("Two-finger swipe left / right") { Text("Next / previous song").foregroundStyle(.secondary) }
                    LabeledContent("Two-finger scroll up / down") { Text("Volume (island closed)").foregroundStyle(.secondary) }
                    LabeledContent("Right-click") { Text("Quick menu").foregroundStyle(.secondary) }
                }
            } header: {
                Text("Gestures")
            }
        }
    }
}

private struct UpdatesPane: View {
    @ObservedObject var updater: Updater
    @AppStorage(Prefs.autoUpdateCheck) private var autoUpdateCheck = true
    @AppStorage(Prefs.autoInstallUpdates) private var autoInstall = true

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline)
                        Text("You have Aries \(Brand.versionLine.replacingOccurrences(of: "Version ", with: ""))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    switch updater.state {
                    case .available:
                        Button("Update Now") { updater.install() }.buttonStyle(.borderedProminent)
                    case .downloading(let p):
                        ProgressView(value: p).frame(width: 120)
                    case .checking, .installing:
                        ProgressView().controlSize(.small)
                    default:
                        Button("Check Now") { updater.check(silent: false) }
                    }
                }
                .padding(.vertical, 4)
                if updater.state == .available, !updater.releaseNotes.isEmpty {
                    ScrollView {
                        Text(updater.releaseNotes)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)
                }
            }
            Section {
                Toggle("Check for updates automatically", isOn: $autoUpdateCheck)
                Toggle("Install updates automatically", isOn: $autoInstall)
                    .disabled(!autoUpdateCheck)
                if let d = updater.lastChecked {
                    LabeledContent("Last checked") { Text(d, style: .relative).foregroundStyle(.secondary) }
                }
                Link("View all releases on GitHub", destination: URL(string: "https://github.com/\(Updater.repo)/releases")!)
            }
        }
        .onAppear { if updater.state == .idle { updater.check(silent: false) } }
    }

    private var title: String {
        switch updater.state {
        case .checking: return "Checking for updates…"
        case .upToDate: return "Aries is up to date"
        case .available: return "Aries \(updater.latestVersion ?? "") is available"
        case .downloading: return "Downloading update…"
        case .installing: return "Installing — Aries will restart"
        case .failed(let e): return "Couldn't update: \(e)"
        case .idle: return "Software Update"
        }
    }
    private var icon: String {
        switch updater.state {
        case .upToDate: return "checkmark.seal.fill"
        case .available: return "arrow.down.app.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "arrow.triangle.2.circlepath"
        }
    }
    private var color: Color {
        switch updater.state {
        case .upToDate: return .green
        case .failed: return .orange
        default: return .blue
        }
    }
}

private struct AboutPane: View {
    @ObservedObject var music: MusicController
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    if let logo = Brand.appLogo {
                        Image(nsImage: logo).resizable().scaledToFit().frame(height: 170)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    Text(Brand.versionLine).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            Section("Made by") {
                HStack(spacing: 14) {
                    if let logo = Brand.logo {
                        Image(nsImage: logo).resizable().scaledToFit().frame(width: 64, height: 64)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Maxx Forge Studio").font(.system(size: 16, weight: .bold))
                        Text("Aries Dynamic Island is a Maxx Forge Studio product.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Link("Visit maxxforgestudio.com", destination: Brand.website)
                Link("Get help or ask a question", destination: PatchNotes.supportURL())
                Link("Report a bug", destination: PatchNotes.reportBugURL)
                Link("Request a feature", destination: PatchNotes.requestFeatureURL)
                Link("Maxx Forge Studio on GitHub", destination: URL(string: "https://github.com/maxxforgestudio-del")!)
            }
            Section {
                EmptyView()
            } footer: {
                Text("\(Brand.copyright)\nAries, Aries Dynamic Island and the Maxx Forge Studio name and logo are property of Maxx Forge Studio. Lyrics by LRCLIB · Weather by Open-Meteo · Not affiliated with Spotify or Apple.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AccessibilityPane: View {
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false
    @AppStorage(Prefs.reduceTransparency) private var reduceTransparency = false
    @AppStorage(Prefs.largerIsland) private var largerIsland = false
    @AppStorage(Prefs.highContrast) private var highContrast = false
    @AppStorage(Prefs.announce) private var announce = true
    @AppStorage(Prefs.lyricsSize) private var lyricsSize = 42.0
    @AppStorage(Prefs.haptics) private var haptics = true

    var body: some View {
        Form {
            Section("Vision") {
                Toggle(isOn: $largerIsland) { row("Larger island", "Makes the open island and its text 12% bigger.") }
                Toggle(isOn: $highContrast) { row("Increase contrast", "Adds a bright outline around the island.") }
                Toggle(isOn: $reduceTransparency) { row("Reduce transparency", "Uses solid black instead of Aquatic glass.") }
                LabeledContent("Lyrics text size") {
                    Slider(value: $lyricsSize, in: 28...64).frame(width: 220)
                }
            }
            Section("Motion") {
                Toggle(isOn: $reduceMotion) { row("Reduce motion", "Turns off bouncing, confetti, music notes, shimmer and the ram's dancing.") }
            }
            Section("Hearing & touch") {
                Toggle(isOn: $announce) { row("Announce popups with VoiceOver", "Reads calls, songs and alerts aloud when VoiceOver is on.") }
                Toggle(isOn: $haptics) { row("Haptic feedback", "Gentle taps on the trackpad when the island opens and you switch tabs.") }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Aries also follows your Mac's own Reduce Motion, Reduce Transparency and Increase Contrast settings in System Settings › Accessibility › Display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PermissionsPane: View {
    @ObservedObject var center: PermissionCenter
    var body: some View {
        Form {
            if !center.missing.isEmpty {
                Section {
                    Label("\(center.missing.count) permission\(center.missing.count == 1 ? "" : "s") still needed for features you've turned on.",
                          systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Button("Allow All") { center.requestNeeded(); center.missing.forEach { center.request($0) } }
                }
            }
            PrivacySecuritySection()
            Section("Permissions") {
                ForEach(PermissionCenter.Kind.allCases) { k in PermissionRow(kind: k, center: center) }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Aries asks for each permission only when a feature you turned on needs it. Nothing leaves your Mac except the requests listed in the README (Spotify, lyrics, artwork, weather, updates).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { center.refresh() }
    }
}

private struct DesktopWidgetsPane: View {
    @AppStorage(Prefs.desktopWidgets) private var desktop = false
    @AppStorage(Prefs.lockScreenWidgets) private var lock = true
    @ViewState private var tick = 0

    var body: some View {
        let model = AppDelegate.shared.model!
        Form {
            Section {
                Toggle(isOn: $desktop) { Label("Show widgets on the desktop", systemImage: "rectangle.3.group") }
                    .onChange(of: desktop) { _, _ in DesktopWidgets.shared.refresh(model: model) }
                if desktop {
                    ForEach(AriesWidget.allCases) { w in
                        Toggle(isOn: Binding(get: { _ = tick; return w.isOn }, set: { v in
                            UserDefaults.standard.set(v, forKey: w.prefKey); tick += 1
                            DesktopWidgets.shared.refresh(model: model)
                        })) { Label(w.title, systemImage: w.icon) }
                    }
                    Button("Reset Widget Positions") { DesktopWidgets.shared.resetPositions(model: model) }
                }
            } header: {
                Text("Desktop")
            } footer: {
                Text("Widgets sit on your wallpaper, below your windows. Drag one to move it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $lock) { Label("Now Playing & widgets on the Lock Screen (beta)", systemImage: "lock.fill") }
                if !LockScreenWidgets.shared.isSupported {
                    Text("Not available on this version of macOS.").font(.caption).foregroundStyle(.orange)
                }
                Button("Preview: Lock Screen Now") {
                    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["displaysleepnow"]; try? p.run()
                }
            } header: {
                Text("Lock Screen")
            } footer: {
                Text("While your Mac is locked, see what's playing (with play, pause and skip), the weather, your next event and battery, like iPhone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Settings look & motion

extension AnyTransition {
    /// Pages float up into place, sharpening from a soft blur.
    static var settingsIn: AnyTransition {
        .modifier(active: SettleIn(progress: 0), identity: SettleIn(progress: 1))
    }
}

private struct SettleIn: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: 18 * (1 - progress))
            .scaleEffect(0.985 + 0.015 * progress, anchor: .top)
            .blur(radius: 6 * (1 - progress))
    }
}

/// Slowly drifting, softly glowing color behind each page, tinted by the page's own color.
private struct SettingsAurora: View {
    let color: Color
    var body: some View {
        if A11y.reduceMotion {
            RadialGradient(colors: [color.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 520)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    ZStack {
                        blob(color, 0.30, size: 460)
                            .position(x: w * (0.78 + 0.08 * sin(t / 7)), y: h * (0.12 + 0.06 * cos(t / 9)))
                        blob(Color(red: 0.32, green: 0.86, blue: 1.0), 0.16, size: 380)
                            .position(x: w * (0.25 + 0.10 * cos(t / 11)), y: h * (0.05 + 0.05 * sin(t / 8)))
                        blob(Color(red: 0.55, green: 0.35, blue: 1.0), 0.12, size: 520)
                            .position(x: w * (0.55 + 0.12 * sin(t / 13)), y: h * (0.95 + 0.04 * cos(t / 10)))
                    }
                    .blur(radius: 70)
                }
            }
            .animation(.easeInOut(duration: 0.8), value: color)
            .allowsHitTesting(false)
        }
    }
    private func blob(_ c: Color, _ a: Double, size: CGFloat) -> some View {
        Circle().fill(c.opacity(a)).frame(width: size, height: size)
    }
}

/// The big card at the top of each page: glowing icon, title, a one-line description and a light sweep.
private struct SettingsHero: View {
    let pane: Pane
    @ViewState private var appeared = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(pane.accent.opacity(0.45)).frame(width: 64, height: 64).blur(radius: 18)
                Image(systemName: pane.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pane.color.gradient))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
                    .shadow(color: pane.accent.opacity(0.5), radius: 10, y: 4)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .rotationEffect(.degrees(appeared ? 0 : -12))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("SETTINGS")
                    .font(.system(size: 10, weight: .heavy)).tracking(2)
                    .foregroundStyle(pane.accent.opacity(0.9))
                Text(pane.title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(pane.blurb).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [pane.accent.opacity(0.22), pane.accent.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        )
        .overlay(Sheen(run: appeared).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .onAppear {
            guard !A11y.reduceMotion else { appeared = true; return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.05)) { appeared = true }
        }
    }
}

/// One soft light sweep across the hero card when a page opens.
private struct Sheen: View {
    let run: Bool
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 140)
                .rotationEffect(.degrees(18))
                .offset(x: run ? geo.size.width + 160 : -200)
                .animation(A11y.reduceMotion ? nil : .easeInOut(duration: 1.1).delay(0.15), value: run)
        }
        .allowsHitTesting(false)
    }
}

/// A sidebar row with a hover glow; the selection highlight slides smoothly between rows.
private struct SidebarRow: View {
    let p: Pane
    let selected: Bool
    let unread: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: p.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.color.gradient))
                    .shadow(color: p.accent.opacity(selected || hover ? 0.55 : 0), radius: 6)
                    .scaleEffect(hover && !selected ? 1.08 : 1)
                Text(p.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
                if unread {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                        .shadow(color: .blue, radius: 4)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [p.accent.opacity(0.28), p.accent.opacity(0.10)],
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(p.accent.opacity(0.35), lineWidth: 0.8))
                        .matchedGeometryEffect(id: "selection", in: ns)
                } else if hover {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.primary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}
