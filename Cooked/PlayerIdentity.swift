//
//  PlayerIdentity.swift
//  Cooked
//
//  Stable per-device identity, and the room code that gates joining.
//
//  The identity is the thing that makes rejoining work. A dropped player is
//  recognised by `id` — which survives app relaunch — and never by a network
//  connection or endpoint, both of which are thrown away on disconnect.
//

import Foundation

// MARK: - Identity

struct PlayerIdentity: Codable, Equatable {
    let id: String
    var name: String
}

enum PlayerIdentityStore {

    private static let key = "cookorcooked.player.identity"

    /// Loaded once per launch. Reading is cheap after the first call.
    private(set) static var current: PlayerIdentity = loadOrCreate()

    static func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        current = PlayerIdentity(id: current.id, name: String(trimmed.prefix(16)))
        persist(current)
    }

    private static func loadOrCreate() -> PlayerIdentity {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(PlayerIdentity.self, from: data) {
            return saved
        }
        let fresh = PlayerIdentity(id: UUID().uuidString,
                                   name: "Chef \(Int.random(in: 10...99))")
        persist(fresh)
        return fresh
    }

    private static func persist(_ identity: PlayerIdentity) {
        guard let data = try? JSONEncoder().encode(identity) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Room code

/// Four digits shown on the host's screen. To type it you have to be able to
/// see that screen, which is the only same-room proof that does not depend on
/// radios, walls or network configuration.
struct RoomCode: Codable, Equatable, Hashable, CustomStringConvertible {

    let digits: String

    var description: String { digits }

    /// Fails for anything that is not exactly four digits.
    init?(_ raw: String) {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 4, cleaned.allSatisfy(\.isNumber) else { return nil }
        digits = cleaned
    }

    private init(unchecked: String) {
        digits = unchecked
    }

    static func random() -> RoomCode {
        RoomCode(unchecked: String(format: "%04d", Int.random(in: 0...9999)))
    }

    /// Digit-by-digit, for the chunky display in the waiting room.
    var characters: [String] { digits.map(String.init) }
}
