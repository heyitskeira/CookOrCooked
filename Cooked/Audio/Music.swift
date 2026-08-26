//
//  Music.swift
//  Cooked
//
//  The background music, and the single owner of this app's audio session.
//
//  Two loops. The menu track runs from launch all the way through the recipe
//  book; the kitchen track takes over the moment the head chef hits START and
//  runs to the results card. The changeover is the sound of the match
//  beginning, which is why the book is deliberately on the *menu* side of the
//  line — the music changing is the reward for pressing START.
//
//  Why one owner rather than an AVAudioPlayer wherever it's convenient:
//  `AVAudioSession` is a single process-wide object, and the blow-to-melt
//  station needs the microphone. It used to grab `.playAndRecord` and then
//  deactivate the session on its way out, which would have silenced the music
//  for the rest of the match. Handing the session to one place means the
//  hand-off to the microphone is a conversation between two methods here
//  instead of a fight between two files.
//
//  ⚠️ The tracks are 256 kbps MP3. Every MP3 encoder pads the start of the file
//  with a few milliseconds of silence, so a plain loop has an audible tick at
//  the seam. `AVAudioPlayer` loops gaplessly enough for a party game, but if
//  the seam bothers anyone on device, re-export as .m4a (AAC) and change the
//  filenames below — nothing else needs to move.
//

import AVFoundation
import Combine

@MainActor
final class Music: ObservableObject {

    static let shared = Music()

    // MARK: The two loops

    enum Track: CaseIterable {
        case menu
        case kitchen

        /// Filename in `Cooked/Audio/`, without the extension.
        var fileName: String {
            switch self {
            case .menu:    return "MainMenuAndLobby"
            case .kitchen: return "in-gameonly"
            }
        }
    }

    // MARK: Tuning

    /// Playing volume at the top of the slider. Not 1.0 — this is background
    /// music for a game where the players need to hear each other count down to
    /// a serve. The settings slider scales this rather than replacing it, so
    /// "100%" stays the level the mix was tuned at.
    private let fullVolume: Float = 0.55

    /// Volume while the microphone is open. Not zero: total silence mid-match
    /// reads as the game having crashed.
    private let duckedVolume: Float = 0.06

    /// Long enough to sound deliberate, short enough that START still feels
    /// like a starting gun.
    private let crossfade: TimeInterval = 1.0

    /// The mic reacts to sound in the room, so the duck has to be quick.
    private let duckFade: TimeInterval = 0.25

    // MARK: State

    /// Persisted so a player who turns the music off doesn't have to do it
    /// again every launch.
    @Published var isMuted: Bool {
        didSet {
            guard oldValue != isMuted else { return }
            UserDefaults.standard.set(isMuted, forKey: Self.muteKey)
            applyMute()
        }
    }

    /// Where the settings slider sits, 0...1. Scales `fullVolume`; it does not
    /// replace it, so 1.0 is the tuned mix level and not a raw 100%.
    ///
    /// Mute is kept as its own flag rather than being folded into "volume == 0"
    /// because they answer different questions. Sliding to zero and coming back
    /// should return you to where you were, and something that mutes the app
    /// from outside this screen must not destroy the player's chosen level.
    @Published var volume: Double {
        didSet {
            let clamped = min(max(volume, 0), 1)
            if clamped != volume { volume = clamped; return }
            guard oldValue != volume else { return }
            UserDefaults.standard.set(volume, forKey: Self.volumeKey)
            applyVolume()
        }
    }

    private static let muteKey = "music.muted"
    private static let volumeKey = "music.volume"

    private var players: [Track: AVAudioPlayer] = [:]
    private(set) var current: Track?

    /// True while the blow-to-melt station has the microphone.
    private var isDucked = false

    /// Whether the microphone is currently open. `SoundFX` reads this so it
    /// doesn't play a noise the melt station would mistake for someone blowing.
    var isMicrophoneOpen: Bool { isDucked }


