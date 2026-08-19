//
//  RecipeBook.swift
//  Cooked
//
//  "Today's Order" — the 11 steps of the strawberry shortcake, as data.
//
//  This is the *reading* copy of the recipe: what the head chef studies before
//  the timer starts. It is deliberately separate from two things it looks like:
//
//    • `Recipe.actions` (Recipe.swift) is the in-game action list the kitchen
//      scene runs on — ids, prerequisites, stations.
//    • `Recipes.all` (GatingLogic.swift) is the rules engine — which exact set
//      of ingredients plus which utensil produces which result.
//
//  The book is the player-facing story of the recipe, so it gets its own list
//  rather than reading one of theirs. Every step carries `gatingID`, the join
//  back to the rules engine — nil would mean "shown to the player, not yet a
//  real action", and `stepsWithNoAction` shouts about it in debug builds.
//  Right now all eleven map cleanly onto `Recipes.all`, which is the point:
//  the head chef never reads out an instruction the kitchen can't perform.
//
//  Change `steps` below and everything — both pages, the numbering, the
//  instruction cards — follows.
//

import SwiftUI

// MARK: - One step

/// A single line in the book: "these things + this tool = this result".
nonisolated struct BookStep: Identifiable, Equatable {

    let number: Int
    let title: String

    /// Ingredient ids going in — the left side of the equation. These match
    /// `FoodID.rawValue` wherever the rules engine already knows the item.
    let inputs: [String]

    /// The tool the chef must be holding. Matches `UtensilID.rawValue`.
    let utensil: String?

    /// What comes out — the right side of the equation.
    let output: String

    /// Where it happens. A `StationID` rather than free text so the book can
    /// never send a chef to a counter that isn't on the map.
    let station: StationID

    /// The matching `Recipes.all` id in GatingLogic, or nil when this step is
    /// a display-only beat the rules engine does not have as its own action.
    let gatingID: String?

    var id: Int { number }

    /// What the player should look for on the map. The two bowls are
    /// interchangeable (see `GameState.sharesActions`), so naming one of them
    /// would be a lie — say both.
    var stationLabel: String {
        switch station {
        case .bowl1, .bowl2: return "Bowl 1 or 2"
        default:             return station.displayName
        }
    }
}

// MARK: - The order

enum RecipeBook {

    static let orderTitle = "Strawberry Shortcake"

    static let steps: [BookStep] = [
        BookStep(number: 1, title: "Cut strawberries",
                 inputs: ["strawberries"], utensil: "knife",
                 output: "choppedStrawberries", station: .chopping,
                 gatingID: "chop"),

        BookStep(number: 2, title: "Macerate strawberries",
                 inputs: ["choppedStrawberries", "sugar"], utensil: nil,
                 output: "maceratedStrawberries", station: .bowl1,
                 gatingID: "macerate"),

        BookStep(number: 3, title: "Sift flour",
                 inputs: ["flour"], utensil: "sifter",
                 output: "siftedFlour", station: .bowl1,
                 gatingID: "sift"),

        BookStep(number: 4, title: "Melt butter",
                 inputs: ["butter"], utensil: "pan",
                 output: "meltedButter", station: .stove,
                 gatingID: "melt"),

        BookStep(number: 5, title: "Crack eggs",
                 inputs: ["egg"], utensil: "whisk",
                 output: "beatenEgg", station: .bowl1,
                 gatingID: "beat"),

        BookStep(number: 6, title: "Mix dough",
                 inputs: ["siftedFlour", "meltedButter", "beatenEgg", "sugar", "cream"],
                 utensil: "mixer",
                 output: "rawDough", station: .bowl1,
                 gatingID: "dough"),

        BookStep(number: 7, title: "Whip cream",
                 inputs: ["cream", "sugar"], utensil: "whisk",
                 output: "whippedCream", station: .bowl1,
                 gatingID: "whip"),

        BookStep(number: 8, title: "Preheat oven",
                 inputs: [], utensil: nil,
                 output: "hotOven", station: .ovenServe,
                 gatingID: "preheat"),

        // The hot oven is shown as an ingredient because that is how it reads
        // on the page: dough + heat = base. In the rules engine it is
        // `requiresHotOven` on the bake recipe rather than a deposited item.
        BookStep(number: 9, title: "Bake base",
                 inputs: ["rawDough", "hotOven"], utensil: nil,
                 output: "bakedBase", station: .ovenServe,
                 gatingID: "bake"),

        BookStep(number: 10, title: "Assemble & decorate",
                 inputs: ["bakedBase", "whippedCream", "maceratedStrawberries"],
                 utensil: nil,
                 output: "finishedCake", station: .table,
                 gatingID: "assemble"),

        // ⚠️ The two engines disagree on where serving happens: GatingLogic
        // says the table, `Recipe.actions` (what KitchenScene actually runs)
        // says the oven counter. The book follows the scene, because that is
        // the station a player will really be standing at.
        BookStep(number: 11, title: "Serve",
                 inputs: ["finishedCake"], utensil: nil,
                 output: "servedCake", station: .ovenServe,
                 gatingID: "serve")
    ]

