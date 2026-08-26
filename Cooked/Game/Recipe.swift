//
//  Recipe.swift
//  Cooked
//
//  Created by Keira on 10/08/26.
//

import Foundation
import CoreGraphics

// MARK: - Stations

// `nonisolated` because station identifiers cross the wire (they appear in
// `ChefSnapshot.station` and `GameSnapshot.occupancy`) and the transport
// decodes on a background callback. Under
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor an unannotated enum — and every
// member on it — would be main-actor isolated, so touching `rawValue` or
// `allCases` off the main actor would not compile.
nonisolated enum StationID: String, CaseIterable {
    case chopping, bowl1, bowl2, mixing, table, stove, ovenServe, storage, trash, drawer

    /// The nine stations a chef can walk to. `drawer` is deliberately absent:
    /// its shelves are now the Storage Rack tab inside the storage room, so it
    /// is somewhere you *reach through* Storage rather than somewhere you go.
    ///
    /// The case itself stays on `StationID` because it is still the key the
    /// drawer's shelves travel under in `GameSnapshot` and `RoomResume`.
    /// Removing it would be a wire-format change for a purely visual one.
    /// Anything drawing or walking the map wants this, not `allCases`.
    static let mapStations: [StationID] = [
        .chopping, .bowl1, .bowl2, .mixing, .table, .stove, .ovenServe, .storage, .trash
    ]

    var displayName: String {
        switch self {
        case .chopping: return "Chopping"
        case .bowl1 : return "Bowl 1"
        case .bowl2 : return "Bowl 2"
        case .mixing: return "Mixing"
        case .table : return "Table"
        case .stove : return "Stove"
        case .storage : return "Storage"
        case .trash : return "Trash"
        case .ovenServe: return "Oven"
        case .drawer: return "Drawer"
        }
    }

    /// Normalised 0...1 position on the artboard, resolved through
    /// `KitchenArt.mapPoint` so the layout survives any screen size.
    ///
    /// Every value below was measured off the reference art
    /// (`Asset-Final/Screens/09-kitchen/screen-09-kitchen-head-chef.png`) by
    /// locating each `station-*` sprite in the mockup, so the map matches the
    /// design exactly rather than approximately. Stations ring a clearing with
    /// an open middle; the pads they stand on are painted into
    /// `bg-kitchen-clearing`, so moving a station without moving its pad will
    /// leave it hovering on grass.
    ///
    /// This is the point the chef *walks to*, and it is deliberately the prop
    /// itself — the oven, the bowl, the bucket — not the centre of the sprite.
    /// Each sprite carries its name plaque off to one side, so the sprite
    /// centre can sit a long way from the thing a chef is meant to stand at.
    /// `artUnitOffset` carries that difference.
    ///
    /// That empty middle is where the match opens and closes: chefs spawn there
    /// in sight of each other, and the whole team has to come back to it to
    /// serve. See `ServeRitual`.
    var unitPosition: CGPoint {
        switch self {
        // The upper arc of the ring, left to right.
        case .stove:     return CGPoint(x: 0.2819, y: 0.4979)
        case .table:     return CGPoint(x: 0.3933, y: 0.5831)
        case .mixing:    return CGPoint(x: 0.5120, y: 0.6426)
        case .ovenServe: return CGPoint(x: 0.6147, y: 0.6384)
        case .chopping:  return CGPoint(x: 0.7157, y: 0.4928)
        // The lower arc, right to left.
        case .bowl1:     return CGPoint(x: 0.6677, y: 0.3099)
        case .storage:   return CGPoint(x: 0.5046, y: 0.2624)
        case .bowl2:     return CGPoint(x: 0.3399, y: 0.2999)
        case .trash:     return CGPoint(x: 0.0950, y: 0.1698)
        // Never drawn — the drawer is not on the map (see `mapStations`).
        // A value is still required because this switch must be exhaustive.
        case .drawer:    return .zero
        }
    }

    /// The map sprite for this station, or nil for one still waiting on art.
    ///
    /// Each sprite is prop *and* name plaque in a single image — which is why
    /// the scene draws no station name of its own any more. A nil here is what
    /// makes `KitchenScene` fall back to a labelled placeholder box.
    var artName: String? {
        switch self {
        case .chopping:  return "station-chopping"
        case .bowl1:     return "station-bowl-1"
        case .bowl2:     return "station-bowl-2"
        case .mixing:    return "station-mixing"
        case .table:     return "station-assembly"
        case .stove:     return "station-stove"
        case .ovenServe: return "station-baking"
        case .storage:   return "station-storage"
        case .trash:     return "station-trash"
        case .drawer:    return nil
        }
    }

    /// Sprite size as a fraction of the artboard, measured from the reference.
    ///
    /// Fractions rather than points because the art was authored at one fixed
    /// size. Multiplied by `KitchenArt.mapRect` — never by the raw scene — so
    /// both axes share a scale factor and a prop keeps its proportions and its
    /// place on the pad at any screen shape.
    var artUnitSize: CGSize {
        switch self {
        case .chopping:  return CGSize(width: 0.1939, height: 0.2034)
        case .bowl1:     return CGSize(width: 0.1733, height: 0.1337)
        case .bowl2:     return CGSize(width: 0.1802, height: 0.1337)
        case .mixing:    return CGSize(width: 0.1219, height: 0.1785)
        case .table:     return CGSize(width: 0.1296, height: 0.1567)
        case .stove:     return CGSize(width: 0.1997, height: 0.2108)
        case .ovenServe: return CGSize(width: 0.1859, height: 0.1710)
        case .storage:   return CGSize(width: 0.1207, height: 0.2898)
        case .trash:     return CGSize(width: 0.1207, height: 0.1959)
        case .drawer:    return .zero
        }
    }

    /// Roughly how much room the prop alone takes up, ignoring its plaque.
    ///
    /// Only the ready/busy halo uses this. Sizing that halo to `artUnitSize`
    /// instead would draw a ring around the name sign as well as the prop,
    /// which reads as the sign being interactive.
    var propUnitSize: CGSize {
        switch self {
        case .chopping:  return CGSize(width: 0.0931, height: 0.1525)
        case .bowl1:     return CGSize(width: 0.0780, height: 0.1203)
        case .bowl2:     return CGSize(width: 0.0811, height: 0.1203)
        case .mixing:    return CGSize(width: 0.1097, height: 0.1071)
        case .table:     return CGSize(width: 0.0803, height: 0.0862)
        case .stove:     return CGSize(width: 0.1098, height: 0.1792)
        case .ovenServe: return CGSize(width: 0.0744, height: 0.1625)
        case .storage:   return CGSize(width: 0.0942, height: 0.2174)
        case .trash:     return CGSize(width: 0.0845, height: 0.1567)
        case .drawer:    return .zero
        }
    }

    /// From `unitPosition` (the prop) to the centre of the sprite, as a
    /// fraction of the artboard. This is what puts each name plaque back on the
    /// side the reference art hangs it.
    var artUnitOffset: CGVector {
        switch self {
        case .chopping:  return CGVector(dx: +0.0543, dy: +0.0000)
        case .bowl1:     return CGVector(dx: +0.0485, dy: -0.0067)
        case .bowl2:     return CGVector(dx: -0.0505, dy: -0.0067)
        case .mixing:    return CGVector(dx: +0.0000, dy: +0.0393)
        case .table:     return CGVector(dx: -0.0155, dy: +0.0345)
        case .stove:     return CGVector(dx: -0.0399, dy: +0.0105)
        case .ovenServe: return CGVector(dx: +0.0632, dy: +0.0000)
        case .storage:   return CGVector(dx: +0.0000, dy: -0.0348)
        case .trash:     return CGVector(dx: +0.0000, dy: -0.0196)
        case .drawer:    return .zero
        }
    }
}

