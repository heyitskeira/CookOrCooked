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
