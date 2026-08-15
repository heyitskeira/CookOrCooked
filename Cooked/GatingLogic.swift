//
//  GatingLogic.swift
//  Cooked
//
//  Created by Agung Ananda on 15/08/26.
//
//  The kitchen's rules engine. Pure logic — no screens, no map, no network.
//
//  How it works, in one breath:
//    Chefs DEPOSIT ingredients (one hand at a time) into a station. The station
//    ACCUMULATES them. When a station holds what an action needs AND a chef is
//    holding the right utensil AND any prep is satisfied (hot oven), the action
//    can be PERFORMED. Performing consumes the deposited ingredients and applies
//    the action's effect. Producing actions leave their result ON the station,
//    which blocks it until someone TAKES it.
//
//  The garbage bin is just another station: its action accepts ANY rotten
//  ingredient and discards it. No special-casing — the "any rotten" rule is
//  declared as data on the recipe, so it runs through the same path as the rest.
//
//  Decoupled on purpose: items are identified by their own enums here, so this
//  file builds and tests on its own. It gets mapped to PlayerInventory /
//  Storage at the integration seam later.
//

import Foundation

// MARK: - Foods

/// Every ingredient and product that can sit in a hand or on a station.
enum FoodID: String, CaseIterable {
    // Raw — these come from storage and are the only ones that can be rotten.
    case strawberries, cream, butter, egg, flour, sugar
    // Intermediates / products — made by actions, never rotten.
    case choppedStrawberries, maceratedStrawberries, siftedFlour
    case meltedButter, beatenEgg, rawDough, whippedCream, bakedBase, finishedCake

    var displayName: String {
        switch self {
        case .strawberries:          return "Strawberries"
        case .cream:                 return "Cream"
        case .butter:                return "Butter"
        case .egg:                   return "Egg"
        case .flour:                 return "Flour"
        case .sugar:                 return "Sugar"
        case .choppedStrawberries:   return "Chopped strawberries"
        case .maceratedStrawberries: return "Macerated strawberries"
        case .siftedFlour:           return "Sifted flour"
        case .meltedButter:          return "Melted butter"
        case .beatenEgg:             return "Beaten egg"
        case .rawDough:              return "Raw dough"
        case .whippedCream:          return "Whipped cream"
        case .bakedBase:             return "Baked base"
        case .finishedCake:          return "Finished cake"
        }
    }

    /// Only raw ingredients from storage can be rotten.
    var canRot: Bool {
        switch self {
        case .strawberries, .cream, .butter, .egg, .flour, .sugar: return true
        default: return false
        }
    }
}

/// A concrete piece of food, with its freshness. Products are always fresh.
struct FoodItem: Equatable {
    let id: FoodID
    var isRotten: Bool = false
}

// MARK: - Utensils

enum UtensilID: String, CaseIterable {
    case knife, sifter, whisk, mixer, pan

    var displayName: String {
        switch self {
        case .knife:  return "Knife"
        case .sifter: return "Sifter"
        case .whisk:  return "Whisk"
        case .mixer:  return "Mixer"
        case .pan:    return "Pan"
        }
    }
}

// MARK: - Station types

enum StationType: String, CaseIterable {
    case cuttingBoard, bowl, stove, oven, table, garbage

    var displayName: String {
        switch self {
        case .cuttingBoard: return "Cutting board"
        case .bowl:         return "Bowl"
        case .stove:        return "Stove"
        case .oven:         return "Oven"
        case .table:        return "Table"
        case .garbage:      return "Garbage bin"
        }
    }

    /// How many physical copies exist. Bowl is the bottleneck, so it gets two.
    var instanceCount: Int {
        self == .bowl ? 2 : 1
    }
}

// MARK: - Recipes (the 12 actions, as data)

/// What a station must hold for an action to fire.
enum InputRequirement: Equatable {
    case exact(Set<FoodID>)   // an exact set of ingredients (empty = none needed)
    case anyRotten            // exactly one rotten ingredient, any kind (garbage)
}

/// What performing the action does.
enum ActionEffect: Equatable {
    case produce(FoodID)      // consume inputs, leave this result on the station
    case heatOven             // set the oven hot (no inputs consumed)
    case serve                // consume the cake — you win
    case discard              // consume the rotten ingredient — trashed
}

struct GatingRecipe: Equatable {
    let id: String
    let name: String
    let station: StationType
    let input: InputRequirement
    let utensil: UtensilID?      // utensil the chef must hold, or nil
    let requiresHotOven: Bool
    let effect: ActionEffect
}

