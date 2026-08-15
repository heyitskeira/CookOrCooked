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
//    ACCUMULATES them. When a station holds the EXACT set an action needs AND a
//    chef is holding the right utensil AND any prep is satisfied (hot oven), the
//    action can be PERFORMED. Performing consumes the deposited ingredients and
//    leaves the result sitting ON the station. That result blocks the station
//    until someone TAKES it. Rotten ingredients are refused everywhere except
//    the garbage bin.
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

struct GatingRecipe: Equatable {
    let id: String
    let name: String
    let station: StationType
    let inputs: Set<FoodID>      // exact ingredient set the station must hold
    let utensil: UtensilID?      // utensil the chef must be holding, or nil
    let requiresHotOven: Bool    // prep gate
    let heatsOven: Bool          // pre-heat action sets the oven hot
    let output: FoodID?          // what's produced and left on the station; nil = consumed (serve)
}

enum Recipes {
    static let all: [GatingRecipe] = [
        GatingRecipe(id: "chop",     name: "Chop strawberries", station: .cuttingBoard,
                     inputs: [.strawberries], utensil: .knife,
                     requiresHotOven: false, heatsOven: false, output: .choppedStrawberries),

        GatingRecipe(id: "macerate", name: "Macerate strawberries", station: .bowl,
                     inputs: [.choppedStrawberries, .sugar], utensil: nil,
                     requiresHotOven: false, heatsOven: false, output: .maceratedStrawberries),

        GatingRecipe(id: "sift",     name: "Sift flour", station: .bowl,
                     inputs: [.flour], utensil: .sifter,
                     requiresHotOven: false, heatsOven: false, output: .siftedFlour),

        GatingRecipe(id: "melt",     name: "Melt butter", station: .stove,
                     inputs: [.butter], utensil: .pan,
                     requiresHotOven: false, heatsOven: false, output: .meltedButter),

        GatingRecipe(id: "beat",     name: "Beat egg", station: .bowl,
                     inputs: [.egg], utensil: .whisk,
                     requiresHotOven: false, heatsOven: false, output: .beatenEgg),

        GatingRecipe(id: "dough",    name: "Make dough", station: .bowl,
                     inputs: [.siftedFlour, .meltedButter, .beatenEgg, .sugar, .cream], utensil: .mixer,
                     requiresHotOven: false, heatsOven: false, output: .rawDough),

        GatingRecipe(id: "whip",     name: "Whip cream", station: .bowl,
                     inputs: [.cream, .sugar], utensil: .whisk,
                     requiresHotOven: false, heatsOven: false, output: .whippedCream),

        GatingRecipe(id: "preheat",  name: "Pre-heat oven", station: .oven,
                     inputs: [], utensil: nil,
                     requiresHotOven: false, heatsOven: true, output: nil),

        GatingRecipe(id: "bake",     name: "Bake base", station: .oven,
                     inputs: [.rawDough], utensil: nil,
                     requiresHotOven: true, heatsOven: false, output: .bakedBase),

        GatingRecipe(id: "assemble", name: "Assemble & decorate cake", station: .table,
                     inputs: [.bakedBase, .whippedCream, .maceratedStrawberries], utensil: nil,
                     requiresHotOven: false, heatsOven: false, output: .finishedCake),

        GatingRecipe(id: "serve",    name: "Serve cake", station: .table,
                     inputs: [.finishedCake], utensil: nil,
                     requiresHotOven: false, heatsOven: false, output: nil),
    ]

    static func at(_ station: StationType) -> [GatingRecipe] {
        all.filter { $0.station == station }
    }

    /// Every ingredient that any action at this station could ever want.
    static func validInputs(at station: StationType) -> Set<FoodID> {
        Set(at(station).flatMap { $0.inputs })
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

    /// Can this held ingredient be dropped onto this station right now?
    static func canDeposit(_ item: FoodItem, into station: Station) -> Bool {
        // A leftover result blocks everything until it's taken.
        if station.isBlocked { return false }

        // Garbage bin accepts rotten items only.
        if station.type == .garbage { return item.isRotten }

        // Cooking stations refuse rotten ingredients outright.
        if item.isRotten { return false }

        // It has to be something an action here actually uses,
        // and we don't stack two of the same ingredient.
        guard Recipes.validInputs(at: station.type).contains(item.id) else { return false }
        guard !station.deposited.contains(where: { $0.id == item.id }) else { return false }
        return true
    }

    /// Drop the ingredient if allowed. Returns whether it went in.
    @discardableResult
    static func deposit(_ item: FoodItem, into station: Station) -> Bool {
        guard canDeposit(item, into: station) else { return false }
        station._append(item)
        return true
    }

    // ---- Performing an action ----

    /// The one action that can be performed here, given what's deposited and
    /// what the chef is holding. `nil` if nothing is ready yet.
    static func availableAction(at station: Station, holdingUtensil utensil: UtensilID?) -> GatingRecipe? {
        guard !station.isBlocked else { return nil }
        let have = Set(station.deposited.map { $0.id })
        return Recipes.at(station.type).first { recipe in
            recipe.inputs == have
            && recipe.utensil == utensil
            && (!recipe.requiresHotOven || station.isHot)
        }
    }

    enum Outcome: Equatable {
        case produced(FoodItem)   // result now sits on the station
        case ovenHeated           // oven is now hot
        case served               // the cake was served — you win
        case notReady             // requirements not met
    }

    /// Try to perform whatever is ready at this station.
    @discardableResult
    static func perform(at station: Station, holdingUtensil utensil: UtensilID?) -> Outcome {
        guard let recipe = availableAction(at: station, holdingUtensil: utensil) else {
            return .notReady
        }

        if recipe.heatsOven {
            station._setHot(true)
            return .ovenHeated
        }

        station._clearDeposited()          // ingredients are consumed
        if let output = recipe.output {
            let result = FoodItem(id: output)
            station._setOutput(result)     // result blocks the station until taken
            return .produced(result)
        } else {
            return .served                 // serve consumes the cake, no leftover
        }
    }

    // ---- Taking the result / trashing ----

    /// Pick up the finished result, freeing the station. Goes into a chef's hand.
    static func takeOutput(from station: Station) -> FoodItem? {
        let result = station.output
        station._setOutput(nil)
        return result
    }

    /// Throw a rotten ingredient in the bin. Only rotten items, only the bin.
    static func throwAway(_ item: FoodItem, at station: Station) -> Bool {
        guard station.type == .garbage, item.isRotten else { return false }
        return true   // caller clears it from the hand
    }

    // ---- Explanation for a blocked station (handy for UI/debug later) ----

    static func blockReason(at station: Station, holdingUtensil utensil: UtensilID?) -> String {
        if station.isBlocked {
            return "Clear the \(station.output!.id.displayName) first"
        }
        if availableAction(at: station, holdingUtensil: utensil) != nil {
            return "Ready"
        }
        let have = Set(station.deposited.map { $0.id })
        // Find the closest recipe (most matching ingredients) to explain what's missing.
        let candidate = Recipes.at(station.type)
            .max(by: { $0.inputs.intersection(have).count < $1.inputs.intersection(have).count })
        guard let recipe = candidate else { return "Nothing happens here" }

        let missingItems = recipe.inputs.subtracting(have).map { $0.displayName }
        if !missingItems.isEmpty {
            return "Need: " + missingItems.sorted().joined(separator: ", ")
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
