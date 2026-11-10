import Foundation

enum Prefs {
    static let expandOnHover = "expandOnHover"
    static let hoverDelay = "hoverDelay"
    static let haptics = "haptics"
    static let showMenuBarIcon = "showMenuBarIcon"

    static let preferredSource = "preferredSource"      // auto | spotify | music
    static let showNotes = "showNotes"
    static let notesIntensity = "notesIntensity"        // 0...1
    static let showVisualizer = "showVisualizer"
    static let showLyricLine = "showLyricLine"
    static let artworkAccent = "artworkAccent"
    static let pausedLinger = "pausedLinger"            // seconds the compact player stays after pause

    static let showMic = "showMic"
    static let showCamera = "showCamera"
    static let showBattery = "showBattery"
    static let chargingToast = "chargingToast"

    static let usePhoneSpotify = "usePhoneSpotify"
    static let spotifyClientID = "spotifyClientID"

    static let lyricsSize = "lyricsSize"                // points

    static let showBuddy = "showBuddy"
    static let showShelf = "showShelf"
    static let showTimer = "showTimer"
    static let timerSound = "timerSound"
    static let showCalendar = "showCalendar"
    static let meetingAlerts = "meetingAlerts"
    static let volumeHUD = "volumeHUD"
    static let deviceToasts = "deviceToasts"
    static let unlockAnimation = "unlockAnimation"
    static let hoverBounce = "hoverBounce"
    static let musicGlow = "musicGlow"
    static let lastTimerMinutes = "lastTimerMinutes"

    static let showNotesTab = "showNotesTab"
    static let showClipboard = "showClipboard"
    static let showMirror = "showMirror"
    static let showWeather = "showWeather"
    static let weatherCity = "weatherCity"
    static let weatherLat = "weatherLat"
    static let weatherLon = "weatherLon"
    static let fahrenheit = "fahrenheit"
    static let announceSongs = "announceSongs"
    static let lockScreenMirror = "lockScreenMirror"
    static let callActivity = "callActivity"
    static let callBanner = "callBanner"
    static let hotkeys = "hotkeys"
    static let timerPausesMusic = "timerPausesMusic"
    static let hideInFullscreen = "hideInFullscreen"
    static let onboardingVersion = "onboardingVersion"
    static let didOnboard = "didOnboard"

    static func register() {
        UserDefaults.standard.register(defaults: [
            expandOnHover: true,
            hoverDelay: 0.12,
            haptics: true,
            showMenuBarIcon: true,
            preferredSource: "auto",
            showNotes: true,
            notesIntensity: 0.35,
            showVisualizer: true,
            showLyricLine: true,
            artworkAccent: true,
            pausedLinger: 20.0,
            showMic: true,
            showCamera: true,
            showBattery: true,
            chargingToast: true,
            usePhoneSpotify: true,
            lyricsSize: 42.0,
            showBuddy: true,
            showShelf: true,
            showTimer: true,
            timerSound: true,
            showCalendar: true,
            meetingAlerts: true,
            volumeHUD: true,
            deviceToasts: true,
            unlockAnimation: true,
            hoverBounce: true,
            musicGlow: true,
            lastTimerMinutes: 10,
            showNotesTab: true,
            showClipboard: false,
            showMirror: true,
            showWeather: true,
            fahrenheit: Locale.current.measurementSystem == .us,
            announceSongs: true,
            lockScreenMirror: true,
            callActivity: true,
            callBanner: true,
            hotkeys: true,
            timerPausesMusic: false,
            hideInFullscreen: false,
        ])
    }

    static func bool(_ k: String) -> Bool { UserDefaults.standard.bool(forKey: k) }
    static func double(_ k: String) -> Double { UserDefaults.standard.double(forKey: k) }
    static func string(_ k: String) -> String { UserDefaults.standard.string(forKey: k) ?? "" }
}
