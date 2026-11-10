import AppKit
import MediaPlayer

/// Mirrors playback from your *phone* (Spotify Connect) into macOS's own Now Playing.
/// That makes it appear on the Mac's lock screen, in Control Center, and lets the
/// keyboard's play/pause/next keys control your phone.
/// (Spotify and Music on this Mac already publish their own Now Playing info.)
final class NowPlayingBridge {
    static let shared = NowPlayingBridge()
    private var active = false
    private var commandsInstalled = false
    private var lastArtworkID: ObjectIdentifier?
    private var artwork: MPMediaItemArtwork?

    func update(_ m: MusicController) {
        let want = Prefs.bool(Prefs.lockScreenMirror) && m.source == .spotifyRemote && m.track != nil
        let center = MPNowPlayingInfoCenter.default()
        guard want, let t = m.track else {
            if active {
                center.nowPlayingInfo = nil
                center.playbackState = .stopped
                setCommands(enabled: false)
                active = false
            }
            return
        }
        installCommands(m)
        setCommands(enabled: true)
        active = true

        if let img = m.artwork, ObjectIdentifier(img) != lastArtworkID {
            lastArtworkID = ObjectIdentifier(img)
            artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPMediaItemPropertyPlaybackDuration: t.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: m.position,
            MPNowPlayingInfoPropertyPlaybackRate: m.isPlaying ? 1.0 : 0.0,
        ]
        if let a = artwork { info[MPMediaItemPropertyArtwork] = a }
        center.nowPlayingInfo = info
        center.playbackState = m.isPlaying ? .playing : .paused
    }

    private func setCommands(enabled: Bool) {
        let c = MPRemoteCommandCenter.shared()
        for cmd in [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand, c.nextTrackCommand,
                    c.previousTrackCommand, c.changePlaybackPositionCommand] as [MPRemoteCommand] {
            cmd.isEnabled = enabled
        }
    }

    private func installCommands(_ m: MusicController) {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { _ in if !m.isPlaying { m.playPause() }; return .success }
        c.pauseCommand.addTarget { _ in if m.isPlaying { m.playPause() }; return .success }
        c.togglePlayPauseCommand.addTarget { _ in m.playPause(); return .success }
        c.nextTrackCommand.addTarget { _ in m.next(); return .success }
        c.previousTrackCommand.addTarget { _ in m.previous(); return .success }
        c.changePlaybackPositionCommand.addTarget { e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            m.seek(to: e.positionTime)
            return .success
        }
    }
}
