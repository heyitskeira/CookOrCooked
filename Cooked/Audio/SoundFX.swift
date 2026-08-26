//
//  SoundFX.swift
//  Cooked
//
//  Short one-shot sounds: taps, an action finishing, the serve landing.
//
//  Separate from `Music` because players think of them separately — plenty of
//  people turn the music off and keep the sound effects, and almost nobody
//  wants the reverse silently forced on them. Two switches, two settings.
//
//  `Music` still owns the audio session; this only ever asks for a player.
//
//  ⚠️ No sound files exist yet. Every effect below is wired and silent until a
//  file with the matching name lands in `Cooked/Audio/` — dropping one in is
//  the only step. Nothing here needs editing unless you want a new effect,
//  which is one case in the enum.
//

import AVFoundation
import Combine

@MainActor
final class SoundFX: ObservableObject {

    static let shared = SoundFX()

    // MARK: The effects

    /// The raw value is the filename in `Cooked/Audio/`, without the extension.
    ///
    /// Add a case, drop in the file, call `SoundFX.shared.play(.yourEffect)`.
    /// A missing file is not an error — it just doesn't make a sound — so these
    /// can be wired into the game before anyone has recorded them.
    enum Effect: String, CaseIterable {
        /// Any button on any menu.
        case tap            = "fx-tap"
        /// Taking something off the storage shelf.
        case pickUp         = "fx-pickup"
        /// Dropping an ingredient into a station.
        case drop           = "fx-drop"
        /// A station's progress bar filling.
        case actionComplete = "fx-action-complete"
        /// Something rotten going in the bin.
        case trash          = "fx-trash"
        /// The cake going out.
        case serve          = "fx-serve"
        case win            = "fx-win"
        case lose           = "fx-lose"
    }

    /// Which file extensions to look for, in order. Short sounds are usually
    /// .wav (no encoder delay, instant to decode); .m4a and .mp3 work too.
    private static let extensions = ["wav", "m4a", "mp3"]

    // MARK: Settings

    /// Persisted, and independent of the music setting.
    @Published var isMuted: Bool {
        didSet { UserDefaults.standard.set(isMuted, forKey: Self.muteKey) }
    }

    /// Where the settings slider sits, 0...1. Scales `fullVolume` rather than
    /// replacing it, so 1.0 stays the level the mix was tuned at.
    ///
    /// Applied to every loaded player as it changes — unlike music there is no
    /// single "current" player, and an effect that was cached before the player
    /// moved the slider would otherwise keep its old level for the whole
    /// session.
    @Published var volume: Double {
        didSet {
            let clamped = min(max(volume, 0), 1)
            if clamped != volume { volume = clamped; return }
            guard oldValue != volume else { return }
            UserDefaults.standard.set(volume, forKey: Self.volumeKey)
            players.values.forEach { $0.volume = playbackVolume }
        }
    }

    private static let muteKey = "sfx.muted"
    private static let volumeKey = "sfx.volume"

    /// Effects sit on top of the music, so they're louder than it is.
    private let fullVolume: Float = 0.85

    private var playbackVolume: Float { fullVolume * Float(volume) }

    private var players: [Effect: AVAudioPlayer] = [:]
    /// Effects whose file is missing. Checked once, then never looked up again
    /// — `Bundle.url(forResource:)` misses are not cached by the system and
    /// these get asked for in the middle of gameplay.
    private var missing: Set<Effect> = []

    private init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.muteKey)
        // Absent means full, not zero — see the same note in `Music`.
        volume = UserDefaults.standard.object(forKey: Self.volumeKey) as? Double ?? 1.0
    }

    // MARK: Playing

    func play(_ effect: Effect) {
        guard !isMuted else { return }

        // Never while the blow-to-melt station is listening: a sound effect out
        // of the speaker is indistinguishable from someone blowing, and would
        // melt the butter for free.
        guard !Music.shared.isMicrophoneOpen else { return }

        guard let player = player(for: effect) else { return }

        // Restart rather than ignore. Two taps in quick succession should sound
        // like two taps, and for effects this short, cutting the first one off
        // is what a player expects.
        player.currentTime = 0
        player.play()
    }

    /// Load every effect that has a file, ahead of time.
    ///
    /// Optional — `play` loads on demand — but calling this once when the
    /// kitchen opens keeps the first chop from hitching while a file is read
    /// off disk mid-frame.
    func preload() {
        for effect in Effect.allCases { _ = player(for: effect) }
    }

    private func player(for effect: Effect) -> AVAudioPlayer? {
        if let existing = players[effect] { return existing }
        guard !missing.contains(effect) else { return nil }

        let url = Self.extensions.lazy
            .compactMap { Bundle.main.url(forResource: effect.rawValue, withExtension: $0) }
            .first

        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else {
            missing.insert(effect)
            return nil
        }

        player.volume = playbackVolume
        player.prepareToPlay()
        players[effect] = player
        return player
    }
}
