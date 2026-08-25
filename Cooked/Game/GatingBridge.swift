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

    /// The garbage bin's action. Named here rather than in `Recipe` so the
    /// rotten rules don't have to reach into a shared file for a literal.
    static let trashActionID = 13

    /// Which utensil an action needs in hand, derived from its motion.
    static func requiredUtensil(for action: CookAction) -> UtensilID? {
        switch action.motion {
        case .chop:     return .knife
        case .whisk:    return .whisk
        case .mix:      return .mixer
        case .sift:     return .sifter
        case .melt:     return .pan
        case .breakEgg: return nil
        case .hold:     return nil     // no tool needed (e.g. macerate, bake, serve)
        case .throwAway: return nil    // the bin takes what's in your hand, no tool
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

    /// Everything that must be deposited at the station for this action — raw
    /// ingredients AND prep items now that preps are carryable. Ids match
    /// `HeldIngredient.id` / `foodID`.
    static func requiredIngredients(for action: CookAction) -> Set<String> {
        switch action.id {
        case 1:  return ["strawberries"]                                              // chop
        case 2:  return ["choppedStrawberries", "sugar"]                              // macerate
        case 3:  return ["flour"]                                                     // sift
        case 4:  return ["butter"]                                                    // melt
        case 5:  return ["egg"]                                                       // crack egg
        case 6:  return ["siftedFlour", "meltedButter", "crackedEgg", "sugar"]        // dough
        case 7:  return ["cream"]                                                     // whip
        case 9:  return ["rawDough"]                                                  // bake (+ hot oven via requires)
        case 10: return ["bakedBase", "whippedCream", "maceratedStrawberries"]        // assemble
        case 11: return ["assembledCake"]                                             // decorate
        case 12: return ["finishedCake"]                                             // serve
        default: return []                                                            // preheat/trash
        }
    }

    /// Display name for any food id — raw ingredients and preps alike. Used by
    /// the inventory bar, deposit toasts, and the result popup.
    static func displayName(_ foodID: String) -> String {
        switch foodID {
        case "strawberries":         return "Strawberries"
        case "cream":                return "Cream"
        case "butter":               return "Butter"
        case "egg":                  return "Egg"
        case "flour":                return "Flour"
        case "sugar":                return "Sugar"
        case "choppedStrawberries":  return "Chopped strawberries"
        case "maceratedStrawberries":return "Macerated strawberries"
        case "siftedFlour":          return "Sifted flour"
        case "meltedButter":         return "Melted butter"
        case "crackedEgg":           return "Cracked egg"
        case "rawDough":             return "Raw dough"
        case "whippedCream":         return "Whipped cream"
        case "bakedBase":            return "Baked base"
        case "assembledCake":        return "Assembled cake"
        case "finishedCake":         return "Finished cake"
        default:                     return foodID.capitalized
        }
    }
}
