//
//  StorageStation.swift
//  Cooked
//
//  Storage station — the pantry/fridge where chefs draw one ingredient or
//  utensil at a time. Ingredients can come out rotten based on their rot risk;
//  utensils never rot.
//
//  For now each ingredient/utensil exists as a single catalog entry (no stock
//  depletion, no duplicates yet).
//

import Foundation
import Combine

// MARK: - Rot risk

enum RotRisk {
    case none   // pantry staple — never rots (sugar)
    case low    // rarely rots (flour)
    case high   // perishable — often rots (strawberries, cream, butter, egg)

    /// Probability (0...1) that a drawn ingredient comes out rotten.
    /// Only `high` is spec'd (40%); `low`/`none` are sensible defaults — tune freely.
    var rotChance: Double {
        switch self {
        case .none: return 0.0
        case .low:  return 0.10
        case .high: return 0.40
        }
    }
}

// MARK: - Items

struct Ingredient: Identifiable, Equatable {
    let id: String        // stable key, e.g. "strawberries"
    let name: String      // display, e.g. "Strawberries"
    let rotRisk: RotRisk
}

struct Utensil: Identifiable, Equatable {
    let id: String
    let name: String
}

/// The outcome of drawing an ingredient from storage.
struct IngredientDraw: Equatable {
    let ingredient: Ingredient
    let isRotten: Bool
}

// MARK: - Catalog + draw logic

enum Storage {

    static let ingredients: [Ingredient] = [
        Ingredient(id: "strawberries", name: "Strawberries", rotRisk: .high),
        Ingredient(id: "cream",        name: "Cream",        rotRisk: .high),
        Ingredient(id: "butter",       name: "Butter",       rotRisk: .high),
        Ingredient(id: "egg",          name: "Egg",          rotRisk: .high),
        Ingredient(id: "flour",        name: "Flour",        rotRisk: .low),
        Ingredient(id: "sugar",        name: "Sugar",        rotRisk: .none),
    ]

    static let utensils: [Utensil] = [
        Utensil(id: "knife",  name: "Knife"),
        Utensil(id: "sifter", name: "Sifter"),
        Utensil(id: "whisk",  name: "Whisk"),
        Utensil(id: "mixer",  name: "Mixer"),
        Utensil(id: "pan",    name: "Pan"),
    ]

    /// Roll the rot chance for a chosen ingredient.
    /// `rng` is injectable so tests can force an outcome.
    static func draw(_ ingredient: Ingredient,
                     using rng: () -> Double = { Double.random(in: 0..<1) }) -> IngredientDraw {
        let rotten = rng() < ingredient.rotRisk.rotChance
        return IngredientDraw(ingredient: ingredient, isRotten: rotten)
    }
}

// MARK: - Pantry stock (limited utensils)

/// Tracks how many of each utensil are left in storage. Taking one decrements;
/// swapping a held utensil for another returns the old one to the shelf.
///
/// LOCAL FOR NOW. In multiplayer this is shared game state and must live in the
/// host's snapshot — the host owns the counts and broadcasts them. See
/// `Docs/NetworkingSpec-Storage-Deposit.md`. The `Snapshot` type below is the
/// wire shape Brio's netcode can adopt.
@MainActor
final class StoragePantry: ObservableObject {

    /// Default stock. Utensils are limited — that's the point of networking it.
    static let defaultUtensilStock: [String: Int] = [
        "knife":  1,
        "sifter": 1,
        "whisk":  2,
        "mixer":  1,
        "pan":    1,
    ]

    @Published private(set) var utensilStock: [String: Int]

    init(utensilStock: [String: Int] = StoragePantry.defaultUtensilStock) {
        self.utensilStock = utensilStock
    }

    func remaining(_ utensilID: String) -> Int { utensilStock[utensilID] ?? 0 }
    func isAvailable(_ utensilID: String) -> Bool { remaining(utensilID) > 0 }

    /// Take one off the shelf. Returns false if none left.
    @discardableResult
    func take(_ utensilID: String) -> Bool {
        guard remaining(utensilID) > 0 else { return false }
        utensilStock[utensilID, default: 0] -= 1
        return true
    }

    /// Put one back (e.g. the utensil a chef was holding before swapping).
    func giveBack(_ utensilID: String) {
        utensilStock[utensilID, default: 0] += 1
    }

    // Wire shape for host-authoritative sync (Brio).
    struct Snapshot: Codable, Equatable {
        var utensilStock: [String: Int]
    }
    var snapshot: Snapshot { Snapshot(utensilStock: utensilStock) }
    func apply(_ snapshot: Snapshot) { utensilStock = snapshot.utensilStock }
}
