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
    case chopping, bowl1, bowl2, mixing, table, stove, ovenServe, storage, trash

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
        }
    }

    /// Normalised 0...1 position. Multiplied by scene size at setup so the
    /// layout survives any screen size.
    var unitPosition: CGPoint {
        switch self {
        case .storage:   return CGPoint(x: 0.10, y: 0.80)
        case .chopping:  return CGPoint(x: 0.32, y: 0.84)
        case .bowl1:     return CGPoint(x: 0.55, y: 0.84)
        case .bowl2:     return CGPoint(x: 0.78, y: 0.84)
        case .mixing:    return CGPoint(x: 0.68, y: 0.58)
        case .stove:     return CGPoint(x: 0.90, y: 0.56)
        case .ovenServe: return CGPoint(x: 0.85, y: 0.24)
        case .table:     return CGPoint(x: 0.50, y: 0.40)
        case .trash:     return CGPoint(x: 0.12, y: 0.24)
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
    /// carryable item (pre-heat, serve, trash). Producing actions leave this on
    /// the station until a chef picks it up.
    var output: String? = nil
}

// MARK: - Recipe definition

nonisolated enum Recipe {
    
    // ---- Tuning knobs. These are the numbers to play with. ----
    
    static let timeLimit: TimeInterval = 120      // 2 minutes
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
        CookAction(id: 12, name: "Serve the Cake",        station: .ovenServe,                    requires: []),
        CookAction(id: 13, name: "Threw rotten ingredients", station: .trash,                     requires: [],  isRepeatable: true)
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
    private(set) var mess = 0
    private(set) var timeRemaining = Recipe.timeLimit
    private(set) var isOver = false
    private(set) var didWin = false
    
    var completedGoalCount: Int {
        Recipe.goalIDs.filter { completed.contains($0) }.count
    }
    
    func reset() {
        completed.removeAll()
        mess = 0
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
        if action.id == 14 && mess == 0 { return false }
        if action.id == 13 && mess == 0 { return false }
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
        mess = snapshot.mess
        timeRemaining = snapshot.timeRemaining
        isOver = snapshot.isOver
        didWin = snapshot.didWin
    }
}
