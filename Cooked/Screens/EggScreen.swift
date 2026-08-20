//
//  EggScreen.swift
//  Cooked
//
//  Created by Keira on 15/08/26.
//
//  Cracking an egg, in two beats.
//
//  Beat one: flick the phone sharply downward to crack the shell. Flicking
//  too gently or too hard just tells the player and lets them try again.
//
//  Beat two: put two fingers on the screen and spread them apart to pull
//  the shell open.
//
//  This is the only station with two separate phases, so it plays quite
//  differently from the fill-a-bar stations.
//
//  Uses CoreMotion, which needs a real device. There is a tap fallback for
//  the simulator.
//

import SpriteKit
import CoreMotion
import SwiftUI


class EggOverlay: StationOverlay {

    // ---- Settings ----

    // How hard the flick has to be, measured in G.
    // Below the first number is too soft, above the second is too hard.
    var flickTooSoft = 1.3
    var flickTooHard = 3.2

    // How long to wait after a flick before listening for another one.
    // Stops a single flick registering several times.
    var flickCooldown = 0.7

    // How far apart the fingers must travel to open the shell, in points.
    var spreadNeeded = 130.0

    // How much of the progress bar the crack is worth. The rest is the
    // spreading. 0.35 means cracking fills the first third or so.
    var crackShare = 0.35

    // Lets you crack by tapping when there is no motion sensor.
    var allowTapFallback = true

    // ---- Things this screen shows ----

    let shellLeft = SKSpriteNode()
    let shellRight = SKSpriteNode()
    let yolk = SKSpriteNode()
    let feedbackLabel = SKLabelNode(fontNamed: "SFProText-Bold")

    // ---- Working values ----

    // Which beat we are on.
    var hasCracked = false

    // Flick detection.
    var shakeAmount = 0.0
    var peakThisFlick = 0.0
    var isInFlick = false
    var secondsSinceFlick = 999.0

    // Spreading.
    var activeTouches: [UITouch] = []
    var startingGap = 0.0
    var hasStartingGap = false
    var spreadSoFar = 0.0

    // How far apart the shell halves currently sit.
    var shellGap = 0.0

    let motionManager = CMMotionManager()

    let colorGood = SKColor(.green)
    let colorBad = SKColor(.red)

    // ---------------------------------------------------------------
    // SETUP
    // ---------------------------------------------------------------

    override func setUpStation() {
        amountNeeded = 1.0          // a share of the whole job, not seconds
        hintWhenIdle = "Flick down to crack"
        hintWhenWorking = "Keep going"
        hintWhenDone = "Cracked"

        // The base class prop is not used here.
        prop.isHidden = true

        buildEgg()
        startReadingMotion()
    }

    func buildEgg() {
        // Two halves of a shell, sitting together until the egg is opened.
        shellLeft.color = SKColor(white: 0.92, alpha: 1)
        shellLeft.size = CGSize(width: 54, height: 70)
        shellLeft.position = CGPoint(x: centerX - 27, y: propRestY)
        addChild(shellLeft)

        shellRight.color = SKColor(white: 0.86, alpha: 1)
        shellRight.size = CGSize(width: 54, height: 70)
        shellRight.position = CGPoint(x: centerX + 27, y: propRestY)
        addChild(shellRight)

        // The yolk, hidden behind the shell until it opens.
        yolk.color = SKColor(.yellow)
        yolk.size = CGSize(width: 40, height: 40)
        yolk.position = CGPoint(x: centerX, y: propRestY)
        yolk.zPosition = -1
        addChild(yolk)

        // Tells the player their flick was too soft or too hard.
        feedbackLabel.text = ""
        feedbackLabel.fontSize = 15
        feedbackLabel.fontColor = colorBad
        feedbackLabel.position = CGPoint(x: centerX, y: propRestY + 66)
        addChild(feedbackLabel)
    }

    // ---------------------------------------------------------------
    // READING THE PHONE'S MOVEMENT
    // ---------------------------------------------------------------

