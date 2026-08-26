//
//  StorageArt.swift
//  Cooked
//
//  Which picture goes with which pantry item, and how the carousel presents it.
//
//  The catalogue keys (`Storage.ingredients`, `Storage.utensils`,
//  `DrawerItem.foodID`) are gameplay identifiers — "sifter", "cream" — and the
//  art ships under descriptive filenames — "utensil-flour-sifter",
//  "ingredient-cream-jug". This is the one place those two vocabularies meet, so
//  renaming an asset never means hunting through view code.
//

import SwiftUI

enum StorageArt {

    /// Catalogue id → asset name. Anything missing falls through to a symbol,
    /// so a half-imported asset catalogue degrades rather than crashes.
    private static let names: [String: String] = [
        // Utensils
        "knife":        "utensil-knife",
        "sifter":       "utensil-flour-sifter",
        "whisk":        "utensil-whisk",
        "mixer":        "utensil-hand-mixer",
        "pan":          "utensil-saucepan",
        "pipingBag":    "utensil-piping-bag",
        "bakingTray":   "utensil-baking-tray",
        // Ingredients
        "strawberries": "ingredient-strawberries",
        "cream":        "ingredient-cream-jug",
        "butter":       "ingredient-butter",
        "egg":          "ingredient-egg",
        "flour":        "ingredient-flour-sack",
        "sugar":        "ingredient-sugar-sack",
        // Preps, for the storage rack. Keys are the `foodID`s `Recipe.actions`
        // actually produces — not the asset filenames, which read differently
        // ("choppedStrawberries" vs prepared-strawberry-slices).
        "crackedEgg":          "prepared-bowl-beaten-egg",
        "meltedButter":        "prepared-bowl-melted-butter",
        "siftedFlour":         "prepared-bowl-sifted-flour",
        "whippedCream":        "prepared-bowl-whipped-cream",
        "bakedBase":           "prepared-cake-base",
        "assembledCake":       "prepared-cake-creamed",
        "rawDough":            "prepared-dough",
        "choppedStrawberries": "prepared-strawberry-slices"
    ]

    /// The dimmed silhouette shown in an item's place while someone else has
    /// it. The art ships these as separate `-in-use` files rather than as a
    /// tint, because a flat black fill of the same shape is not what the
    /// designer drew.
    static func inUseAssetName(_ id: String) -> String? {
        guard let base = names[id] else { return nil }
        return UIImage(named: base + "-in-use") != nil ? base + "-in-use" : nil
    }

    static func image(_ id: String, inUse: Bool = false) -> UIImage? {
        if inUse, let dim = inUseAssetName(id), let art = UIImage(named: dim) { return art }
        guard let name = names[id] else { return nil }
        return UIImage(named: name)
    }

    /// Fallback glyph for an item with no art yet.
    static func symbol(_ id: String) -> String {
        switch id {
        case "knife":  return "scissors"
        case "whisk", "mixer": return "tornado"
        case "sifter": return "circle.grid.3x3.fill"
        case "pan":    return "frying.pan.fill"
        default:       return "leaf.fill"
        }
    }

    // MARK: Carousel presentation
    //
    // Straight from the design notes on the storage board.

    /// Height of the item the carousel is centred on.
    static let focusedHeight: CGFloat = 280
    /// Height of the items either side of it.
    static let unfocusedHeight: CGFloat = 130
    /// Every item hangs at the same slight angle, focused or not.
    static let tilt: Angle = .degrees(-20)
}
