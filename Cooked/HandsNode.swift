//
//  HandsNode.swift
//  Cooked
//
//  The chef's own two hands, drawn side by side in the bottom-left of the
//  kitchen map.
//
//  Left hand carries the ingredient or the prep you just made, right hand
//  carries the utensil. That split is not decoration: it is exactly the shape
//  of `PlayerInventory` (one ingredient slot, one utensil slot), so the hands
//  can never show a state the model can't hold.
//
//  They belong to the map and only the map. Inside a station screen the motion
//  is the whole picture, so the hands drop away entirely and come back — with
//  whatever you just made — once you're out in the kitchen again.
//
//  ⚠️ All art here is placeholder — a mitten of a palm and a coloured chip for
//  the item. `SKTexture` is used the moment an imageset named after the item id
//  exists ("strawberries", "knife"), same convention as `ArtIcon`.
//

import SpriteKit
import SwiftUI

@MainActor
final class HandsNode: SKNode {

    // MARK: Layout

    /// How far in from the left edge the first hand sits.
    private let inset: CGFloat = 52
    /// Gap between the two hands. Wide enough that the items they hold don't
    /// touch, tight enough that they read as one pair.
    private let spacing: CGFloat = 92
    /// How far the hands slide down when hidden — far enough to clear the item.
    private let dropDistance: CGFloat = 150

    private let leftHand: SKNode
    private let rightHand: SKNode

    /// The item chips currently drawn, so a repeat call can skip the rebuild.
    /// `refresh` runs every frame on the kitchen map; rebuilding two sprites at
    /// 60fps for a hand that hasn't changed is pure garbage collection work.
    private var shownPrep: String??
    private var shownUtensil: String??

    private let restY: CGFloat

    // MARK: Setup

    init(screenSize: CGSize) {
        leftHand = SKNode()
        rightHand = SKNode()
        restY = 46
        super.init()

        zPosition = 150

        layout(for: screenSize)

        // A slight splay so they read as a pair of hands coming up into frame
        // rather than two objects sitting in a row.
        leftHand.zRotation = 0.14
        rightHand.zRotation = -0.14

        addChild(leftHand)
        addChild(rightHand)

        buildPalm(on: leftHand)
        buildPalm(on: rightHand)

        alpha = 0
        isHidden = true
        position = CGPoint(x: 0, y: -dropDistance)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// Both hands live in the bottom-left, so this doesn't depend on the screen
    /// width — but it stays a function of the size because the scene is built
    /// at the safe-area size and resized to the view's real bounds afterwards,
    /// and the day either hand moves to an edge this is where it gets fixed.
    func layout(for screenSize: CGSize) {
        leftHand.position = CGPoint(x: inset, y: restY)
        rightHand.position = CGPoint(x: inset + spacing, y: restY)
    }

    /// The dummy hand itself: a rounded palm with a thumb. Replace this one
    /// function with a sprite and every screen gets the real art.
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
    func setItems(prep: String?, utensil: String?) {
        if shownPrep != .some(prep) {
            shownPrep = .some(prep)
            setItem(prep, on: leftHand)
        }
        if shownUtensil != .some(utensil) {
            shownUtensil = .some(utensil)
            setItem(utensil, on: rightHand)
        }
    }

    private func setItem(_ id: String?, on hand: SKNode) {
        hand.childNode(withName: "item")?.removeFromParent()
        guard let id else { return }

        let item = SKNode()
        item.name = "item"
        item.position = CGPoint(x: 0, y: 44)

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
