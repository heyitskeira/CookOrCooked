//
//  RoomResume.swift
//  Cooked
//
//  What lets a kitchen outlive the app that was hosting it.
//
//  The original bug: the room code was generated fresh in every
//  `KitchenSession.init`, and a guest reconnected by Bonjour *endpoint*. Both
//  of those die when the host's app does. So a host that crashed, backgrounded
//  too long, or was stopped from Xcode came back as a brand new kitchen with a
//  brand new code, and the chefs still standing in the old one had nothing left
//  to reconnect to.
//
//  The fix is one idea in two halves:
//
//    • A room has an identity of its own — `roomID` — that is written to disk
//      the moment it opens. Relaunching the app reopens the *same* room: same
//      id, same four digits, same roster, same clock.
//    • A player rejoining presents a `resumeToken` the host issued them on the
//      way in. The host recognises the token, restores their slot and colour,
//      and skips the code and the UWB check — they already proved they were in
//      the room, and making them prove it again mid-match is the whole bad
//      experience we are removing.
//
//  Everything here is deliberately `nonisolated` and stringly-typed: it is
//  written by the main actor but its contents cross the wire as plain values.
//

import Foundation

// MARK: - The room's own identity

/// A kitchen, independent of any socket, Bonjour endpoint, or app launch.
///
/// `roomID` is what a rejoining guest names in its handshake. Two hosts on the
/// same Wi-Fi can pick the same four digits — that's a 1-in-10,000 coin flip,
/// and it used to mean joining the wrong kitchen. The id makes that impossible.
nonisolated struct RoomTicket: Codable, Equatable {
    let roomID: String
    let code: String
    var kitchenName: String
    var maxPlayers: Int

    static func fresh(kitchenName: String, maxPlayers: Int) -> RoomTicket {
        RoomTicket(roomID: UUID().uuidString,
                   code: RoomCode.random().digits,
                   kitchenName: kitchenName,
                   maxPlayers: maxPlayers)
    }
}

// MARK: - What the host writes down

/// Enough of the kitchen to rebuild it after the app dies.
///
/// This is not a save game — it is a *thirty second* insurance policy against
/// the host's app going away mid-match. It is deliberately the host's
/// authoritative tables and nothing else: no scene state, no local hands, no
/// UI. Everything a returning chef sees is rebuilt from a snapshot anyway.
nonisolated struct SavedHostRoom: Codable {

    /// Where the match had got to. The lobby is worth saving too: a host who
    /// quits while people are still arriving should come back to the same code
    /// rather than making everyone re-enter a new one.
    nonisolated enum Stage: String, Codable { case lobby, briefing, playing }

    var ticket: RoomTicket
    var stage: Stage
    var players: [Player]
    /// playerID -> the token that proves this device was already admitted.
    var resumeTokens: [String: String]

    var completed: [Int]
    var timeRemaining: TimeInterval
    var chefs: [ChefSnapshot]
    var utensilStock: [String: Int]
    var deposited: [String: [String]]
    var drawer: [DrawerItem?]
    var stationOutput: [String: String]

    var savedAt: Date
}

// MARK: - What a guest writes down

/// A guest only needs to know which room it belongs to and how to prove it.
nonisolated struct SavedGuestRoom: Codable {
    var roomID: String
    var code: String
    var kitchenName: String
    var resumeToken: String
    /// Whether the match had actually started. A guest who closed the app while
    /// still in the lobby should not have the start screen hijacked on next
    /// launch — nobody is frozen waiting on them.
    var wasMidMatch: Bool
    var savedAt: Date

    enum CodingKeys: String, CodingKey {
        case roomID, code, kitchenName, resumeToken, wasMidMatch, savedAt
    }

    init(roomID: String, code: String, kitchenName: String,
         resumeToken: String, wasMidMatch: Bool, savedAt: Date) {
        self.roomID = roomID
        self.code = code
        self.kitchenName = kitchenName
        self.resumeToken = resumeToken
        self.wasMidMatch = wasMidMatch
        self.savedAt = savedAt
    }

    // Hand-written for the same reason `Player`'s is: `wasMidMatch` arrived
    // after the first build, and a synthesised decoder treats a missing key as
    // a failure even where the property has a default. A file written by the
    // previous build would otherwise silently fail to decode.
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        roomID = try box.decode(String.self, forKey: .roomID)
        code = try box.decode(String.self, forKey: .code)
        kitchenName = try box.decode(String.self, forKey: .kitchenName)
        resumeToken = try box.decode(String.self, forKey: .resumeToken)
        wasMidMatch = try box.decodeIfPresent(Bool.self, forKey: .wasMidMatch) ?? false
        savedAt = try box.decode(Date.self, forKey: .savedAt)
    }
}

