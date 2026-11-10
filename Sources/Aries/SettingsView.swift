import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var music: MusicController
    @ObservedObject var spotify: SpotifyWeb

    @AppStorage(Prefs.expandOnHover) private var expandOnHover = true
    @AppStorage(Prefs.hoverDelay) private var hoverDelay = 0.12
    @AppStorage(Prefs.haptics) private var haptics = true
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true

    @AppStorage(Prefs.preferredSource) private var preferredSource = "auto"
    @AppStorage(Prefs.showNotes) private var showNotes = true
    @AppStorage(Prefs.notesIntensity) private var notesIntensity = 0.35
    @AppStorage(Prefs.showVisualizer) private var showVisualizer = true
    @AppStorage(Prefs.showLyricLine) private var showLyricLine = true
    @AppStorage(Prefs.artworkAccent) private var artworkAccent = true
    @AppStorage(Prefs.pausedLinger) private var pausedLinger = 20.0
    @AppStorage(Prefs.lyricsSize) private var lyricsSize = 42.0

    @AppStorage(Prefs.showMic) private var showMic = true
    @AppStorage(Prefs.showCamera) private var showCamera = true
    @AppStorage(Prefs.showBattery) private var showBattery = true
    @AppStorage(Prefs.chargingToast) private var chargingToast = true

    @AppStorage(Prefs.showBuddy) private var showBuddy = true
    @AppStorage(Prefs.showShelf) private var showShelf = true
    @AppStorage(Prefs.showTimer) private var showTimer = true
    @AppStorage(Prefs.timerSound) private var timerSound = true
    @AppStorage(Prefs.showCalendar) private var showCalendar = true
    @AppStorage(Prefs.meetingAlerts) private var meetingAlerts = true
    @AppStorage(Prefs.volumeHUD) private var volumeHUD = true
    @AppStorage(Prefs.deviceToasts) private var deviceToasts = true
    @AppStorage(Prefs.unlockAnimation) private var unlockAnimation = true
    @AppStorage(Prefs.hoverBounce) private var hoverBounce = true
    @AppStorage(Prefs.musicGlow) private var musicGlow = true

    @AppStorage(Prefs.showNotesTab) private var showNotesTab = true
    @AppStorage(Prefs.showClipboard) private var showClipboard = false
    @AppStorage(Prefs.showMirror) private var showMirror = true
    @AppStorage(Prefs.showWeather) private var showWeather = true
    @AppStorage(Prefs.fahrenheit) private var fahrenheit = true
    @AppStorage(Prefs.announceSongs) private var announceSongs = true
    @AppStorage(Prefs.lockScreenMirror) private var lockScreenMirror = true
    @AppStorage(Prefs.callActivity) private var callActivity = true
    @AppStorage(Prefs.callBanner) private var callBanner = true
    @AppStorage(Prefs.hotkeys) private var hotkeys = true
    @AppStorage(Prefs.hideInFullscreen) private var hideInFullscreen = false
    @ViewState private var cityDraft = Prefs.string(Prefs.weatherCity)

    @AppStorage(Prefs.usePhoneSpotify) private var usePhoneSpotify = true
    @AppStorage(Prefs.spotifyClientID) private var clientID = ""

    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var loginError: String?

    var body: some View {
        Form {
            Section { header }

            Section("Island") {
                Toggle("Expand when hovering", isOn: $expandOnHover)
                if expandOnHover {
                    LabeledContent("Hover delay") {
                        Slider(value: $hoverDelay, in: 0...0.6) { EmptyView() }
                            minimumValueLabel: { Text("Instant").font(.caption) }
                            maximumValueLabel: { Text("Relaxed").font(.caption) }
                            .frame(width: 240)
                    }
                }
                Toggle("Bouncy hover", isOn: $hoverBounce)
                Toggle("Haptic feedback on trackpad", isOn: $haptics)
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                Toggle("Hide during full-screen apps", isOn: $hideInFullscreen)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Picker("Preferred player", selection: $preferredSource) {
                    Text("Automatic").tag("auto")
                    Text("Spotify").tag("spotify")
                    Text("Apple Music").tag("music")
                }
                Toggle("Music notes effect", isOn: $showNotes)
                if showNotes {
                    LabeledContent("Notes intensity") {
                        Slider(value: $notesIntensity, in: 0...1) { EmptyView() }
                            minimumValueLabel: { Image(systemName: "music.note").font(.caption) }
                            maximumValueLabel: { Image(systemName: "music.note.list").font(.caption) }
                            .frame(width: 240)
                    }
                }
                Toggle("Live visualizer", isOn: $showVisualizer)
                Toggle("Soft glow while playing", isOn: $musicGlow)
                Toggle("Tint with album colors", isOn: $artworkAccent)
                Toggle("Show current lyric in island", isOn: $showLyricLine)
                Toggle("Announce new songs", isOn: $announceSongs)
                Toggle("Show phone playback on Lock Screen & Control Center", isOn: $lockScreenMirror)
                LabeledContent("Keep player after pausing") {
                    Picker("", selection: $pausedLinger) {
                        Text("5 sec").tag(5.0)
                        Text("20 sec").tag(20.0)
                        Text("1 min").tag(60.0)
                        Text("5 min").tag(300.0)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            } header: {
                Text("Music")
            }

            Section("Lyrics") {
                LabeledContent("Text size") {
                    Slider(value: $lyricsSize, in: 28...64) { EmptyView() }
                        minimumValueLabel: { Text("A").font(.system(size: 11, weight: .bold)) }
                        maximumValueLabel: { Text("A").font(.system(size: 17, weight: .bold)) }
                        .frame(width: 240)
                }
                Button("Open Full-Screen Player") { AppDelegate.shared.openLyrics() }
                Text("Synced lyrics come from LRCLIB, a free open lyrics library. In the full-screen player: click a line to jump to it, scroll to look around, space to play/pause, ← → to skip, ↑ ↓ for volume, esc to close.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show music playing on my phone", isOn: $usePhoneSpotify)
                if usePhoneSpotify {
                    phoneSetup
                }
            } header: {
                Text("iPhone · Spotify Connect")
            } footer: {
                Text("Your phone's Spotify reports to Spotify's servers, and Aries reads it from there. Apple Music on iPhone can't be read from a Mac. Pause, skip and seek for phone playback need Spotify Premium.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $showBuddy) { Label("Aries buddy on Home", systemImage: "face.smiling") }
                Toggle(isOn: $showCalendar) { Label("Next calendar event", systemImage: "calendar") }
                    .onChange(of: showCalendar) { _, _ in AppDelegate.shared.model.calendar.refresh() }
                if showCalendar {
                    Toggle(isOn: $meetingAlerts) { Label("Heads-up 5 min before events", systemImage: "bell.badge") }
                    if !AppDelegate.shared.model.calendar.authorized {
                        Button("Allow Calendar Access") { AppDelegate.shared.model.calendar.requestAccess() }
                    }
                }
                Toggle(isOn: $showWeather) { Label("Weather on Home", systemImage: "cloud.sun") }
                if showWeather {
                    HStack {
                        TextField("City", text: $cityDraft).textFieldStyle(.roundedBorder)
                            .onSubmit { AppDelegate.shared.model.weather.setCity(cityDraft) }
                        Button("Set") { AppDelegate.shared.model.weather.setCity(cityDraft) }
                        Toggle("°F", isOn: $fahrenheit).toggleStyle(.checkbox)
                            .onChange(of: fahrenheit) { _, _ in AppDelegate.shared.model.weather.refresh() }
                    }
                }
                Toggle(isOn: $showNotesTab) { Label("Notes & to-dos", systemImage: "note.text") }
                Toggle(isOn: $showShelf) { Label("File shelf (drop files on the notch)", systemImage: "tray.full") }
                Toggle(isOn: $showTimer) { Label("Timer", systemImage: "timer") }
                if showTimer {
                    Toggle(isOn: $timerSound) { Label("Chime when done", systemImage: "speaker.wave.2") }
                }
                Toggle(isOn: $showMirror) { Label("Mirror (camera check)", systemImage: "person.crop.square") }
                Toggle(isOn: $showClipboard) { Label("Clipboard history", systemImage: "doc.on.clipboard") }
            } header: {
                Text("Widgets")
            } footer: {
                Text("Hover the island and use the tabs at the top-left. Clipboard history stays in memory only and skips password managers. Tap the little ram to boop it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Popups") {
                Toggle(isOn: $volumeHUD) { Label("Volume", systemImage: "speaker.wave.3.fill") }
                Toggle(isOn: $deviceToasts) { Label("AirPods & audio devices connecting", systemImage: "airpodspro") }
                Toggle(isOn: $unlockAnimation) { Label("Unlock greeting", systemImage: "lock.open.fill") }
            }

            Section {
                Toggle(isOn: $callActivity) { Label("Show calls in the island", systemImage: "phone.fill") }
                Toggle(isOn: $callBanner) { Label("Answer iPhone calls from the island", systemImage: "phone.arrow.down.left") }
                if callBanner && !AppDelegate.shared.model.calls.axTrusted {
                    Button("Allow Accessibility…") { AppDelegate.shared.model.calls.requestAccessibility() }
                }
            } header: {
                Text("Calls")
            } footer: {
                Text("Aries notices FaceTime, iPhone (Continuity), Zoom, Teams, Discord, Slack, Webex and WhatsApp calls by which app is using your mic, and shows a timer with a mute button. Answering needs Accessibility so Aries can press the call banner's buttons.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Keyboard Shortcuts") {
                Toggle("Enable shortcuts", isOn: $hotkeys)
                if hotkeys {
                    ForEach(Hotkeys.all, id: \.id) { s in
                        LabeledContent(s.title) {
                            Text(s.glyph).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Indicators") {
                Toggle(isOn: $showMic) { Label("Microphone in use", systemImage: "mic.fill") }
                Toggle(isOn: $showCamera) { Label("Camera in use", systemImage: "video.fill") }
                Toggle(isOn: $showBattery) { Label("Battery level & low-battery alerts", systemImage: "battery.75percent") }
                Toggle(isOn: $chargingToast) { Label("Charging animation", systemImage: "bolt.fill") }
            }

            Section {
                HStack {
                    Text("Aries Dynamic Island \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Welcome Tour") { AppDelegate.shared.openWelcome() }
                    Button("Quit Aries") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 600)
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [music.accent.opacity(0.9), music.accent.opacity(0.35)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Capsule().fill(.black).frame(width: 44, height: 16).offset(y: -14)
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: 8)
            }
            .frame(width: 64, height: 64)
            .shadow(color: music.accent.opacity(0.4), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text("Aries Dynamic Island").font(.system(size: 24, weight: .bold))
                Text(music.track.map { "Now playing: \($0.title) — \($0.artist)" } ?? "Your notch, alive.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var phoneSetup: some View {
        if spotify.isConnected {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(spotify.accountName.map { "Connected as \($0)" } ?? spotify.status)
                Spacer()
                Button("Disconnect", role: .destructive) { spotify.disconnect() }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("One-time setup (about 2 minutes):").font(.callout.weight(.semibold))
                step(1, "Open the Spotify Developer Dashboard and click **Create app**.") {
                    Link("Open Dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                }
                step(2, "Use any name. Add this as the **Redirect URI**, then tick **Web API**:") {
                    HStack {
                        Text(SpotifyWeb.redirectURI)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SpotifyWeb.redirectURI, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy")
                    }
                }
                step(3, "Copy the app's **Client ID** and paste it here:") {
                    TextField("", text: $clientID, prompt: Text("Client ID"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                HStack {
                    Text(spotify.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Connect Spotify") { spotify.connect() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.11, green: 0.73, blue: 0.33))
                        .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription). Move Aries Dynamic Island to Applications and try again."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
