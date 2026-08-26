//
//  KitchenArt.swift
//  Cooked
//
//  The seam between the art in Assets.xcassets and the code that draws it.
//
//  Every asset name in the game is *derived* from an identifier the rules
//  already own — `StationID.rawValue`, a `CookAction` output id, `UtensilID` —
//  so there is no second list of names to keep in sync. Add a station to
//  `Recipe.swift` and the art name it wants falls out of this file for free.
//
//  Nothing here asserts that the art exists. `texture(_:)` returns nil while a
//  drawing is still missing, which lets the scene keep its placeholder shape
//  and the game stay playable through the whole art pass.
//
//  Export settings and the full name list: Docs/ArtPipeline.md
//

import SpriteKit

enum KitchenArt {

    // MARK: - Names

    /// What a station looks like right now. `output` is the "finished prep is
    /// sitting here, go take it" look — it maps to `GameSnapshot.stationOutput`.
    enum StationState: String {
        case idle, busy, output
    }

    /// Which way a chef is facing. There is no `left`: the scene draws `side`
    /// with `xScale = -1` for it, which halves the number of drawings.
    enum Facing: String {
        case down, up, side
    }

    static func station(_ id: StationID, _ state: StationState) -> String {
        "station-\(id.rawValue)-\(state.rawValue)"
    }

    /// `foodID` is a `CookAction.output` or a raw storage ingredient —
    /// "strawberries", "siftedFlour", "assembledCake".
    static func food(_ foodID: String, rotten: Bool = false) -> String {
        "food-\(foodID)" + (rotten ? "-rotten" : "")
    }

    static func utensil(_ id: UtensilID) -> String {
        "utensil-\(id.rawValue)"
    }

    static func chef(walking: Bool, facing: Facing) -> String {
        "chef-\(walking ? "walk" : "idle")-\(facing.rawValue)"
    }

    /// The heads-down-at-a-station pose. One drawing, no facing — the chef is
    /// turned towards the counter by definition.
    static let chefBusy = "chef-busy"

    // MARK: - Loading

    /// Looks up a texture by name, or nil if that drawing has not landed yet.
    ///
    /// `SKTexture(imageNamed:)` never fails outright — for a name it cannot
    /// find it hands back a zero-sized texture and logs once. Measuring it is
    /// the only honest way to tell "missing" from "there", so that is what this
    /// does, and it caches the answer so a scene that asks every frame does not
    /// re-trigger the lookup or the log.
    static func texture(_ name: String) -> SKTexture? {
        if let cached = cache[name] { return cached }
        let candidate = SKTexture(imageNamed: name)
        let found = candidate.size() == .zero ? nil : candidate
        cache[name] = .some(found)
        return found
    }

    /// `.some(nil)` means "looked, wasn't there" — distinct from "not looked at
    /// yet", so a missing drawing is only ever probed once per launch.
    private static var cache: [String: SKTexture?] = [:]

    // MARK: - Nodes

    /// A station sprite sized to the footprint the rules use for collision and
    /// tap targets, or nil while the art is missing.
    ///
    /// The drawing is free to be *taller* than the footprint — a stove with a
    /// hood, a shelf above the counter. Width is matched to the footprint and
    /// height follows the drawing's own aspect ratio, with the anchor at the
    /// bottom edge so the extra height grows up the back wall instead of
    /// swallowing the floor the chef walks on.
    static func stationNode(_ id: StationID,
                            state: StationState = .idle,
                            footprint: CGSize) -> SKSpriteNode? {
        guard let tex = texture(station(id, state)) else { return nil }
        let node = SKSpriteNode(texture: tex)
        let aspect = tex.size().height / tex.size().width
        node.size = CGSize(width: footprint.width, height: footprint.width * aspect)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        return node
    }

    /// A chef sprite tinted to that player's colour.
    ///
    /// The drawing itself is greyscale: one body, recoloured per player, rather
    /// than four near-identical chefs in the atlas. `colorBlendFactor` below 1
    /// keeps the shading readable instead of flattening the sprite to a
    /// silhouette.
    static func chefNode(color: SKColor,
                         facing: Facing = .down,
                         height: CGFloat) -> SKSpriteNode? {
        guard let tex = texture(chef(walking: false, facing: facing)) else { return nil }
        let node = SKSpriteNode(texture: tex)
        let aspect = tex.size().width / tex.size().height
        node.size = CGSize(width: height * aspect, height: height)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.color = color
        node.colorBlendFactor = 0.7
        return node
    }
}
