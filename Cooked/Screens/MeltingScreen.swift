//
//  Untitled.swift
//  Cooked
//
//  Created by Keira on 14/08/26.
//
//
//  Melting butter: the player slides the butter back and forth across the pan.
//
//  The butter follows the finger. Progress fills while it is being moved
//  fast enough, and stops when the finger stops, the same way whisking works.
//

import SpriteKit
import SwiftUI


class MeltOverlay: StationOverlay {

    // ---- Settings ----

    // How fast the butter must be moving for it to count, in points per second.
    var speedNeeded = 90.0

    // How far the butter can slide either side of the middle.
    var slideRange = 110.0

    // ---- Things this screen shows ----

    let pan = SKSpriteNode()

    // ---- Working values ----

    var isTouching = false
    var previousX = 0.0
    var hasPreviousX = false
    var movedThisFrame = 0.0
    var currentSpeed = 0.0

    // Where the butter currently sits, measured from the middle.
    var butterOffset = 0.0

    // ---------------------------------------------------------------
    // SETUP
    // ---------------------------------------------------------------

    override func setUpStation() {
        amountNeeded = 5.0          // seconds of sliding
        hintWhenIdle = "Slide the butter"
        hintWhenWorking = "Keep sliding"
        hintWhenDone = "Melted"

        // A pan for the butter to slide around in. Swap for artwork later.
        pan.color = SKColor(white: 0.20, alpha: 1)
        pan.size = CGSize(width: slideRange * 2 + 70, height: 70)
        pan.position = CGPoint(x: centerX, y: propRestY)
        pan.zPosition = -1
        addChild(pan)

        // The base class prop is the butter.
        prop.size = CGSize(width: 46, height: 34)
        prop.color = SKColor(.yellow)
    }

    // ---------------------------------------------------------------
    // TOUCHES
    // ---------------------------------------------------------------

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isFinished { return }
        guard let touch = touches.first else { return }

        isTouching = true
        previousX = Double(touch.location(in: self).x)
        hasPreviousX = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isFinished { return }
        if isTouching == false { return }
        guard let touch = touches.first else { return }

        let newX = Double(touch.location(in: self).x)

        // No previous position to compare with yet, so just save this one.
        if hasPreviousX == false {
            previousX = newX
            hasPreviousX = true
            return
        }

        // How far the finger moved sideways since last time.
        let change = newX - previousX
        previousX = newX

        // Distance is always counted as positive, so sliding left and
        // sliding right both make progress.
        movedThisFrame = movedThisFrame + abs(change)

        // Move the butter along with the finger.
        butterOffset = butterOffset + change

        // Do not let it slide off the pan.
        if butterOffset < -slideRange { butterOffset = -slideRange }
        if butterOffset > slideRange { butterOffset = slideRange }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        hasPreviousX = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        hasPreviousX = false
    }

    // ---------------------------------------------------------------
    // EVERY FRAME
    // ---------------------------------------------------------------

    override func readInput(secondsSinceLastFrame: Double) {

        // Distance moved divided by time gives us a speed.
        let speedRightNow = movedThisFrame / secondsSinceLastFrame
        movedThisFrame = 0

        // Blend the new speed into the old one so the bar does not flicker.
        currentSpeed = currentSpeed + (speedRightNow - currentSpeed) * 0.35

        // Counts as melting if a finger is down AND it is moving fast enough.
        isWorking = isTouching && currentSpeed >= speedNeeded

        if isWorking {
            amountDone = amountDone + secondsSinceLastFrame
        }
    }

    override func animateProp(secondsSinceLastFrame: Double) {

        // Slide the butter to wherever the finger dragged it.
        prop.position = CGPoint(x: centerX + butterOffset, y: propRestY)

        // Shrink it as it melts, so the progress is visible on the butter too.
        let howFull = amountDone / amountNeeded
        let shrink = 1 - howFull * 0.55
        prop.xScale = CGFloat(shrink)
        prop.yScale = CGFloat(shrink)
    }
}

class MeltPreviewScene: SKScene {
    
    var overlay: MeltOverlay!
    var timeOfLastFrame = 0.0
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        showWhiskScreen()
    }
    
    func showWhiskScreen() {
        overlay?.removeFromParent()
        
        let newOverlay = MeltOverlay(screenSize: size, actionName: "Melt the Butter")
        
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

#Preview("Melting") {
    GeometryReader { geometry in
        SpriteView(scene: {
            let scene = MeltPreviewScene(size: geometry.size)
            scene.scaleMode = .resizeFill
            return scene
        }())
        .ignoresSafeArea()
    }
}
#endif
