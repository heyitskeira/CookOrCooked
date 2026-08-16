//
//  GatingBridge.swift
//  Cooked
//
//  The seam between the team's station/action system (CookAction + motion) and
//  this project's inventory rule ("you must hold the right tool to act").
//
//  Kept as a separate, additive file so it doesn't rewrite anyone's model:
//  it only READS a CookAction and a PlayerInventory and answers "allowed?".
//
//  NOTE — scope: their CookAction has no ingredient list and their stations
//  don't accumulate deposited ingredients yet, so for now the gate checks the
//  UTENSIL only (hold a whisk to whisk, a knife to chop, …). The multi-
//  ingredient "deposit into the bowl" gate from GatingLogic is a later step
//  that needs the recipe model extended — a change to coordinate with Keira.
//

import Foundation

enum GatingBridge {

    /// Which utensil an action needs in hand, derived from its motion.
    static func requiredUtensil(for action: CookAction) -> UtensilID? {
        switch action.motion {
        case .chop:     return .knife
        case .whisk:    return .whisk
        case .mix:      return .mixer
        case .sift:     return .sifter
        case .melt:     return .pan
        case .breakEgg: return .whisk
        case .hold:     return nil     // no tool needed (e.g. macerate, bake, serve)
        }
    }

    /// Returns a player-facing reason the action is blocked, or nil if allowed.
    /// Utensil ids are matched by their string key (`UtensilID.rawValue` ==
    /// `HeldUtensil.id`, e.g. "whisk").
    static func blockReason(for action: CookAction, holding inventory: PlayerInventory?) -> String? {
        guard let needed = requiredUtensil(for: action) else { return nil }
        if inventory?.utensil?.id == needed.rawValue { return nil }
        return "Need a \(needed.displayName) in hand"
    }
}
