//
//  SiftingScreen.swift
//  Cooked
//

import SpriteKit
import CoreMotion

// The sifting station screen.
//
// The player shakes the phone, like shaking a sieve. A progress bar fills up
// while the phone is moving hard enough, and stops when they stop.
//
// This uses CoreMotion, which only works on a real device. The simulator has
// no accelerometer, so there is a tap fallback further down for testing.

class SiftOverlay: SKNode {

    // ---------------------------------------------------------------
    // SETTINGS - change these numbers to make the action feel different
    // ---------------------------------------------------------------

    // How many seconds of shaking it takes to finish.
    var secondsNeeded = 5.0

    // How hard the phone must be moving for it to count.
    // Measured in G. About 0.35 is a gentle shake, 1.0 is vigorous.
    var shakeNeeded = 0.55

    // Lets you test on the simulator by tapping instead of shaking.
    // Turn this off before you ship.
    var allowTapFallback = true

    // This gets called when the player finishes.
    var whenFinished: (() -> Void)?

    // ---------------------------------------------------------------
    // THINGS THE SCREEN SHOWS
    // ---------------------------------------------------------------

    let background = SKSpriteNode()
    let titleLabel = SKLabelNode(fontNamed: "SFProText-Bold")
    let sieve = SKSpriteNode()
    let barBackground = SKSpriteNode()
    let barFill = SKSpriteNode()
    let hintLabel = SKLabelNode(fontNamed: "SFProText-Regular")

    // ---------------------------------------------------------------
    // THINGS THAT CHANGE WHILE PLAYING
    // ---------------------------------------------------------------

    var secondsDone = 0.0          // how much progress so far
    var isFinished = false         // did the player complete it

    var shakeAmount = 0.0          // how hard the phone is moving right now
    var isTapping = false          // simulator fallback: is a finger down

    // Where the middle of the screen is.
    var centerX = 0.0
    var centerY = 0.0

    // How wide the progress bar is.
    var barWidth = 300.0

    // Where the sieve sits when it is resting.
    var sieveRestY = 0.0

    // Colours.
    let colorMoving = SKColor(.orange)
    let colorStopped = SKColor(.red)
    let colorDone = SKColor(.green)

    // This is the object that reads the phone's motion sensors.
    let motionManager = CMMotionManager()

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

        // A simple bar standing in for the sieve. Swap for artwork later.
        sieveRestY = centerY + 26
        sieve.color = SKColor.white
        sieve.size = CGSize(width: 110, height: 10)
        sieve.position = CGPoint(x: centerX, y: sieveRestY)
        addChild(sieve)

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
        hintLabel.text = "Shake to sift"
        hintLabel.fontSize = 13
        hintLabel.fontColor = SKColor(white: 0.55, alpha: 1)
        hintLabel.position = CGPoint(x: centerX, y: centerY - 46)
        addChild(hintLabel)

        startReadingMotion()
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    // ---------------------------------------------------------------
    // READING THE PHONE'S MOVEMENT
    // ---------------------------------------------------------------

    func startReadingMotion() {
        // Device motion is not available on the simulator.
        if motionManager.isDeviceMotionAvailable == false {
            return
        }

        // Ask for a reading 60 times a second, matching the frame rate.
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0

        // The phone will now call this closure over and over with new data.
        motionManager.startDeviceMotionUpdates(to: OperationQueue.main) {
            motion, error in

            guard let motion = motion else { return }

            // userAcceleration is how much the player is moving the phone,
            // with gravity already taken out. It has an x, y and z part.
            let sideways = motion.userAcceleration.x
            let upDown = motion.userAcceleration.y
            let forward = motion.userAcceleration.z

            // Combine the three into one number: the overall strength of
            // the movement, whichever direction it is in.
            let strength = sqrt(sideways * sideways
                                + upDown * upDown
                                + forward * forward)

            // Ease towards the new reading so the bar does not flicker.
            self.shakeAmount = self.shakeAmount + (strength - self.shakeAmount) * 0.4
        }
    }

    func stopReadingMotion() {
        motionManager.stopDeviceMotionUpdates()
    }

    // Always switch the sensors off when this screen goes away, otherwise
    // they keep running and drain the battery.
    deinit {
        stopReadingMotion()
    }

    // ---------------------------------------------------------------
    // SIMULATOR FALLBACK
    // ---------------------------------------------------------------

    // Holding a finger down pretends the phone is being shaken, so the
    // screen can be tested without a real device.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTapping = true
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTapping = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTapping = false
    }

    // ---------------------------------------------------------------
    // RUNS EVERY FRAME
    // ---------------------------------------------------------------

    // The scene calls this about 60 times a second.
    // secondsSinceLastFrame is the tiny gap between frames.
    func update(secondsSinceLastFrame: Double) {

        if isFinished { return }
        if secondsSinceLastFrame <= 0 { return }

        // Work out whether the phone is being shaken hard enough.
        var isSifting = false
        if shakeAmount >= shakeNeeded {
            isSifting = true
        }

        // On the simulator there is no motion, so holding a finger counts.
        if allowTapFallback && motionManager.isDeviceMotionAvailable == false {
            if isTapping {
                isSifting = true
            }
        }

        // Only add progress while they are actually sifting.
        if isSifting {
            secondsDone = secondsDone + secondsSinceLastFrame
            barFill.color = colorMoving
            hintLabel.text = "Keep shaking"
        } else {
            barFill.color = colorStopped
            hintLabel.text = "Shake to sift"
        }

        updateSieve()
        updateBar()

        if secondsDone >= secondsNeeded {
            finish()
        }
    }

    // Wobbles the sieve from side to side based on how hard the phone moves.
    func updateSieve() {
        // Cap the wobble so a violent shake does not throw it off screen.
        var wobble = shakeAmount * 26
        if wobble > 22 {
            wobble = 22
        }

        // A random offset each frame reads as vibration.
        let offset = Double.random(in: -wobble...wobble)
        sieve.position = CGPoint(x: centerX + offset, y: sieveRestY)
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

        stopReadingMotion()

        sieve.position = CGPoint(x: centerX, y: sieveRestY)
        sieve.color = colorDone
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

class SiftPreviewScene: SKScene {

    var overlay: SiftOverlay?
    var timeOfLastFrame = 0.0

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        showSiftScreen()
    }

    func showSiftScreen() {
        overlay?.removeFromParent()

        let newOverlay = SiftOverlay(screenSize: size, actionName: "Sift the flour")

        // When it finishes, wait a moment and show it again so you can retry.
        newOverlay.whenFinished = {
            let wait = SKAction.wait(forDuration: 0.6)
            let again = SKAction.run {
                self.showSiftScreen()
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

#Preview("Sift station") {
    GeometryReader { geometry in
        SpriteView(scene: {
            let scene = SiftPreviewScene(size: geometry.size)
            scene.scaleMode = .resizeFill
            return scene
        }())
        .ignoresSafeArea()
    }
}
#endif