//MARK: How an action is performed
nonisolated enum ActionMotion {
    case chop
    case whisk
    case mix
    case sift
    case melt
    case breakEgg
    case hold
    /// Throwing the rotten one into the bin: tilt to aim, hold to charge.
    case throwAway
}

// MARK: - Actions

nonisolated struct CookAction {
    let id: Int
    let name: String
    let station: StationID
    var  motion: ActionMotion = .hold
    /// Prior actions that must be complete. Now used ONLY for non-item gates
    /// (the oven must be pre-heated before baking); ingredient order is enforced
    /// by what's deposited, not by this list.
    let requires: [Int]
    var isRepeatable: Bool = false
    /// The prep item this action produces (a `foodID`), or nil if it makes no
    /// carryable item (pre-heat, serve, trash).
    ///
    /// Producing actions leave this ON THE STATION until a chef picks it up —
    /// that is what gives the drawer something prepped to store, and what the
    /// result popup offers as "hands or station". This replaces the earlier
    /// `produces`, which handed the item straight to the chef.
    var output: String? = nil
}

// MARK: - Recipe definition

nonisolated enum Recipe {
    
    // ---- Tuning knobs. These are the numbers to play with. ----
    
    static let timeLimit: TimeInterval = 900      // 15 minutes
    static let showRecipeChecklist = true         // set false to simulate hidden recipe
    static let chefSpeed: CGFloat = 240           // points per second
    
    // ---- The 14 actions ----
    //
    // Three dependencies were missing from the original spec and are added here:
    //   - bake now requires pre-heat (7)
    //   - assemble requires the batter to exist (6)
    //   - serve requires decorate (11)
    
    // Order is now enforced by DEPOSITS (see GatingBridge), not `requires` —
    // an action fires only when its ingredients/preps are dropped in. `requires`
    // survives only where the gate isn't an item: bake needs a hot oven (8).
    // Each prep is made ONCE per game: after an action completes it's recorded,
    // so its "Do" button disappears and only the finished prep remains to be
    // collected. Order is enforced by deposits; `requires` survives only for
    // the oven pre-heat gate (8) and the serve gate (11) — serving is the
    // team ritual in the middle of the room, and `ServeRitual`/`serveIsArmed`
    // read `isUnlocked(serve)` to decide the SERVE button is live. Leave that
    // at `requires: []` and the whole team can serve an empty plate at 0:00.
    // Trash is the one repeatable action.
    static let actions: [CookAction] = [
        CookAction(id: 1,  name: "Cut strawberries",      station: .chopping,  motion: .chop,     requires: [],  output: "choppedStrawberries"),
        CookAction(id: 2,  name: "Macerate Strawberries", station: .bowl2,                        requires: [],  output: "maceratedStrawberries"),
        CookAction(id: 3,  name: "Sift flour",            station: .bowl1,     motion: .sift,     requires: [],  output: "siftedFlour"),
        CookAction(id: 4,  name: "Melt Butter",           station: .stove,     motion: .melt,     requires: [],  output: "meltedButter"),
        CookAction(id: 5,  name: "Crack Egg",             station: .bowl1,     motion: .breakEgg, requires: [],  output: "crackedEgg"),
        CookAction(id: 6,  name: "Make raw dough",        station: .mixing,    motion: .mix,      requires: [],  output: "rawDough"),
        CookAction(id: 7,  name: "Whip cream",            station: .bowl2,     motion: .whisk,    requires: [],  output: "whippedCream"),
        CookAction(id: 8,  name: "Pre-heat oven",         station: .ovenServe,                    requires: []),
        CookAction(id: 9,  name: "Bake base",             station: .ovenServe,                    requires: [8], output: "bakedBase"),
        CookAction(id: 10, name: "Assemble",              station: .table,                        requires: [],  output: "assembledCake"),
        CookAction(id: 11, name: "Decorate Cake",         station: .table,                        requires: [],  output: "finishedCake"),
        CookAction(id: 12, name: "Serve the Cake",        station: .ovenServe,                    requires: [11]),
        CookAction(id: 13, name: "Threw rotten ingredients", station: .trash, motion: .throwAway,  requires: [],  isRepeatable: true)
    ]
    
    static var goalIDs: [Int] {
        actions.filter { !$0.isRepeatable }.map { $0.id }
    }
    
    static func action(_ id: Int) -> CookAction? {
        actions.first { $0.id == id }
    }
}

