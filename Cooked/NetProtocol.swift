//
//  NetProtocol.swift
//  Cooked
//
//  Everything that crosses the wire. Deliberately free of Network.framework
//  and NearbyInteraction imports so the transport underneath can be swapped
//  without touching the protocol.
//
//  The host is authoritative. Guests never mutate shared state directly —
//  they report intent (`moveTo`, `finishedAction`) and render whatever the
//  next snapshot says.
//

//  Everything here is `nonisolated` on purpose. The project builds with
//  SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so an unannotated type — and its
//  Codable conformance with it — would be main-actor isolated, and the
//  transport decodes frames on a background callback. Wire types cross
//  threads by definition, so they must opt out.

import Foundation

// MARK: - Roster

nonisolated struct Player: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var isHost: Bool
    /// False while the slot is being held for someone who dropped out.
    var isConnected: Bool
    /// Index into `PlayerPalette.colors`, assigned by the host on join.
    var colorIndex: Int
}

nonisolated enum PlayerPalette {
    /// Tomato, basil, blueberry, mustard — one per player, max four.
    static let rgb: [(r: Double, g: Double, b: Double)] = [
        (0.85, 0.35, 0.19),
        (0.24, 0.55, 0.32),
        (0.24, 0.42, 0.72),
        (0.88, 0.68, 0.18)
    ]

    static func components(_ index: Int) -> (r: Double, g: Double, b: Double) {
        rgb[((index % rgb.count) + rgb.count) % rgb.count]
    }
}

// MARK: - Snapshot

/// One chef's visible situation. Positions are unit coordinates (0...1) so
/// they survive different screen sizes between host and guest.
nonisolated struct ChefSnapshot: Codable, Equatable {
    var playerID: String
    var x: Double
    var y: Double
    /// `StationID.rawValue`, or nil while walking.
    var station: String?
    /// True while heads-down at a station. Rendered as a ring.
    var isBusy: Bool
}

/// The complete authoritative picture, broadcast by the host ~10x/second.
nonisolated struct GameSnapshot: Codable, Equatable {
    var completed: [Int]
    var mess: Int
    var timeRemaining: TimeInterval
    var isOver: Bool
    var didWin: Bool
    var chefs: [ChefSnapshot]

    /// Who is heads-down at which station. Keys are `StationID.rawValue`,
    /// values are player IDs. A station in this map is closed to everyone else.
    ///
    /// This is derived state — the host could recompute it from `chefs` — but
    /// it is sent explicitly because the host grants it *before* the guest is
    /// visibly busy, and that gap is exactly where a double-entry race lives.
    var occupancy: [String: String] = [:]

    /// Convenience for the scene: who holds this station, if anyone.
    func holder(of station: StationID) -> String? {
        occupancy[station.rawValue]
    }

    static let empty = GameSnapshot(completed: [], mess: 0,
                                    timeRemaining: Recipe.timeLimit,
                                    isOver: false, didWin: false, chefs: [],
                                    occupancy: [:])
}

// MARK: - Why a join failed

nonisolated enum JoinRejection: String, Codable {
    case wrongCode
    case kitchenFull
    case tooFarAway
    case alreadyStarted

    var message: String {
        switch self {
        case .wrongCode:      return "That code doesn't match this kitchen"
        case .kitchenFull:    return "This kitchen is full"
        case .tooFarAway:     return "You're too far from this kitchen"
        case .alreadyStarted: return "This game has already finished"
        }
    }
}

// MARK: - Messages

nonisolated enum NetMessage: Codable {

    // guest -> host
    /// Sent the moment the connection opens. `supportsRanging` tells the host
    /// whether to bother with a UWB check or go straight to the code.
    case hello(id: String, name: String, code: String, supportsRanging: Bool)
    /// Archived NIDiscoveryToken, exchanged only during join verification.
    case rangingToken(Data)
    case moveTo(x: Double, y: Double, station: String?, isBusy: Bool)
    case finishedAction(id: Int)
    /// "I've arrived at this station and want to start work." The host is the
    /// only one allowed to answer, which is what makes two guests arriving in
    /// the same frame resolve deterministically instead of both walking in.
    case claimStation(station: String)
    /// Sent on leaving a station — finished, backed out, or the game ended.
    /// The host also releases on disconnect, so a dropped guest can't padlock
    /// a station the rest of the kitchen still needs.
    case releaseStation(station: String)

    // host -> guest
    case queued(position: Int)
    /// The claim succeeded — open the station screen.
    case stationGranted(station: String)
    /// Someone got there first. The holder's ID is enough — the guest already
    /// has the roster, so it can find the name and the colour itself.
    case stationDenied(station: String, holderID: String)
    case rangingRequest
    case joinAccepted(player: Player)
    case joinRejected(reason: JoinRejection)
    case lobby(kitchenName: String, maxPlayers: Int, players: [Player])
    case start
    case snapshot(GameSnapshot)
}
