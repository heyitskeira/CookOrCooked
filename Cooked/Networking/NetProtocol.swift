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

    /// How many of each utensil are left on the storage shelf. Keyed by
    /// utensil id. Host-owned; guests read it to show "N left" and grey out
    /// what's gone.
    var utensilStock: [String: Int] = [:]

    /// Ingredients accumulated at each station, waiting for an action. Keys are
    /// `StationID.rawValue`, values are `foodID`s deposited so far. Host-owned
    /// so every chef sees the same bowl contents.
    var deposited: [String: [String]] = [:]

    /// The drawer's four shelves, in slot order (0/1 cold, 2/3 room temp).
    /// nil means the shelf is empty. Host-owned, like the bowls.
    var drawer: [DrawerItem?] = Array(repeating: nil, count: Drawer.slotCount)
    // MARK: Serving together
    //
    // Serving is the one thing in the kitchen nobody can do alone: every chef
    // has to be standing in the serve zone, and then everyone has to press at
    // the same moment. These three fields are what each device draws from —
    // who has gathered, whether the button is live, and whose press is still
    // inside the window.

    /// Player ids currently standing in the serve zone.
    var serveReady: [String] = []

    /// True when every connected chef is in the zone. Until then the SERVE
    /// button is visible but dead, so the missing person is obvious.
    var serveArmed: Bool = false

    /// Player ids holding the button right now. A hold that isn't joined by
    /// everyone else within `ServeRitual.gatherWindow` is dropped by the host,
    /// so pressing early does nothing rather than banking anything.
    var serveHolding: [String] = []

    /// How full the serve bar is, 0...1. Only climbs while every connected chef
    /// is holding; the moment one lets go it goes back to zero.
    var serveProgress: Double = 0
    /// The finished prep sitting on a station, waiting to be picked up. Keys are
    /// `StationID.rawValue`, values a `foodID`. A station with an output here is
    /// blocked — no new action until someone takes it.
    var stationOutput: [String: String] = [:]

    /// Convenience for the scene: who holds this station, if anyone.
    func holder(of station: StationID) -> String? {
        occupancy[station.rawValue]
    }

    /// What's been dropped into this station so far.
    func depositedFoods(at station: StationID) -> [String] {
        deposited[station.rawValue] ?? []
    }

    /// The prep sitting on this station waiting to be collected, if any.
    func outputFood(at station: StationID) -> String? {
        stationOutput[station.rawValue]
    }

    static let empty = GameSnapshot(completed: [],
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
    /// "Give me this utensil off the shelf." `returning` is the tool the chef
    /// was already holding (goes back on the shelf), or nil. Only the host may
    /// touch the counts, so two guests grabbing the last knife resolve cleanly.
    case requestUtensil(id: String, returning: String?)
    /// "I'm dropping this ingredient into the station in front of me."
    case deposit(station: String, foodID: String)
    /// "Put what I'm holding on this drawer shelf." The host checks the shelf is
    /// free and the temperature is right; the chef keeps the item until it says
    /// yes, so a refusal can never eat an ingredient.
    case requestStoreDrawer(slot: Int, item: DrawerItem)
    /// "Give me what's on this drawer shelf."
    case requestTakeDrawer(slot: Int)
    /// "I am / am no longer standing in the serve zone." Sent on the edge, not
    /// every frame — standing still is the normal case and it costs nothing.
    case serveReady(Bool)
    /// "I am holding the serve button" / "I let go." A hold, not a tap: the
    /// cake is only served if every chef holds at the same time long enough to
    /// fill the bar, so letting go is as meaningful as pressing.
    case serveHold(Bool)
    /// "I'm taking the finished prep off this station into my hands." The host
    /// clears the station's output; the prep goes into the guest's local hand.
    case pickUpOutput(station: String)
    /// "I'm taking one ingredient I'd dropped back off this station." The host
    /// removes that foodID from the station's deposits; it goes back into hand.
    case takeDeposit(station: String, foodID: String)

    // host -> guest
    case queued(position: Int)
    /// The utensil was in stock and is now the guest's.
    case utensilGranted(id: String)
    /// The shelf was empty — someone else has the last one.
    case utensilOut(id: String)
    /// The item is on the shelf now — the chef may empty their hand.
    case drawerStored(slot: Int)
    /// The shelf refused it: already occupied, or the wrong temperature. The
    /// chef keeps holding what they had.
    case drawerRefused(slot: Int, reason: String)
    /// The shelf's contents, now in the chef's hand. nil means someone emptied
    /// it first.
    case drawerTaken(slot: Int, item: DrawerItem?)
    /// The claim succeeded — open the station screen.
    case stationGranted(station: String)
    /// Someone got there first. The holder's ID is enough — the guest already
    /// has the roster, so it can find the name and the colour itself.
    case stationDenied(station: String, holderID: String)
    case rangingRequest
    case joinAccepted(player: Player)
    case joinRejected(reason: JoinRejection)
    case lobby(kitchenName: String, maxPlayers: Int, players: [Player])
    /// Leave the lobby and open the recipe book. The clock is NOT running yet —
    /// everyone is reading Today's Order while the head chef studies it.
    case start
    /// The head chef has closed the book. Now the kitchen opens and the timer
    /// starts. Split from `start` so that reading the recipe never costs the
    /// team any of their two minutes.
    case beginCooking
    case snapshot(GameSnapshot)
}