// MARK: - Storage

nonisolated enum RoomResumeStore {

    /// How long a written-down kitchen stays worth reopening.
    ///
    /// Generous on purpose. The guests' own patience is much shorter — they
    /// give up after `PauseRules.graceSeconds` — so this window is really
    /// about the host relaunching and finding the room still there to be
    /// offered, not about anyone waiting fifteen minutes.
    static let window: TimeInterval = 15 * 60

    private static let hostKey  = "cookorcooked.room.host"
    private static let guestKey = "cookorcooked.room.guest"

    // MARK: Host

    static func saveHost(_ room: SavedHostRoom) {
        guard let data = try? JSONEncoder().encode(room) else { return }
        UserDefaults.standard.set(data, forKey: hostKey)
    }

    static func loadHost() -> SavedHostRoom? {
        guard let data = UserDefaults.standard.data(forKey: hostKey),
              let room = try? JSONDecoder().decode(SavedHostRoom.self, from: data),
              Date().timeIntervalSince(room.savedAt) < window else {
            return nil
        }
        return room
    }

    static func clearHost() {
        UserDefaults.standard.removeObject(forKey: hostKey)
    }

    // MARK: Guest

    static func saveGuest(_ room: SavedGuestRoom) {
        guard let data = try? JSONEncoder().encode(room) else { return }
        UserDefaults.standard.set(data, forKey: guestKey)
    }

    static func loadGuest() -> SavedGuestRoom? {
        guard let data = UserDefaults.standard.data(forKey: guestKey),
              let room = try? JSONDecoder().decode(SavedGuestRoom.self, from: data),
              Date().timeIntervalSince(room.savedAt) < window else {
            return nil
        }
        return room
    }

    static func clearGuest() {
        UserDefaults.standard.removeObject(forKey: guestKey)
    }

    // MARK: What the start screen asks

    /// The kitchen this device was last in, whichever side of it we were on.
    ///
    /// A device can only be in one kitchen at a time, but both keys can be
    /// populated across sessions — you host one evening and join the next — so
    /// the more recent write wins.
    static var resumable: ResumableKitchen? {
        let host = loadHost()
        let guest = loadGuest()
        switch (host, guest) {
        case let (h?, g?):
            return h.savedAt >= g.savedAt ? .host(h) : .guest(g)
        case let (h?, nil):  return .host(h)
        case let (nil, g?):  return .guest(g)
        case (nil, nil):     return nil
        }
    }

    static func clearAll() {
        clearHost()
        clearGuest()
    }
}

nonisolated enum ResumableKitchen: Identifiable {
    case host(SavedHostRoom)
    case guest(SavedGuestRoom)

    /// The room's own id, which is exactly the right identity: two launches
    /// that find the same kitchen must not be treated as two different offers.
    var id: String {
        switch self {
        case .host(let room):  return room.ticket.roomID
        case .guest(let room): return room.roomID
        }
    }

    var kitchenName: String {
        switch self {
        case .host(let room):  return room.ticket.kitchenName
        case .guest(let room): return room.kitchenName
        }
    }

    /// A lobby that was never started is worth reopening, but it is not the
    /// urgent case — nobody is standing in a frozen kitchen waiting for it, so
    /// taking over the start screen for one would be obnoxious every time
    /// somebody backed out of setting a game up.
    var wasMidMatch: Bool {
        switch self {
        case .host(let room):  return room.stage != .lobby
        case .guest(let room): return room.wasMidMatch
        }
    }
}

// MARK: - Timings

/// The three clocks the pause feature runs on, in one place so they can be
/// tuned without hunting through the session.
nonisolated enum PauseRules {

    /// How long the kitchen stays frozen waiting for a host who went away.
    /// Long enough to relaunch a crashed app and walk back; short enough that
    /// nobody is stranded staring at a still frame.
    static let graceSeconds = 90

    /// "Host is back — 3, 2, 1." Dropping straight back into a live kitchen is
    /// how you lose a cake you were carrying.
    static let resumeCountdown = 3

    /// The same beat after the last chef presses Ready, so the auto-start
    /// isn't a jump-scare and there is a moment to un-ready.
    static let startCountdown = 3
}
