//
//  HandsNode.swift
//  Cooked
//
//  The chef's own two paws, coming up into the bottom-right of the kitchen map.
//
//  Left paw carries the ingredient or the prep you just made, right paw carries
//  the utensil. That split is not decoration: it is exactly the shape of
//  `PlayerInventory` (one ingredient slot, one utensil slot), so the hands can
//  never show a state the model can't hold.
//
//  They belong to the map and only the map. Inside a station screen the motion
//  is the whole picture, so the hands drop away entirely and come back — with
//  whatever you just made — once you're out in the kitchen again.
//
//  The art is one image per animal containing *both* paws (`paw-squirrel` and
//  friends), not one per hand. So a single sprite is drawn underneath, and the
//  two hand nodes are invisible anchors parked over where each paw sits inside
//  it — which is why the offsets below are fractions of the pair rather than a
//  gap between two separate hands.
//

import SpriteKit
import SwiftUI

@MainActor
final class HandsNode: SKNode {

    // MARK: Layout

    /// Width of the paw pair, as a fraction of the map artwork — not a fixed
    /// number of points.
    ///
    /// Absolute sizing put the paws over Bowl Station 1 on a 852pt phone and
    /// over four fifths of it on an SE, because the map shrinks with the screen
    /// and a constant does not. Measuring against `KitchenArt.mapRect` keeps the
    /// same clearance on every device, and keeps the paws on the artwork rather
    /// than down in the letterbox band on an iPad.
    private static let pairWidthFraction: CGFloat = 0.16

    /// How far in from the artwork's right edge the pair sits, also a fraction.
    private static let edgeInsetFraction: CGFloat = 0.018
    /// Centre of each paw, as a fraction of the pair's width from its middle.
    /// Measured off the art: the two paws sit a little inboard of the edges.
    private let pawOffset: CGFloat = 0.24
    /// How far the hands slide down when hidden — far enough to clear the item.
    private let dropDistance: CGFloat = 150

    /// Both paws in one picture. Nil until an animal is chosen, and nil forever
    /// if the art is missing, in which case the placeholder mittens are drawn.
    private var pawArt: SKSpriteNode?
    /// How far above a paw's centre an item sits. Set by `layout(for:)`, since
    /// it scales with the pair.
    private var itemRise: CGFloat = 38
    private let leftHand: SKNode
    private let rightHand: SKNode

    /// The item chips currently drawn, so a repeat call can skip the rebuild.
    /// `refresh` runs every frame on the kitchen map; rebuilding two sprites at
    /// 60fps for a hand that hasn't changed is pure garbage collection work.
    private var shownPrep: String??
    private var shownUtensil: String??

    // MARK: Setup