enum Recipes {
    static let all: [GatingRecipe] = [
        GatingRecipe(id: "chop", name: "Chop strawberries", station: .cuttingBoard,
                     input: .exact([.strawberries]), utensil: .knife,
                     requiresHotOven: false, effect: .produce(.choppedStrawberries)),

        GatingRecipe(id: "macerate", name: "Macerate strawberries", station: .bowl,
                     input: .exact([.choppedStrawberries, .sugar]), utensil: nil,
                     requiresHotOven: false, effect: .produce(.maceratedStrawberries)),

        GatingRecipe(id: "sift", name: "Sift flour", station: .bowl,
                     input: .exact([.flour]), utensil: .sifter,
                     requiresHotOven: false, effect: .produce(.siftedFlour)),

        GatingRecipe(id: "melt", name: "Melt butter", station: .stove,
                     input: .exact([.butter]), utensil: .pan,
                     requiresHotOven: false, effect: .produce(.meltedButter)),

        GatingRecipe(id: "beat", name: "Beat egg", station: .bowl,
                     input: .exact([.egg]), utensil: .whisk,
                     requiresHotOven: false, effect: .produce(.beatenEgg)),

        GatingRecipe(id: "dough", name: "Make dough", station: .bowl,
                     input: .exact([.siftedFlour, .meltedButter, .beatenEgg, .sugar, .cream]), utensil: .mixer,
                     requiresHotOven: false, effect: .produce(.rawDough)),

        GatingRecipe(id: "whip", name: "Whip cream", station: .bowl,
                     input: .exact([.cream, .sugar]), utensil: .whisk,
                     requiresHotOven: false, effect: .produce(.whippedCream)),

        GatingRecipe(id: "preheat", name: "Pre-heat oven", station: .oven,
                     input: .exact([]), utensil: nil,
                     requiresHotOven: false, effect: .heatOven),

        GatingRecipe(id: "bake", name: "Bake base", station: .oven,
                     input: .exact([.rawDough]), utensil: nil,
                     requiresHotOven: true, effect: .produce(.bakedBase)),

        GatingRecipe(id: "assemble", name: "Assemble & decorate cake", station: .table,
                     input: .exact([.bakedBase, .whippedCream, .maceratedStrawberries]), utensil: nil,
                     requiresHotOven: false, effect: .produce(.finishedCake)),

        GatingRecipe(id: "serve", name: "Serve cake", station: .table,
                     input: .exact([.finishedCake]), utensil: nil,
                     requiresHotOven: false, effect: .serve),

        // Garbage is just another station with its own action.
        GatingRecipe(id: "throwGarbage", name: "Throw out rotten", station: .garbage,
                     input: .anyRotten, utensil: nil,
                     requiresHotOven: false, effect: .discard),
    ]

    static func at(_ station: StationType) -> [GatingRecipe] {
        all.filter { $0.station == station }
    }
}

// MARK: - Station instance (holds live state)

/// One physical station. Two bowls each have their own separate contents.
final class Station: Identifiable {
    let type: StationType
    let index: Int              // 0 for singletons; 0/1 for the two bowls

    private(set) var deposited: [FoodItem] = []   // accumulated ingredients
    private(set) var output: FoodItem?            // result waiting to be taken
    private(set) var isHot = false                // oven only

    init(type: StationType, index: Int = 0) {
        self.type = type
        self.index = index
    }

    var id: String { "\(type.rawValue)#\(index)" }
    var isBlocked: Bool { output != nil }         // a leftover result blocks the station

    // The mutations below are only ever reached through GatingEngine, which
    // checks the rules first. Kept internal so tests can read state.
    func _append(_ item: FoodItem) { deposited.append(item) }
    func _clearDeposited() { deposited.removeAll() }
    func _setOutput(_ item: FoodItem?) { output = item }
    func _setHot(_ hot: Bool) { isHot = hot }
    func _reset() { deposited.removeAll(); output = nil; isHot = false }
}

// MARK: - The engine (all the rules live here)

enum GatingEngine {

    // ---- Depositing ingredients ----

    /// Can this held item be dropped onto this station right now? True if any
    /// action at the station would accept it as a valid addition.
    static func canDeposit(_ item: FoodItem, into station: Station) -> Bool {
        if station.isBlocked { return false }   // a leftover result blocks everything

        for recipe in Recipes.at(station.type) {
            switch recipe.input {
            case .exact(let set):
                // Cooking actions want a fresh, listed ingredient, not duplicated.
                if !item.isRotten,
                   set.contains(item.id),
                   !station.deposited.contains(where: { $0.id == item.id }) {
                    return true
                }
            case .anyRotten:
                // The bin accepts any rotten item.
                if item.isRotten { return true }
            }
        }
        return false
    }

