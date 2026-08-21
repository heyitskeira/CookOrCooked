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

    /// Normalised 0...1 position. Multiplied by scene size at setup so the
    /// layout survives any screen size.
    ///
    /// Stations line the walls, the way a real kitchen does — a run of counters
    /// along the back, the pantry and oven down the right, prep and the bin on
    /// the left. The middle is left deliberately empty.
    ///
    /// That empty floor is where the match opens and closes: chefs spawn there
    /// in sight of each other, and the whole team has to come back to it to
    /// serve. See `ServeRitual`.
    ///
    /// The positions also clear the screen furniture the scene draws on top of
    /// the map — the recipe checklist down the top left, the clock top right,
    /// the chef's hands bottom left, the SERVE button bottom right.
    var unitPosition: CGPoint {
        switch self {
        // The counter run along the back wall. Mixing sits between the bowls
        // it draws from and the stove, so the batter never crosses the room.
        case .chopping:  return CGPoint(x: 0.28, y: 0.86)
        case .bowl1:     return CGPoint(x: 0.40, y: 0.86)
        case .bowl2:     return CGPoint(x: 0.53, y: 0.86)
        case .mixing:    return CGPoint(x: 0.65, y: 0.86)
        case .stove:     return CGPoint(x: 0.77, y: 0.86)
        // Right-hand wall. The drawer is the other put-things-away station, so
        // it sits with the pantry rather than out on its own.
        case .storage:   return CGPoint(x: 0.90, y: 0.60)
        case .ovenServe: return CGPoint(x: 0.90, y: 0.38)
        case .drawer:    return CGPoint(x: 0.90, y: 0.80)
        // Left-hand wall.
        case .table:     return CGPoint(x: 0.24, y: 0.55)
        case .trash:     return CGPoint(x: 0.28, y: 0.30)
        // Next to the pantry on the right, because they're the same errand:
        // you go over there to fetch something. Added when the drawer landed —
        // a merge left this switch a case short, which is a compile error
        // rather than a bad position, since it must cover every StationID.
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
