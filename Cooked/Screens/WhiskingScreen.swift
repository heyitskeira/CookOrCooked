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

class WhiskOverlay: StationOverlay {
    
    // How fast the player must circle for it to count.
    var speedNeeded = 1.5
    
    // Touches closer than this to the middle are ignored, because tiny
    // movements near the centre swing the angle wildly.
    var centerSize = 34.0
    var isTouching = false
    var previousAngle = 0.0
    var hasPreviousAngle = false
    var turnDirection = 0.0
    var turnedThisFrame = 0.0
    var currentSpeed = 0.0
    
    
    
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
    
    override func setUpStation() {
        amountNeeded = 5.5          // seconds of circling
        hintWhenIdle = "Swipe in circles"
        prop.size = CGSize(width: 100, height: 9)
    }
    
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
    
    override func readInput(secondsSinceLastFrame: Double) {
        // Turning amount divided by time gives us a speed.
        let speedRightNow = turnedThisFrame / secondsSinceLastFrame
        turnedThisFrame = 0
        
        // Blend the new speed into the old one so the bar does not flicker.
        currentSpeed = currentSpeed + (speedRightNow - currentSpeed) * 0.35
        
        // The player counts as whisking if a finger is down AND they are
        // circling fast enough.
        isWorking = isTouching && currentSpeed >= speedNeeded
        
        if isWorking {
            amountDone = amountDone + secondsSinceLastFrame
        }
    }
    
}


//only for preview, can delete later
class WhiskPreviewScene: SKScene {
    
    var overlay: WhiskOverlay!
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