    /// Drop the item if allowed. Returns whether it went in.
    @discardableResult
    static func deposit(_ item: FoodItem, into station: Station) -> Bool {
        guard canDeposit(item, into: station) else { return false }
        station._append(item)
        return true
    }

    // ---- Performing an action ----

    private static func inputSatisfied(_ requirement: InputRequirement, by deposited: [FoodItem]) -> Bool {
        switch requirement {
        case .exact(let set):
            return Set(deposited.map { $0.id }) == set
        case .anyRotten:
            return deposited.count == 1 && deposited[0].isRotten
        }
    }

    /// The one action that can be performed here, given what's deposited and
    /// what the chef is holding. `nil` if nothing is ready yet.
    static func availableAction(at station: Station, holdingUtensil utensil: UtensilID?) -> GatingRecipe? {
        guard !station.isBlocked else { return nil }
        return Recipes.at(station.type).first { recipe in
            inputSatisfied(recipe.input, by: station.deposited)
            && recipe.utensil == utensil
            && (!recipe.requiresHotOven || station.isHot)
        }
    }

    enum Outcome: Equatable {
        case produced(FoodItem)   // result now sits on the station
        case ovenHeated           // oven is now hot
        case served               // the cake was served — you win
        case trashed              // a rotten ingredient was thrown out
        case notReady             // requirements not met
    }

    /// Try to perform whatever is ready at this station.
    @discardableResult
    static func perform(at station: Station, holdingUtensil utensil: UtensilID?) -> Outcome {
        guard let recipe = availableAction(at: station, holdingUtensil: utensil) else {
            return .notReady
        }

        switch recipe.effect {
        case .heatOven:
            station._setHot(true)
            return .ovenHeated

        case .produce(let output):
            station._clearDeposited()
            let result = FoodItem(id: output)
            station._setOutput(result)     // result blocks the station until taken
            return .produced(result)

        case .serve:
            station._clearDeposited()
            return .served

        case .discard:
            station._clearDeposited()
            return .trashed
        }
    }

    // ---- Taking the result ----

    /// Pick up the finished result, freeing the station. Goes into a chef's hand.
    static func takeOutput(from station: Station) -> FoodItem? {
        let result = station.output
        station._setOutput(nil)
        return result
    }

    // ---- Explanation for a blocked station (handy for UI/debug later) ----

    static func blockReason(at station: Station, holdingUtensil utensil: UtensilID?) -> String {
        if station.isBlocked {
            return "Clear the \(station.output!.id.displayName) first"
        }
        if availableAction(at: station, holdingUtensil: utensil) != nil {
            return "Ready"
        }
        if station.type == .garbage {
            return "Bring a rotten ingredient"
        }

        let have = Set(station.deposited.map { $0.id })
        // Find the closest recipe (most matching ingredients) to explain what's missing.
        let candidate = Recipes.at(station.type)
            .compactMap { recipe -> (GatingRecipe, Set<FoodID>)? in
                if case .exact(let set) = recipe.input { return (recipe, set) }
                return nil
            }
            .max(by: { $0.1.intersection(have).count < $1.1.intersection(have).count })

        guard let (recipe, needed) = candidate else { return "Nothing happens here" }

        let missing = needed.subtracting(have).map { $0.displayName }
        if !missing.isEmpty {
            return "Need: " + missing.sorted().joined(separator: ", ")
        }
        if recipe.requiresHotOven && !station.isHot {
            return "Pre-heat the oven first"
        }
        if let need = recipe.utensil, need != utensil {
            return "Need a \(need.displayName) in hand"
        }
        return "Not ready yet"
    }
}

// MARK: - Kitchen (all the station instances in one place)

/// Builds one of every station, plus the second bowl. Convenience for tests
/// and, later, whatever drives the map.
final class Kitchen {
    let stations: [Station]

    init() {
        stations = StationType.allCases.flatMap { type in
            (0..<type.instanceCount).map { Station(type: type, index: $0) }
        }
    }

    func stations(of type: StationType) -> [Station] {
        stations.filter { $0.type == type }
    }

    func firstStation(of type: StationType) -> Station? {
        stations.first { $0.type == type }
    }

    func reset() { stations.forEach { $0._reset() } }
}