    /// The book is a two-page spread, so the steps are split down the middle.
    /// Derived rather than hard-coded — 11 today (6 | 5, exactly as the mockup
    /// lays them out), any number tomorrow.
    static var pageBreak: Int { (steps.count + 1) / 2 }

    static var leftPage: [BookStep] { Array(steps.prefix(pageBreak)) }
    static var rightPage: [BookStep] { Array(steps.dropFirst(pageBreak)) }

    /// Steps the player is told to do that the rules engine cannot actually
    /// perform. A `gatingID` nobody checks is a comment, not a join — this is
    /// what makes it real. `RecipeBookView` trips an assertion on it in debug
    /// builds, so the book can't drift from the kitchen unnoticed.
    static var stepsWithNoAction: [BookStep] {
        steps.filter { step in
            guard let id = step.gatingID else { return true }
            return !Recipes.all.contains { $0.id == id }
        }
    }
}

// MARK: - Dummy art

/// Placeholder artwork, and the seam where the real assets arrive.
///
/// `ArtIcon` looks for an image set named exactly after the ingredient id
/// ("strawberries", "meltedButter", "knife"). Until one exists it draws a
/// tinted SF Symbol instead, so the screen is fully playable with no art at
/// all — and the day the imageset lands it is picked up with no code change.
enum FoodArt {

    struct Look {
        let symbol: String
        let tint: Color
    }

    private static let berry   = Color(red: 0.85, green: 0.25, blue: 0.30)
    private static let cream   = Color(red: 0.98, green: 0.95, blue: 0.88)
    private static let butter  = Color(red: 0.95, green: 0.78, blue: 0.28)
    private static let dough   = Color(red: 0.80, green: 0.68, blue: 0.48)
    private static let bake    = Color(red: 0.62, green: 0.42, blue: 0.24)
    private static let tool    = Color(red: 0.42, green: 0.47, blue: 0.55)
    private static let heat    = Color(red: 0.93, green: 0.45, blue: 0.16)

    private static let looks: [String: Look] = [
        // Raw
        "strawberries":          Look(symbol: "circle.hexagongrid.fill", tint: berry),
        "sugar":                 Look(symbol: "cube.fill",               tint: cream),
        "flour":                 Look(symbol: "bag.fill",                tint: dough),
        "butter":                Look(symbol: "rectangle.fill",          tint: butter),
        "egg":                   Look(symbol: "oval.fill",               tint: cream),
        "cream":                 Look(symbol: "cup.and.saucer.fill",     tint: cream),
        // Preps
        "choppedStrawberries":   Look(symbol: "square.grid.2x2.fill",    tint: berry),
        "maceratedStrawberries": Look(symbol: "drop.fill",               tint: berry),
        "siftedFlour":           Look(symbol: "aqi.medium",              tint: dough),
        "meltedButter":          Look(symbol: "drop.fill",               tint: butter),
        "beatenEgg":             Look(symbol: "tornado",                 tint: butter),
        "whippedCream":          Look(symbol: "cloud.fill",              tint: cream),
        "rawDough":              Look(symbol: "circle.fill",             tint: dough),
        "bakedBase":             Look(symbol: "rectangle.stack.fill",    tint: bake),
        "finishedCake":          Look(symbol: "star.fill",               tint: berry),
        "servedCake":            Look(symbol: "tray.fill",               tint: berry),
        // States
        "hotOven":               Look(symbol: "flame.fill",              tint: heat),
        // Tools
        "knife":                 Look(symbol: "fork.knife",              tint: tool),
        "sifter":                Look(symbol: "circle.grid.3x3.fill",    tint: tool),
        "whisk":                 Look(symbol: "tornado",                 tint: tool),
        "mixer":                 Look(symbol: "gearshape.fill",          tint: tool),
        "pan":                   Look(symbol: "oval.fill",               tint: tool)
    ]

    static func look(_ id: String) -> Look {
        looks[id] ?? Look(symbol: "questionmark", tint: tool)
    }

    /// Real artwork for an ingredient id, or nil while it's still a symbol.
    ///
    /// Cached because UIKit remembers asset-catalog *hits* but not *misses*,
    /// and right now every one of these is a miss — fourteen full bundle
    /// searches per redraw, on every frame of the card animation, otherwise.
    static func art(_ id: String) -> UIImage? {
        if let known = cache[id] { return known }
        let found = UIImage(named: id)
        cache[id] = found
        return found
    }

    private static var cache: [String: UIImage?] = [:]

    /// Turns "maceratedStrawberries" into "Macerated strawberries" so a new
    /// ingredient never has to be spelled out twice.
    static func name(_ id: String) -> String {
        var words = ""
        for character in id {
            if character.isUppercase && !words.isEmpty { words.append(" ") }
            words.append(character)
        }
        return words.prefix(1).uppercased() + words.dropFirst().lowercased()
    }
}

/// One ingredient or tool, drawn as real art if it exists and a tinted symbol
/// if it does not.
struct ArtIcon: View {

    let id: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(FoodArt.look(id).tint.opacity(0.22))

            if let art = FoodArt.art(id) {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.12)
            } else {
                Image(systemName: FoodArt.look(id).symbol)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(FoodArt.look(id).tint)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .stroke(AppTheme.ink.opacity(0.35), lineWidth: 2)
        )
    }
}
