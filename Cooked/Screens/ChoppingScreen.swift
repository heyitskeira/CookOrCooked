//
//  ChoppingScreen.swift
//  Cooked
//

import SpriteKit

// The chopping station screen.
//
// The player taps repeatedly. Each tap is one chop. A progress bar fills up
// as chops land. When the bar is full, the action is done.

class ChopOverlay: SKNode {

    // ---------------------------------------------------------------
    // SETTINGS - change these numbers to make the action feel different
    // ---------------------------------------------------------------

    // How many taps it takes to finish.
    var tapsNeeded = 8.0

    // Shortest allowed gap between taps, in seconds. Anything faster is
    // ignored, so two fingers mashing cannot double the speed.
    var minimumGap = 0.06

    // How much progress bleeds away each second when the player stops.
    // Set to 0 if you want progress to simply hold.
    var decayPerSecond = 0.0

    // This gets called when the player finishes.
    var whenFinished: (() -> Void)?

    // ---------------------------------------------------------------
    // THINGS THE SCREEN SHOWS
    // ---------------------------------------------------------------

    let background = SKSpriteNode()
    let titleLabel = SKLabelNode(fontNamed: "SFProText-Bold")
    let knife = SKSpriteNode()
    let barBackground = SKSpriteNode()
    let barFill = SKSpriteNode()
    let hintLabel = SKLabelNode(fontNamed: "SFProText-Regular")

    // ---------------------------------------------------------------
    // THINGS THAT CHANGE WHILE PLAYING
    // ---------------------------------------------------------------

    var tapsDone = 0.0             // how much progress so far
    var isFinished = false         // did the player complete it
    var isFingerDown = false       // is a finger currently held down

    var secondsSinceLastTap = 999.0  // used to block taps that are too fast
    var tapLandedThisFrame = false   // a tap happened, so the knife should jolt
    var knifeKick = 0.0              // 1 right after a tap, eases back to 0

    // Where the middle of the screen is.
    var centerX = 0.0
    var centerY = 0.0

    // How wide the progress bar is.
    var barWidth = 300.0

    // Where the knife sits when it is resting.
    var knifeRestY = 0.0

    // Colours.
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

        // A simple bar standing in for the knife. Swap for artwork later.
        knifeRestY = centerY + 26
        knife.color = SKColor.white
        knife.size = CGSize(width: 90, height: 8)
        knife.position = CGPoint(x: centerX, y: knifeRestY)
        addChild(knife)

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
        barFill.color = colorMoving
        barFill.size = CGSize(width: barWidth, height: 10)
        barFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        barFill.position = CGPoint(x: centerX - barWidth / 2, y: centerY - 6)
        barFill.xScale = 0.0001
        addChild(barFill)

        // The hint at the bottom.
        hintLabel.text = "Tap to chop"
        hintLabel.fontSize = 13
        hintLabel.fontColor = SKColor(white: 0.55, alpha: 1)
        hintLabel.position = CGPoint(x: centerX, y: centerY - 46)
        addChild(hintLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    // ---------------------------------------------------------------
    // WHEN THE PLAYER TOUCHES THE SCREEN
    // ---------------------------------------------------------------

    // A chop lands the moment the finger goes down, not when it lifts,
    // because that feels more responsive.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isFinished { return }

        // A finger is already held down, so this is not a fresh tap.
        if isFingerDown { return }
        isFingerDown = true

        // Too soon after the last chop, so ignore it.
        if secondsSinceLastTap < minimumGap { return }

        secondsSinceLastTap = 0
        tapsDone = tapsDone + 1
        tapLandedThisFrame = true
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isFingerDown = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isFingerDown = false
    }

    // ---------------------------------------------------------------
    // RUNS EVERY FRAME
    // ---------------------------------------------------------------

    // The scene calls this about 60 times a second.
    // secondsSinceLastFrame is the tiny gap between frames.
    func update(secondsSinceLastFrame: Double) {

        if isFinished { return }
        if secondsSinceLastFrame <= 0 { return }

        // Keep track of how long it has been since the last chop.
        secondsSinceLastTap = secondsSinceLastTap + secondsSinceLastFrame

        // A tap just landed, so kick the knife.
        if tapLandedThisFrame {
            knifeKick = 1.0
            tapLandedThisFrame = false
        }

        // Ease the kick back down to zero over about a fifth of a second.
        knifeKick = knifeKick - secondsSinceLastFrame * 5
        if knifeKick < 0 {
            knifeKick = 0
        }

        // Bleed progress away if the player has stopped chopping.
        if decayPerSecond > 0 {
            tapsDone = tapsDone - decayPerSecond * secondsSinceLastFrame
            if tapsDone < 0 {
                tapsDone = 0
            }
        }

        // The bar is orange while they are chopping, red once they pause.
        if secondsSinceLastTap < 0.6 {
            barFill.color = colorMoving
            hintLabel.text = "Keep chopping"
        } else {
            barFill.color = colorStopped
            hintLabel.text = "Tap to chop"
        }

        updateKnife()
        updateBar()

        if tapsDone >= tapsNeeded {
            finish()
        }
    }

    // Drops the knife down and squashes it slightly on each chop.
    func updateKnife() {
        knife.position = CGPoint(x: centerX, y: knifeRestY - knifeKick * 14)
        knife.xScale = CGFloat(1 + knifeKick * 0.25)
    }

    // Makes the coloured bar match the progress.
    func updateBar() {
        var howFull = tapsDone / tapsNeeded
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
        tapsDone = tapsNeeded
        updateBar()

        knife.position = CGPoint(x: centerX, y: knifeRestY)
        knife.xScale = 1
        knife.color = colorDone
        barFill.color = colorDone
        hintLabel.text = "Done"

        let wait = SKAction.wait(forDuration: 0.35)
        let callBack = SKAction.run {
            self.whenFinished?()
        }
        run(SKAction.sequence([wait, callBack]))
    }
}


// ===================================================================
// PREVIEW - lets you try this screen on its own in Xcode
// ===================================================================

class ChopPreviewScene: SKScene {

    var overlay: ChopOverlay?
    var timeOfLastFrame = 0.0

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        showChopScreen()
    }

    func showChopScreen() {
        overlay?.removeFromParent()

        let newOverlay = ChopOverlay(screenSize: size, actionName: "Cut strawberries")

        // When it finishes, wait a moment and show it again so you can retry.
        newOverlay.whenFinished = {
            let wait = SKAction.wait(forDuration: 0.6)
            let again = SKAction.run {
                self.showChopScreen()
            }
            self.run(SKAction.sequence([wait, again]))
        }

        addChild(newOverlay)
        overlay = newOverlay
    }

    override func update(_ currentTime: TimeInterval) {
        if timeOfLastFrame == 0 {
            timeOfLastFrame = currentTime
        }

        var gap = currentTime - timeOfLastFrame
        if gap > 0.1 {
            gap = 0.1
        }
        timeOfLastFrame = currentTime

        overlay?.update(secondsSinceLastFrame: gap)
    }
}

#if DEBUG
import SwiftUI

#Preview("Chop station") {
    GeometryReader { geometry in
        SpriteView(scene: {
            let scene = ChopPreviewScene(size: geometry.size)
            scene.scaleMode = .resizeFill
            return scene
        }())
        .ignoresSafeArea()
    }
}
#endif
