//
//  StorageArt.swift
//  Cooked
//
//  Which picture goes with which pantry item, and how the carousel presents it.
//
//  The catalogue keys (`Storage.ingredients`, `Storage.utensils`,
//  `DrawerItem.foodID`) are gameplay identifiers — "sifter", "whippedCream" —
//  and the art ships under descriptive filenames — "ui-sifter-active",
//  "ui-whip-cream". This is the one place those two vocabularies meet, so
//  renaming an asset never means hunting through view code.
//
//  The pantry set is drawn twice: `-active` in full colour, `-inactive` as the
//  same object in near-black silhouette. That is the designer's answer to
//  "someone else has the last knife" — not a tint or an opacity, a second
//  drawing. Rack preps have no such pair; nothing about a stored prep is ever
//  unavailable.
//

import SwiftUI

enum StorageArt {

    /// Catalogue id → the stem of its two-state pantry art. `image(_:inUse:)`
    /// appends `-active` / `-inactive`. Anything missing falls through to the
    /// older single-state art and then to a symbol, so a half-imported catalog
    /// degrades rather than crashes.
    private static let pantryStems: [String: String] = [
        // Utensils
        "knife":        "ui-knife",
        "sifter":       "ui-sifter",
        "whisk":        "ui-whisk",
        "mixer":        "ui-mixer",
        "pan":          "ui-saucepan",
        "pipingBag":    "ui-piping",
        // Ingredients
        "strawberries": "ui-strawberry",
        "cream":        "ui-cream",
        "butter":       "ui-butter",
        "egg":          "ui-egg",
        "flour":        "ui-flour",
        "sugar":        "ui-sugar"
    ]

    /// Single-state art: the preps that sit on the storage rack, plus the
    /// pantry items whose two-state pair hasn't been drawn.
    ///
    /// Keys are the `foodID`s `Recipe.actions` actually produces — not the
    /// asset filenames, which read differently ("whippedCream" vs
    /// ui-whip-cream, "bakedBase" vs ui-baked-cake).
    private static let names: [String: String] = [
        // Preps, final art
        "crackedEgg":          "ui-cracked-egg",
        "meltedButter":        "ui-melted-butter",
        "siftedFlour":         "ui-sifted-flour",
        "whippedCream":        "ui-whip-cream",
        "rawDough":            "ui-raw-dough",
        "bakedBase":           "ui-baked-cake",
        "choppedStrawberries": "ui-chopped-strawberries",
        // Preps still on the earlier set
        "maceratedStrawberries": "prepared-strawberry-slices",
        "assembledCake":         "prepared-cake-creamed",
        "finishedCake":          "prepared-cake-finished",
        // Utensils with no two-state pair yet
        "bakingTray":   "utensil-baking-tray"
    ]

    /// The dimmed silhouette shown in an item's place while someone else has
    /// it. Prefers the `-inactive` drawing; falls back to the older
    /// `-in-use` suffix on the single-state art.
    static func inUseAssetName(_ id: String) -> String? {
        if let stem = pantryStems[id], UIImage(named: stem + "-inactive") != nil {
            return stem + "-inactive"
        }
        guard let base = names[id] else { return nil }
        return UIImage(named: base + "-in-use") != nil ? base + "-in-use" : nil
    }

    /// The full-colour drawing.
    static func assetName(_ id: String) -> String? {
        if let stem = pantryStems[id] {
            // The piping bag ships its lit state as the bare stem, everything
            // else as `-active`. Try both rather than special-casing one id
            // here and again the next time an asset lands named the short way.
            if UIImage(named: stem + "-active") != nil { return stem + "-active" }
            if UIImage(named: stem) != nil { return stem }
        }
        return names[id]
    }

    static func image(_ id: String, inUse: Bool = false) -> UIImage? {
        if inUse, let dim = inUseAssetName(id), let art = UIImage(named: dim) { return art }
        guard let name = assetName(id) else { return nil }
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
    // Measured against the storage artboard (see `StorageCanvas`) — the plain
    // 874x402 screen, not the stretched one the station pages use.

    /// Height of the item the carousel is centred on.
    ///
    /// Down from 165. At that size the focused item's slot and its neighbours'
    /// actually overlapped — 1.35 times the height is a wide box, and three of
    /// them did not fit between the two chevrons — so the outer edge of one
    /// item sat on top of the next. Taking about 15% off both heights opens a
    /// real gap between the three slots and still leaves the middle one plainly
    /// the biggest thing on the shelf.
    static let focusedHeight: CGFloat = 140
    /// Height of the items either side of it.
    static let unfocusedHeight: CGFloat = 72

    // MARK: Seating a prep on a shelf

    /// How much of a drawing's height is empty space below the object, as a
    /// fraction of the whole image.
    ///
    /// The rack draws every prep in the same box, bottom-aligned, so that they
    /// rest on the plank. That only works if the drawing's own bottom edge is
    /// the object's bottom edge — and it isn't: the sliced strawberries carry
    /// 17% empty space underneath, the cake 5%. Bottom-aligning the *image*
    /// leaves the strawberries hovering a finger's width above the wood.
    /// Pushing the image down by this much seats the object instead.
    ///
    /// Measured off the alpha channel of each `@2x` asset. Redraw an asset with
    /// different margins and this number goes stale — the symptom is one item
    /// floating or sinking while its neighbours sit right.
    private static let bottomPadding: [String: CGFloat] = [
        "siftedFlour":           0.072,
        "meltedButter":          0.072,
        "crackedEgg":            0.072,
        "whippedCream":          0.068,
        "choppedStrawberries":   0.173,
        "bakedBase":             0.048,
        "rawDough":              0.134
    ]

    /// Fraction of the slot's height to push this food down by so it rests on
    /// the shelf. Zero for anything unmeasured, which bottom-aligns as before.
    static func seatOffsetFraction(_ foodID: String) -> CGFloat {
        bottomPadding[foodID] ?? 0
    }
}