    private init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.muteKey)
        // `double(forKey:)` returns 0 for a key that was never written, which
        // would launch a first-time player into silence. Absent means full.
        volume = UserDefaults.standard.object(forKey: Self.volumeKey) as? Double ?? 1.0
    }

    // MARK: Session

    /// Called once at launch, before anything plays.
    ///
    /// `.playback` rather than `.ambient` on purpose: this is a game you sit
    /// down to play with people in the room, and half the group having their
    /// ring switch on shouldn't mean half the group hears nothing.
    func start() {
        observeInterruptions()
        play(.menu)
    }

    /// Take the audio session. Deliberately NOT called at launch: `.playback`
    /// is non-mixing, so activating it stops whatever the player had going in
    /// Spotify — and doing that to someone who has our music muted is rude.
    /// Called only when something is actually about to make a sound.
    private func configureForPlayback() {
        guard !isMuted else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: Playing

    /// Bring this track up and take the other one down.
    ///
    /// Safe to call repeatedly with the track that's already playing — the
    /// views drive this from `onChange`, which fires more often than the music
    /// should restart.
    func play(_ track: Track) {
        // Asking for the track that's already playing is a no-op — but only if
        // it really is playing. After a phone call or a spell in the background
        // the player is stopped while `current` still points at it, and a plain
        // "same track, do nothing" guard would mean the music never came back
        // for the rest of the launch.
        let sameTrack = current == track
        if sameTrack, isMuted || currentPlayer?.isPlaying == true { return }

        let outgoing = sameTrack ? nil : current
        current = track

        guard !isMuted else {
            // Muted: remember where we are, make no sound. Unmuting picks the
            // right track up from here.
            outgoing.map { players[$0]?.stop() }
            return
        }

        configureForPlayback()

        if let incoming = player(for: track) {
            incoming.volume = 0
            incoming.play()
            incoming.setVolume(targetVolume, fadeDuration: crossfade)
        }

        if let outgoing, let leaving = players[outgoing] {
            leaving.setVolume(0, fadeDuration: crossfade)
            // Stop only after the fade has actually finished, or the track
            // vanishes instead of fading.
            let fade = crossfade
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(fade))
                // Unless it has been brought back in the meantime.
                if self.current != outgoing { leaving.stop() }
            }
        }
    }

    /// Silence everything — the app is going away, not just changing screens.
    func stop() {
        players.values.forEach { $0.stop() }
        current = nil
    }

    // MARK: The microphone hand-off

    /// The blow-to-melt station is about to start listening.
    ///
    /// Ducks the music so the speaker can't blow into the app's own microphone
    /// and melt the butter without anyone breathing on it.
    func willUseMicrophone() {
        isDucked = true
        // Set directly rather than fading. The category change and the recorder
        // start on the next two lines of the caller, and a 0.25s ramp would
        // leave the music loud enough to trip its own meter and push the flame
        // down for free.
        currentPlayer?.volume = targetVolume
    }

    /// The station has finished with the microphone.
    ///
    /// This replaces the `setActive(false)` that used to live in
    /// `BlowmeltingScreen.cleanUp()`. Deactivating the shared session there
    /// stopped the music for the rest of the match, and putting the category
    /// back is the only way to get the speaker (rather than the earpiece) again
    /// after `.measurement` mode.
    func didFinishWithMicrophone() {
        // Idempotent on purpose. The station's `cleanUp()` runs twice on a
        // normal finish (once from `finish()`, once from `closeStation()`), and
        // the scene calls it again defensively on teardown.
        guard isDucked else { return }
        isDucked = false

        configureForPlayback()

        // Nothing is latched about what was playing before: the state is
        // re-derived. A flag captured at duck time goes stale the moment the
        // player opens settings and mutes mid-station, and a stale flag here
        // means the music never comes back off 6%.
        guard !isMuted, let player = currentPlayer else { return }
        if !player.isPlaying { player.play() }
        player.setVolume(targetVolume, fadeDuration: duckFade)
    }

    // MARK: Interruptions

    /// Phone calls, Siri, the app being backgrounded. iOS stops playback and
    /// tells us; without this the music simply never returns.
    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { note in
            Task { @MainActor in Music.shared.handleInterruption(note) }
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        // `.began` needs nothing — the system has already stopped us.
        if type == .ended { resume() }
    }

    /// Start the current track again if it should be playing and isn't.
    ///
    /// Safe to call whenever — coming back from the background, an interruption
    /// ending, a screen appearing. Doing nothing is the common case.
    func resume() {
        guard !isMuted, let track = current, currentPlayer?.isPlaying != true else { return }
        configureForPlayback()
        guard let player = player(for: track) else { return }
        player.play()
        player.setVolume(targetVolume, fadeDuration: 0.3)
    }

    // MARK: Plumbing

    private var targetVolume: Float {
        if isMuted { return 0 }
        return (isDucked ? duckedVolume : fullVolume) * Float(volume)
    }

    private var currentPlayer: AVAudioPlayer? {
        current.flatMap { players[$0] }
    }

    /// Live-update the level while the settings slider is being dragged.
    ///
    /// Set directly, no fade: a ramp on every value change turns a drag into a
    /// queue of overlapping fades and the volume lags the thumb.
    ///
    /// The player keeps running at zero rather than stopping. Stopping and
    /// restarting on each end of the slider would restart the loop from the
    /// top, so dragging past zero and back would jump the music.
    private func applyVolume() {
        guard !isMuted else { return }
        currentPlayer?.volume = targetVolume
    }

    private func applyMute() {
        guard let track = current else { return }

        if isMuted {
            // Every player, not just the current one — an outgoing crossfade
            // would otherwise keep sounding for up to a second after the
            // player hit the switch.
            players.values.forEach { $0.stop() }
        } else {
            // Not while the microphone has the session: `setCategory(.playback)`
            // here would kill the recorder and leave the melt station
            // unwinnable. The un-duck will bring the music back on its way out.
            if !isDucked { configureForPlayback() }
            if let player = self.player(for: track) {
                player.volume = 0
                player.play()
                player.setVolume(targetVolume, fadeDuration: 0.4)
            }
        }
    }

    /// Built once per track and kept. Loading a several-megabyte MP3 on the
    /// main thread mid-match would be a visible hitch, and there are only two.
    private func player(for track: Track) -> AVAudioPlayer? {
        if let existing = players[track] { return existing }

        guard let url = Bundle.main.url(forResource: track.fileName, withExtension: "mp3"),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            // No file, no music, no crash. The game is entirely playable in
            // silence, so a missing track must never be fatal — and this is
            // what makes the whole thing work before the art is final.
            #if DEBUG
            print("⚠️ Music: couldn't load \(track.fileName).mp3 — is it in Cooked/Audio/?")
            #endif
            return nil
        }

        player.numberOfLoops = -1        // forever
        player.volume = 0
        player.prepareToPlay()
        players[track] = player
        return player
    }
}
