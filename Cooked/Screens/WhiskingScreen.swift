//
//  WhiskingScreen.swift
//  Cooked
//
//  Created by Keira on 12/08/26.
//

import SpriteKit

// The whisking station screen.
//
// The player swipes in circles. A progress bar fills up while they are
// circling, and stops when they stop. When the bar is full, the action is done.

class WhiskOverlay: SKNode {

    // ---------------------------------------------------------------
    // SETTINGS - change these numbers to make the action feel different
    // ---------------------------------------------------------------

    // How many seconds of circling it takes to finish.
    var secondsNeeded = 5.5

    // How fast the player must circle for it to count.
    // Bigger number = they must swipe faster.
    var speedNeeded = 1.5

    // This gets called when the player finishes.
    var whenFinished: (() -> Void)?

    // ---------------------------------------------------------------
    // THINGS THE SCREEN SHOWS
    // ---------------------------------------------------------------

    let background = SKSpriteNode()
    let titleLabel = SKLabelNode(fontNamed: "SFProText-Bold")
    let barBackground = SKSpriteNode()
    let barFill = SKSpriteNode()
    let hintLabel = SKLabelNode(fontNamed: "SFProText-Regular")

    // ---------------------------------------------------------------
    // THINGS THAT CHANGE WHILE PLAYING
    // ---------------------------------------------------------------

    var secondsDone = 0.0          // how much progress so far
    var isFinished = false         // did the player complete it
    var isTouching = false         // is a finger on the screen

    var previousAngle = 0.0        // where the finger was last frame
    var hasPreviousAngle = false   // do we have a valid previous angle yet
    var turnDirection = -1.0      // 1 = clockwise, -1 = anticlockwise
    var turnedThisFrame = 0.0      // how far they turned since last frame
    var currentSpeed = 0.0         // how fast they are circling right now

    // Where the middle of the screen is.
    var centerX = 0.0
    var centerY = 0.0

    // How wide the progress bar is.
    var barWidth = 300.0

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

        // The name of the action, above the bar.
        titleLabel.text = actionName
        titleLabel.fontSize = 24
        titleLabel.fontColor = SKColor.white
        titleLabel.position = CGPoint(x: centerX, y: centerY + 40)
        addChild(titleLabel)

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
        hintLabel.text = "Swipe in circles"
        hintLabel.fontSize = 13
        hintLabel.fontColor = SKColor(white: 0.55, alpha: 1)
        hintLabel.position = CGPoint(x: centerX, y: centerY - 46)
        addChild(hintLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    // ---------------------------------------------------------------
    // HELPERS
    // ---------------------------------------------------------------

    // Turns a touch position into an angle around the centre of the screen.
    func angleOf(_ touch: UITouch) -> Double {
        let point = touch.location(in: self)
        let acrossX = Double(point.x) - centerX
        let acrossY = Double(point.y) - centerY
        return atan2(acrossY, acrossX)
    }

    // How far the touch is from the centre of the screen.
    func distanceFromCenter(_ touch: UITouch) -> Double {
        let point = touch.location(in: self)
        let acrossX = Double(point.x) - centerX
        let acrossY = Double(point.y) - centerY
        return sqrt(acrossX * acrossX + acrossY * acrossY)
    }

    // ---------------------------------------------------------------
    // WHEN THE PLAYER TOUCHES THE SCREEN
    // ---------------------------------------------------------------

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isFinished { return }
        guard let touch = touches.first else { return }

        isTouching = true
        previousAngle = angleOf(touch)
        hasPreviousAngle = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isFinished { return }
        if isTouching == false { return }
        guard let touch = touches.first else { return }

        

        let newAngle = angleOf(touch)

        // If we have no previous angle to compare with, just save this one.
        if hasPreviousAngle == false {
            previousAngle = newAngle
            hasPreviousAngle = true
            return
        }

        // How much the angle changed since last time.
        var change = newAngle - previousAngle
        previousAngle = newAngle

        // Angles wrap around from +pi to -pi. When that happens the change
        // looks huge even though the finger barely moved, so fix it here.
        if change > Double.pi {
            change = change - 2 * Double.pi
        }
        if change < -Double.pi {
            change = change + 2 * Double.pi
        }

        // The first real movement decides which way counts as forwards.
        if turnDirection == 0 && abs(change) > 0.05 {
            if change > 0 {
                turnDirection = 1
            } else {
                turnDirection = -1
            }
        }

        // Multiplying by the direction makes going the chosen way positive
        // and going back negative. Only forward turning is added, so
        // scrubbing back and forth gets the player nowhere.
        let forwardTurn = change * turnDirection
        if forwardTurn > 0 {
            turnedThisFrame = turnedThisFrame + forwardTurn
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        hasPreviousAngle = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        hasPreviousAngle = false
    }

    // ---------------------------------------------------------------
    // RUNS EVERY FRAME
    // ---------------------------------------------------------------

    // The scene calls this about 60 times a second.
    // secondsSinceLastFrame is the tiny gap between frames.
    func update(secondsSinceLastFrame: Double) {

        if isFinished { return }
        if secondsSinceLastFrame <= 0 { return }

        // Turning amount divided by time gives us a speed.
        let speedRightNow = turnedThisFrame / secondsSinceLastFrame
        turnedThisFrame = 0

        // Blend the new speed into the old one so the bar does not flicker.
        currentSpeed = currentSpeed + (speedRightNow - currentSpeed) * 0.35

        // The player counts as whisking if a finger is down AND they are
        // circling fast enough.
        var isWhisking = false
        if isTouching && currentSpeed >= speedNeeded {
            isWhisking = true
        }

        // Only add progress while they are actually whisking.
        if isWhisking {
            secondsDone = secondsDone + secondsSinceLastFrame
            barFill.color = colorMoving
            hintLabel.text = "Keep going"
        } else {
            barFill.color = colorStopped
            hintLabel.text = "Swipe in circles"
        }

        updateBar()

        if secondsDone >= secondsNeeded {
            finish()
        }
    }

    // Makes the coloured bar match the progress.
    func updateBar() {
        var howFull = secondsDone / secondsNeeded
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
        secondsDone = secondsNeeded
        updateBar()

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

class WhiskPreviewScene: SKScene {

    var overlay: WhiskOverlay?
    var timeOfLastFrame = 0.0

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        showWhiskScreen()
    }

    func showWhiskScreen() {
        overlay?.removeFromParent()

        let newOverlay = WhiskOverlay(screenSize: size, actionName: "Whip the cream")

        // When it finishes, wait a moment and show it again so you can retry.
        newOverlay.whenFinished = {
            let wait = SKAction.wait(forDuration: 0.6)
            let again = SKAction.run {
                self.showWhiskScreen()
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

#Preview("Whisk station") {
    GeometryReader { geometry in
        SpriteView(scene: {
            let scene = WhiskPreviewScene(size: geometry.size)
            scene.scaleMode = .resizeFill
            return scene
        }())
        .ignoresSafeArea()
    }
}
#endif
