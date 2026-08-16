//
//  StationOverlay.swift
//  Cooked
//
//  Created by Keira on 14/08/26.
//
//  The shared base for every station screen.
//
//  It holds everything the stations have in common: the background, the
//  title, the prop in the middle, the progress bar, the hint text, and the
//  finishing behaviour.
//
//  It does NOT know how the player makes progress. Each station file says
//  that for itself by overriding the four hooks near the bottom.
//

import SpriteKit
import SwiftUI


class StationOverlay: SKNode {
    // ---- Settings every station has ----

    // How much work the action takes. For whisking and sifting this is
    // seconds. For chopping it is taps. The bar does not care which.
    var amountNeeded = 4.0

    // This gets called when the player finishes.
    var whenFinished: (() -> Void)?

    // ---- Things the screen shows ----

    let background = SKSpriteNode()
    let titleLabel = SKLabelNode(fontNamed: "SFProText-Bold")
    let barBackground = SKSpriteNode()
    let barFill = SKSpriteNode()
    let hintLabel = SKLabelNode(fontNamed: "SFProText-Regular")

    // The prop in the middle: a whisk, a knife, a sieve. Each station
    // moves this its own way.
    let prop = SKSpriteNode()

    // ---- Things that change while playing ----

    var amountDone = 0.0        // how much progress so far
    var isFinished = false      // did the player complete it
    var isWorking = false       // is the player actively doing the action

    // Where the middle of the screen is.
    var centerX = 0.0
    var centerY = 0.0

    // How wide the progress bar is.
    var barWidth = 300.0

    // Where the prop sits when it is resting.
    var propRestY = 0.0

    // ---- Words each station changes ----

    var hintWhenIdle = "Get to work"
    var hintWhenWorking = "Keep going"
    var hintWhenDone = "Done"

    // ---- Colours ----

    let colorMoving = SKColor(.orange)
    let colorStopped = SKColor(.red)
    let colorDone = SKColor(.green)

    // ---------------------------------------------------------------
    // SETTING UP THE SCREEN
    // ---------------------------------------------------------------

    init(screenSize: CGSize, actionName: String) {
        super.init()

        centerX = Double(screenSize.width) / 2
        centerY = Double(screenSize.height) / 2

        isUserInteractionEnabled = true
        zPosition = 100

        // Dark background covering everything. change with design
        background.color = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        background.size = screenSize
        background.position = CGPoint(x: centerX, y: centerY)
        addChild(background)

        // The name of the action, above everything else.
        titleLabel.text = actionName
        titleLabel.fontSize = 24
        titleLabel.fontColor = SKColor.white
        titleLabel.position = CGPoint(x: centerX, y: centerY + 70)
        addChild(titleLabel)

        // A plain bar standing in for the prop. Swap for artwork later.
        propRestY = centerY + 26
        prop.color = SKColor.white
        prop.size = CGSize(width: 100, height: 9)
        prop.position = CGPoint(x: centerX, y: propRestY)
        addChild(prop)

        // Make the bar fit smaller screens.
        if barWidth > Double(screenSize.width) - 80 {
            barWidth = Double(screenSize.width) - 80
        }

        // The grey empty bar.
        barBackground.color = SKColor(white: 0.24, alpha: 1)
        barBackground.size = CGSize(width: barWidth, height: 10)
        barBackground.position = CGPoint(x: centerX, y: centerY - 6)
        addChild(barBackground)

        // The coloured bar that fills up.
        // anchorPoint on the left means it grows to the right.
        barFill.color = colorStopped
        barFill.size = CGSize(width: barWidth, height: 10)
        barFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        barFill.position = CGPoint(x: centerX - barWidth / 2, y: centerY - 6)
        barFill.xScale = 0.0001
        addChild(barFill)

        // The hint at the bottom.
        hintLabel.fontSize = 13
        hintLabel.fontColor = SKColor(white: 0.55, alpha: 1)
        hintLabel.position = CGPoint(x: centerX, y: centerY - 46)
        addChild(hintLabel)

        // Let the station set its own wording and settings.
        setUpStation()
        hintLabel.text = hintWhenIdle
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    // ---------------------------------------------------------------
    // THINGS EACH STATION FILLS IN
    // ---------------------------------------------------------------

    // Runs once at the end of setup. Use it to change the hint words,
    // the amount needed, or the look of the prop.
    func setUpStation() {
    }

    // Runs every frame. Each station works out whether the player is
    // doing the action, sets isWorking, and adds to amountDone.
    func readInput(secondsSinceLastFrame: Double) {
    }

    // Runs every frame, after readInput. Move the prop here.
    func animateProp(secondsSinceLastFrame: Double) {
    }

    // Runs when the screen is finished or closed. Use it to switch off
    // anything still running, like the motion sensors.
    func cleanUp() {
    }

    // ---------------------------------------------------------------
    // RUNS EVERY FRAME
    // ---------------------------------------------------------------

    // The scene calls this about 60 times a second.
    // secondsSinceLastFrame is the tiny gap between frames.
    func update(secondsSinceLastFrame: Double) {

        if isFinished { return }
        if secondsSinceLastFrame <= 0 { return }

        // Ask the station what the player is doing.
        readInput(secondsSinceLastFrame: secondsSinceLastFrame)
        animateProp(secondsSinceLastFrame: secondsSinceLastFrame)

        // Colour and wording follow whether they are working.
        if isWorking {
            barFill.color = colorMoving
            hintLabel.text = hintWhenWorking
        } else {
            barFill.color = colorStopped
            hintLabel.text = hintWhenIdle
        }

        updateBar()

        if amountDone >= amountNeeded {
            finish()
        }
    }

    // Makes the coloured bar match the progress.
    func updateBar() {
        var howFull = amountDone / amountNeeded
        if howFull > 1 {
            howFull = 1
        }
        if howFull < 0.0001 {
            howFull = 0.0001
        }
        barFill.xScale = CGFloat(howFull)
    }

    func finish() {
        isFinished = true
        isUserInteractionEnabled = false
        amountDone = amountNeeded
        updateBar()

        cleanUp()

        prop.position = CGPoint(x: centerX, y: propRestY)
        prop.xScale = 1
        prop.color = colorDone
        barFill.color = colorDone
        hintLabel.text = hintWhenDone

        let wait = SKAction.wait(forDuration: 0.35)
        let callBack = SKAction.run {
            self.whenFinished?()
        }
        run(SKAction.sequence([wait, callBack]))
    }
}
