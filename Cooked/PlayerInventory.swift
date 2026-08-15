//
//  PlayerInventory.swift
//  Cooked
//
//  A single chef's hands. At most ONE ingredient and ONE utensil at a time.
//
//  This is a pure model layer:
//    • It knows nothing about stations, gating, the map, or the network.
//    • Other systems (gating, rotten-disposal, scoring) will READ it later;
//      it never reaches back into them. One-way, by design.
//    • Items are Codable structs so a host can serialise and sync a player's
//      hands across devices when multiplayer lands.
//

import Foundation
import Combine

// MARK: - Carried items

/// An ingredient a chef is carrying, plus whether it came out rotten.
/// The `isRotten` flag is what a future "carry it to the trash" rule reads.
struct HeldIngredient: Identifiable, Equatable, Codable {
    let id: String        // stable key, e.g. "strawberries"
    let name: String      // display, e.g. "Strawberries"
    var isRotten: Bool = false
}

/// A utensil a chef is carrying. Utensils never rot.
struct HeldUtensil: Identifiable, Equatable, Codable {
    let id: String
    let name: String
}

// MARK: - Inventory

/// One chef's two hands: an ingredient slot and a utensil slot.
///
/// "Only one each" is enforced structurally — each slot is a single optional,
/// so it is *impossible* to hold two ingredients or two utensils. Picking up a
/// new item replaces whatever was in that slot and hands the old one back to
/// the caller (who can decide to drop it, return it to storage, etc.).
final class PlayerInventory: ObservableObject {

    @Published private(set) var ingredient: HeldIngredient?
    @Published private(set) var utensil: HeldUtensil?

    init(ingredient: HeldIngredient? = nil, utensil: HeldUtensil? = nil) {
        self.ingredient = ingredient
        self.utensil = utensil
    }

    // MARK: Queries

    var hasIngredient: Bool { ingredient != nil }
    var hasUtensil: Bool { utensil != nil }
    var isEmpty: Bool { ingredient == nil && utensil == nil }

    /// Does the chef hold this exact ingredient? (used by gating later)
    func holds(ingredientID: String) -> Bool { ingredient?.id == ingredientID }

    /// Does the chef hold this exact utensil? (used by gating later)
    func holds(utensilID: String) -> Bool { utensil?.id == utensilID }

    // MARK: Pick up (replaces the slot, returns whatever was displaced)

    @discardableResult
    func pickUp(_ newItem: HeldIngredient) -> HeldIngredient? {
        let displaced = ingredient
        ingredient = newItem
        return displaced
    }

    @discardableResult
    func pickUp(_ newItem: HeldUtensil) -> HeldUtensil? {
        let displaced = utensil
        utensil = newItem
        return displaced
    }

    // MARK: Drop / consume

    /// Remove the held ingredient (e.g. used in an action, or thrown in trash).
    func dropIngredient() { ingredient = nil }

    /// Remove the held utensil.
    func dropUtensil() { utensil = nil }

    /// Empty both hands.
    func clear() {
        ingredient = nil
        utensil = nil
    }

    // MARK: Sync snapshot (for host-authoritative multiplayer later)

    /// A plain, sendable copy of both hands. The host will broadcast these;
    /// guests apply them. Kept separate from the class so the network layer
    /// never touches the live object directly.
    struct Snapshot: Equatable, Codable {
        var ingredient: HeldIngredient?
        var utensil: HeldUtensil?
    }

    var snapshot: Snapshot {
        Snapshot(ingredient: ingredient, utensil: utensil)
    }

    func apply(_ snapshot: Snapshot) {
        ingredient = snapshot.ingredient
        utensil = snapshot.utensil
    }
}