// MARK: - Game state

final class GameState {
    
    private(set) var completed = Set<Int>()
    private(set) var timeRemaining = Recipe.timeLimit
    private(set) var isOver = false
    private(set) var didWin = false
    
    var completedGoalCount: Int {
        Recipe.goalIDs.filter { completed.contains($0) }.count
    }
    
    func reset() {
        completed.removeAll()
        timeRemaining = Recipe.timeLimit
        isOver = false
        didWin = false
    }

    /// Put a saved match back exactly where it was.
    ///
    /// Distinct from `apply(_:)`, which mirrors a live host: this is the host
    /// itself coming back from disk after its app died, so `isOver`/`didWin`
    /// are recomputed from the restored facts rather than trusted. A file
    /// written on the tick the clock ran out must not resume as a playable
    /// game with zero seconds on it.
    func restore(completed: Set<Int>, timeRemaining: TimeInterval) {
        self.completed = completed
        self.timeRemaining = max(0, timeRemaining)
        didWin = Recipe.goalIDs.allSatisfy { completed.contains($0) }
        isOver = didWin || self.timeRemaining <= 0
    }
    
    func tick(_ dt: TimeInterval) {
        guard !isOver else { return }
        timeRemaining -= dt
        if timeRemaining <= 0 {
            timeRemaining = 0
            isOver = true
            didWin = false
        }
    }
    