    /// - Parameter pawAsset: which animal's paws to draw, already resolved.
    ///
    ///   Handed in rather than worked out here. This used to take a
    ///   `colorIndex` and run it through a paw list of its own, which was a
    ///   second, different answer to a question `ChefCast` was already
    ///   answering for the lobby cards — so a chef was a raccoon on the card
    ///   and a rabbit in the kitchen. `KitchenSession.localPawAsset` is now the
    ///   one place that decides, and this just draws what it is told.
    init(screenSize: CGSize, pawAsset: String = ChefCast.Animal.squirrel.paw) {
        leftHand = SKNode()
        rightHand = SKNode()
        super.init()

        zPosition = 150

        // Behind the hand anchors, so an item always sits on top of the paw
        // holding it.
        if let art = UIImage(named: pawAsset) {
            let sprite = SKSpriteNode(texture: SKTexture(image: art))
            sprite.zPosition = -1
            addChild(sprite)
            pawArt = sprite
        } else {
            // No paw art in the bundle — the old placeholder mittens, so the
            // map still shows what is in each hand.
            buildPalm(on: leftHand)
            buildPalm(on: rightHand)
            leftHand.zRotation = 0.14
            rightHand.zRotation = -0.14
        }

        addChild(leftHand)
        addChild(rightHand)

        layout(for: screenSize)

        alpha = 0
        isHidden = true
        position = CGPoint(x: 0, y: -dropDistance)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// The pair sits in the bottom-right, so this *does* depend on the screen
    /// width — and the scene is built at the safe-area size then resized to the
    /// view's real bounds, so it has to be re-run on every resize or the paws
    /// end up short of the corner.
    func layout(for screenSize: CGSize) {
        let map = KitchenArt.mapRect(in: screenSize)
        guard map.width > 0 else { return }

        let width = map.width * Self.pairWidthFraction
        // From the texture, not a shared constant: the six paw images run from
        // 298x220 to 356x220, so one hardcoded ratio squashes the beaver by 12%
        // and stretches the fox and rabbit. Only the squirrel — the default —
        // would have looked right.
        let height = width / Self.aspect(of: pawArt?.texture)

        let centreX = map.maxX - map.width * Self.edgeInsetFraction - width / 2
        // A little below the artwork's bottom edge, so the paws read as
        // reaching up into frame rather than resting on the floor.
        let centreY = map.minY + height / 2 - height * 0.10

        pawArt?.size = CGSize(width: width, height: height)
        pawArt?.position = CGPoint(x: centreX, y: centreY)

        itemRise = height * 0.26
        leftHand.position = CGPoint(x: centreX - width * pawOffset, y: centreY)
        rightHand.position = CGPoint(x: centreX + width * pawOffset, y: centreY)
        for hand in [leftHand, rightHand] {
            hand.childNode(withName: "item")?.position = CGPoint(x: 0, y: itemRise)
        }
    }

    /// Falls back to the squirrel's ratio only when there is no texture at all,
    /// which is the placeholder-mitten path.
    private static func aspect(of texture: SKTexture?) -> CGFloat {
        guard let size = texture?.size(), size.height > 0 else { return 314.0 / 220.0 }
        return size.width / size.height
    }

    /// The stand-in used only when the paw art is missing: a rounded palm with
    /// a thumb.
    private func buildPalm(on hand: SKNode) {
        let palm = SKShapeNode(rectOf: CGSize(width: 62, height: 74), cornerRadius: 26)
        palm.fillColor = SKColor(red: 0.93, green: 0.78, blue: 0.64, alpha: 1)
        palm.strokeColor = SKColor(red: 0.42, green: 0.28, blue: 0.20, alpha: 1)
        palm.lineWidth = 3
        palm.name = "palm"
        hand.addChild(palm)

        let thumb = SKShapeNode(circleOfRadius: 13)
        thumb.fillColor = palm.fillColor
        thumb.strokeColor = palm.strokeColor
        thumb.lineWidth = 3
        thumb.position = CGPoint(x: 28, y: 14)
        hand.addChild(thumb)
    }

    // MARK: What's in them

    /// Put an item in each hand. Passing nil empties that hand.
    ///
    /// `isRotten` used to be the inventory bar's job — it drew a queasy face on
    /// spoiled ingredients. The bar is gone, so the mark comes here instead:
    /// without it a chef can't tell what needs binning, and the bin is a real
    /// step in the recipe.
    func setItems(prep: String?, isRotten: Bool = false, utensil: String?) {
        let leftKey = prep.map { isRotten ? "\($0)!rotten" : $0 }
        if shownPrep != .some(leftKey) {
            shownPrep = .some(leftKey)
            setItem(prep, on: leftHand, isRotten: isRotten)
        }
        if shownUtensil != .some(utensil) {
            shownUtensil = .some(utensil)
            setItem(utensil, on: rightHand)
        }
    }

    private func setItem(_ id: String?, on hand: SKNode, isRotten: Bool = false) {
        hand.childNode(withName: "item")?.removeFromParent()
        guard let id else { return }

        let item = SKNode()
        item.name = "item"
        // In the pad of the paw that holds it, not floating above the claws.
        item.position = CGPoint(x: 0, y: itemRise)

        if let art = FoodArt.art(id) {
            let sprite = SKSpriteNode(texture: SKTexture(image: art))
            let longest = max(sprite.size.width, sprite.size.height)
            if longest > 0 {
                let scale = 52 / longest
                sprite.size = CGSize(width: sprite.size.width * scale,
                                     height: sprite.size.height * scale)
            }
            item.addChild(sprite)
        } else {
            // Stand-in: a chip tinted like the ingredient, initials on top.
            let tint = SKColor(FoodArt.look(id).tint)
            let chip = SKShapeNode(rectOf: CGSize(width: 52, height: 52), cornerRadius: 14)
            chip.fillColor = tint
            chip.strokeColor = SKColor(white: 0.15, alpha: 0.7)
            chip.lineWidth = 2.5
            item.addChild(chip)

            let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
            label.text = Self.initials(of: id)
            label.fontSize = 17
            label.fontColor = SKColor(white: 0.12, alpha: 0.85)
            label.verticalAlignmentMode = .center
            item.addChild(label)
        }

        if isRotten {
            let mark = SKLabelNode(fontNamed: "AvenirNext-Bold")
            mark.text = "!"
            mark.fontSize = 15
            mark.fontColor = .white
            mark.verticalAlignmentMode = .center
            mark.zPosition = 2

            let badge = SKShapeNode(circleOfRadius: 11)
            badge.fillColor = SKColor(red: 0.55, green: 0.30, blue: 0.55, alpha: 1)
            badge.strokeColor = SKColor(white: 1, alpha: 0.9)
            badge.lineWidth = 2
            badge.position = CGPoint(x: 22, y: 22)
            badge.zPosition = 1
            badge.addChild(mark)
            item.addChild(badge)
        }

        hand.addChild(item)
    }

    /// "meltedButter" -> "MB", "flour" -> "FL". Enough to tell two dummy chips
    /// apart while the real art is still missing.
    private static func initials(of id: String) -> String {
        let capitals = id.filter(\.isUppercase)
        if let first = id.first, !capitals.isEmpty {
            return (String(first) + capitals.prefix(1)).uppercased()
        }
        return id.prefix(2).uppercased()
    }

    // MARK: Coming and going

    /// Slide up into frame. `bounce` gives the little overshoot that sells
    /// "here's what you just made" at the end of an action.
    func appear(bounce: Bool = false) {
        removeAllActions()
        isHidden = false

        let rise = SKAction.group([
            .move(to: .zero, duration: 0.22),
            .fadeAlpha(to: 1, duration: 0.18)
        ])
        rise.timingMode = .easeOut

        if bounce {
            let overshoot = SKAction.moveBy(x: 0, y: 14, duration: 0.09)
            overshoot.timingMode = .easeOut
            let settle = SKAction.moveBy(x: 0, y: -14, duration: 0.12)
            settle.timingMode = .easeIn
            run(.sequence([rise, overshoot, settle]))
        } else {
            run(rise)
        }
    }

    /// Drop out of frame. Used the moment a station screen opens — during the
    /// action the motion is the whole picture and the hands are in the way.
    func vanish(animated: Bool = true) {
        removeAllActions()
        guard animated else {
            alpha = 0
            isHidden = true
            position = CGPoint(x: 0, y: -dropDistance)
            return
        }

        let fall = SKAction.group([
            .move(to: CGPoint(x: 0, y: -dropDistance), duration: 0.16),
            .fadeAlpha(to: 0, duration: 0.14)
        ])
        fall.timingMode = .easeIn
        run(.sequence([fall, .run { [weak self] in self?.isHidden = true }]))
    }
}