    func startReadingMotion() {
        if motionManager.isDeviceMotionAvailable == false { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0

        motionManager.startDeviceMotionUpdates(to: OperationQueue.main) {
            motion, error in

            guard let motion = motion else { return }

            let sideways = motion.userAcceleration.x
            let upDown = motion.userAcceleration.y
            let forward = motion.userAcceleration.z

            // One number for how hard the phone is being moved.
            // Not smoothed here, because a flick is a sharp spike and
            // smoothing would flatten the very thing we are looking for.
            self.shakeAmount = sqrt(sideways * sideways
                                    + upDown * upDown
                                    + forward * forward)
        }
    }

    override func cleanUp() {
        motionManager.stopDeviceMotionUpdates()
    }

    // ---------------------------------------------------------------
    // TOUCHES
    // ---------------------------------------------------------------

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isFinished { return }

        for touch in touches {
            activeTouches.append(touch)
        }

        // Before the egg is cracked, a tap stands in for a flick when there
        // is no motion sensor to read.
        if hasCracked == false {
            if allowTapFallback && motionManager.isDeviceMotionAvailable == false {
                crack(strength: 2.0)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isFinished { return }
        if hasCracked == false { return }

        // Two fingers are needed to pull the shell apart.
        if activeTouches.count < 2 {
            hasStartingGap = false
            return
        }

        let first = activeTouches[0].location(in: self)
        let second = activeTouches[1].location(in: self)
        let gap = distanceBetween(first, second)

        // Remember how far apart the fingers started.
        if hasStartingGap == false {
            startingGap = gap
            hasStartingGap = true
            return
        }

        // How much further apart they are now than when they landed.
        let opened = gap - startingGap
        if opened > spreadSoFar {
            spreadSoFar = opened
        }
        if spreadSoFar > spreadNeeded {
            spreadSoFar = spreadNeeded
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        removeTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        removeTouches(touches)
    }

    func removeTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if let spot = activeTouches.firstIndex(of: touch) {
                activeTouches.remove(at: spot)
            }
        }
        if activeTouches.count < 2 {
            hasStartingGap = false
        }
    }

    // Straight line distance between two points.
    func distanceBetween(_ a: CGPoint, _ b: CGPoint) -> Double {
        let acrossX = Double(a.x) - Double(b.x)
        let acrossY = Double(a.y) - Double(b.y)
        return sqrt(acrossX * acrossX + acrossY * acrossY)
    }

    // ---------------------------------------------------------------
    // EVERY FRAME
    // ---------------------------------------------------------------

    override func readInput(secondsSinceLastFrame: Double) {

        secondsSinceFlick = secondsSinceFlick + secondsSinceLastFrame

        if hasCracked == false {
            watchForFlick(secondsSinceLastFrame: secondsSinceLastFrame)
            amountDone = 0
            isWorking = isInFlick
            hintWhenIdle = "Flick down to crack"
        } else {
            // Progress is the crack plus however far the shell has opened.
            let openedShare = (spreadSoFar / spreadNeeded) * (1 - crackShare)
            amountDone = crackShare + openedShare
            isWorking = activeTouches.count >= 2
            hintWhenIdle = "Two fingers, pull it open"
            hintWhenWorking = "Keep pulling"
        }
    }

    // Looks for a single sharp jolt, then judges how hard it was.
    func watchForFlick(secondsSinceLastFrame: Double) {

        // Still cooling down from the last attempt.
        if secondsSinceFlick < flickCooldown { return }

        // The movement is strong enough to be the start of a flick.
        if shakeAmount > flickTooSoft * 0.6 {
            isInFlick = true
            if shakeAmount > peakThisFlick {
                peakThisFlick = shakeAmount
            }
            return
        }

        // The movement has died down, so the flick is over. Judge the peak.
        if isInFlick {
            isInFlick = false
            let strength = peakThisFlick
            peakThisFlick = 0
            secondsSinceFlick = 0

            if strength < flickTooSoft {
                showFeedback("Too soft", good: false)
            } else if strength > flickTooHard {
                showFeedback("Too hard", good: false)
            } else {
                crack(strength: strength)
            }
        }
    }

    func crack(strength: Double) {
        hasCracked = true
        showFeedback("Cracked", good: true)
    }

    func showFeedback(_ words: String, good: Bool) {
        feedbackLabel.text = words
        if good {
            feedbackLabel.fontColor = colorGood
        } else {
            feedbackLabel.fontColor = colorBad
        }

        // Fade the message out after a moment.
        feedbackLabel.removeAllActions()
        feedbackLabel.alpha = 1
        let wait = SKAction.wait(forDuration: 0.9)
        let fade = SKAction.fadeOut(withDuration: 0.4)
        feedbackLabel.run(SKAction.sequence([wait, fade]))
    }

    override func animateProp(secondsSinceLastFrame: Double) {

        if hasCracked == false {
            // Wobble the egg while the phone is being moved.
            let wobble = shakeAmount * 4
            let offset = Double.random(in: -wobble...wobble)
            shellLeft.position = CGPoint(x: centerX - 27 + offset, y: propRestY)
            shellRight.position = CGPoint(x: centerX + 27 + offset, y: propRestY)
            return
        }

        // Once cracked, the halves slide apart as the fingers spread.
        shellGap = (spreadSoFar / spreadNeeded) * 60

        shellLeft.position = CGPoint(x: centerX - 27 - shellGap, y: propRestY)
        shellRight.position = CGPoint(x: centerX + 27 + shellGap, y: propRestY)

        // Tilt them a little, so it reads as opening rather than sliding.
        shellLeft.zRotation = CGFloat(-shellGap * 0.006)
        shellRight.zRotation = CGFloat(shellGap * 0.006)

        // The yolk swells into view as the shell opens.
        let show = 1 + (spreadSoFar / spreadNeeded) * 0.5
        yolk.xScale = CGFloat(show)
        yolk.yScale = CGFloat(show)
    }
}

class EggScreen: SKScene {
    
    var overlay: EggOverlay!
    var timeOfLastFrame = 0.0
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        showEggscreen()
    }
    
    func showEggscreen() {
        overlay?.removeFromParent()
        view?.isMultipleTouchEnabled = true
        
        let newOverlay = EggOverlay(screenSize: size, actionName: "Beat the Egg")
        
        // When it finishes, wait a moment and show it again so you can retry.
        newOverlay.whenFinished = {
            let wait = SKAction.wait(forDuration: 0.6)
            let again = SKAction.run {
                self.showEggscreen()
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

#Preview("Egg Breaks") {
    GeometryReader { geometry in
        SpriteView(scene: {
            let scene = EggScreen(size: geometry.size)
            scene.scaleMode = .resizeFill
            return scene
        }())
        .ignoresSafeArea()
    }
}
#endif