    /// An action is unlocked when every prerequisite is done, it hasn't
    /// already been performed, and any special gate is satisfied.
    func isUnlocked(_ action: CookAction) -> Bool {
        if !action.isRepeatable && completed.contains(action.id) { return false }
        for requirement in action.requires where !completed.contains(requirement) {
            return false
        }
        return true
    }
    
    /// The single action a chef standing at this station can start right now.
    /// The two bowls are interchangeable — any bowl action can be done at
    /// either bowl (agreed with Keira, replaces the bowl1/bowl2 split).
    static func sharesActions(_ a: StationID, _ b: StationID) -> Bool {
        if a == b { return true }
        let bowls: Set<StationID> = [.bowl1, .bowl2]
        return bowls.contains(a) && bowls.contains(b)
    }

    func availableAction(at station: StationID) -> CookAction? {
        Recipe.actions.first { GameState.sharesActions(station, $0.station) && isUnlocked($0) }
    }

    /// Why nothing is doable here — used for the on-screen nudge.
    func blockReason(at station: StationID) -> String {
        let here = Recipe.actions.filter { GameState.sharesActions(station, $0.station) }
        if here.isEmpty { return "Nothing happens here" }
        
        let unfinished = here.filter { !$0.isRepeatable && !completed.contains($0.id) }
        if unfinished.isEmpty { return "Station finished" }

        if let next = unfinished.first {
            let missing = next.requires
                .filter { !completed.contains($0) }
                .compactMap { Recipe.action($0)?.name }
            if !missing.isEmpty {
                return "Waiting on: " + missing.joined(separator: ", ")
            }
        }
        return "Not ready yet"
    }
    
    func complete(_ action: CookAction) {
        if !action.isRepeatable { completed.insert(action.id) }
        if Recipe.goalIDs.allSatisfy({ completed.contains($0) }) {
            isOver = true
            didWin = true
        }
    }
    
    /// Overwrite with the host's authoritative picture.
    ///
    /// In a networked game every device keeps a GameState, but only the host's
    /// is real. Everyone else's is a mirror refreshed ten times a second, which
    /// lets all the existing single-player logic — `availableAction(at:)`,
    /// `blockReason(at:)`, the HUD — keep working untouched.
    func apply(_ snapshot: GameSnapshot) {
        completed = Set(snapshot.completed)
        timeRemaining = snapshot.timeRemaining
        isOver = snapshot.isOver
        didWin = snapshot.didWin
    }
}
