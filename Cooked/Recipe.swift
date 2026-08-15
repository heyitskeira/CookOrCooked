//
//  Recipe.swift
//  Cooked
//
//  Created by Keira on 10/08/26.
//

import Foundation
import CoreGraphics

// MARK: - Stations

// Pure data, read from both the main actor and the nonisolated wire types
// (GameSnapshot.empty reads Recipe.timeLimit). Under this project's
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor these would otherwise be
// main-actor isolated and unreachable from there.

nonisolated enum StationID: String, CaseIterable {
    case sink, chopping, dryPrep, crusher, stove, mixing, whipping, oven, prep, trash

    var displayName: String {
        switch self {
        case .sink:     return "Sink"
        case .chopping: return "Chopping"
        case .dryPrep:  return "Dry prep"
        case .crusher:  return "Crusher"
        case .stove:    return "Stove"
        case .mixing:   return "Mixing"
        case .whipping: return "Whipping"
        case .oven:     return "Oven"
        case .prep:     return "Prep counter"
        case .trash:    return "Trash bin"
        }
    }

    /// Normalised 0...1 position. Multiplied by scene size at setup so the
    /// layout survives any screen size.
    var unitPosition: CGPoint {
        switch self {
        case .sink:     return CGPoint(x: 0.13, y: 0.82)
        case .chopping: return CGPoint(x: 0.36, y: 0.82)
        case .dryPrep:  return CGPoint(x: 0.60, y: 0.82)
        case .crusher:  return CGPoint(x: 0.85, y: 0.82)
        case .stove:    return CGPoint(x: 0.87, y: 0.60)
        case .mixing:   return CGPoint(x: 0.13, y: 0.52)
        case .whipping: return CGPoint(x: 0.34, y: 0.52)
        case .oven:     return CGPoint(x: 0.87, y: 0.36)
        case .prep:     return CGPoint(x: 0.52, y: 0.22)
        case .trash:    return CGPoint(x: 0.13, y: 0.20)
        }
    }
}

// MARK: - Actions

nonisolated struct CookAction {
    let id: Int
    let name: String
    let station: StationID
    let duration: TimeInterval
    let requires: [Int]
    var isRepeatable: Bool = false
    /// How much mess this action leaves behind. Negative values clean up.
    var messDelta: Int = 1
}

// MARK: - Recipe definition

nonisolated enum Recipe {

    // ---- Tuning knobs. These are the numbers to play with. ----

    static let timeLimit: TimeInterval = 300      // 5 minutes
    static let requireCleanBeforeServe = true     // the "cleanup crunch" rule
    static let showRecipeChecklist = true         // set false to simulate hidden recipe
    static let chefSpeed: CGFloat = 240           // points per second

    // ---- The 14 actions ----
    //
    // Three dependencies were missing from the original spec and are added here:
    //   - bake now requires pre-heat (7)
    //   - assemble requires the batter to exist (6)
    //   - serve requires decorate (11)

    static let actions: [CookAction] = [
        CookAction(id: 1,  name: "Wash strawberries", station: .sink,     duration: 4,  requires: []),
        CookAction(id: 2,  name: "Cut strawberries",  station: .chopping, duration: 5,  requires: [1]),
        CookAction(id: 3,  name: "Melt butter",       station: .stove,    duration: 6,  requires: []),
        CookAction(id: 4,  name: "Sift flour",        station: .dryPrep,  duration: 5,  requires: []),
        CookAction(id: 5,  name: "Break biscuit",     station: .crusher,  duration: 5,  requires: []),
        CookAction(id: 6,  name: "Mix all mixture",   station: .mixing,   duration: 8,  requires: [3, 4, 5]),
        CookAction(id: 7,  name: "Pre-heat oven",     station: .oven,     duration: 6,  requires: [], messDelta: 0),
        CookAction(id: 8,  name: "Whip the cream",    station: .whipping, duration: 7,  requires: []),
        CookAction(id: 9,  name: "Assemble the cake", station: .prep,     duration: 6,  requires: [6]),
        CookAction(id: 10, name: "Bake the cake",     station: .oven,     duration: 20, requires: [7, 9]),
        CookAction(id: 11, name: "Decorate the cake", station: .prep,     duration: 8,  requires: [2, 8, 10]),
        CookAction(id: 12, name: "Serve",             station: .prep,     duration: 4,  requires: [11], messDelta: 0),

        // Reactive cleanup. Repeatable, never "completed", clears mess.
        CookAction(id: 13, name: "Wash dishes",       station: .sink,  duration: 5, requires: [],
                   isRepeatable: true, messDelta: -3),
        CookAction(id: 14, name: "Throw out garbage", station: .trash, duration: 4, requires: [],
                   isRepeatable: true, messDelta: -3)
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
        if action.id == 12 && Recipe.requireCleanBeforeServe && mess > 0 { return false }
        return true
    }

    /// The single action a chef standing at this station can start right now.
    func availableAction(at station: StationID) -> CookAction? {
        Recipe.actions.first { $0.station == station && isUnlocked($0) }
    }

    /// Why nothing is doable here — used for the on-screen nudge.
    func blockReason(at station: StationID) -> String {
        let here = Recipe.actions.filter { $0.station == station }
        if here.isEmpty { return "Nothing happens here" }

        let unfinished = here.filter { !$0.isRepeatable && !completed.contains($0.id) }
        if unfinished.isEmpty {
            if station == .sink || station == .trash { return "Kitchen is clean" }
            return "Station finished"
        }

        if let next = unfinished.first {
            if next.id == 12 && mess > 0 {
                return "Clean the kitchen first (\(mess) mess)"
            }
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
        mess = max(0, mess + action.messDelta)
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
