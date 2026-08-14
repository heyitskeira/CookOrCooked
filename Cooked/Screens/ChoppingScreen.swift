//
//  ChoppingScreen.swift
//  Cooked
//

import SpriteKit

// The chopping station screen.
//
// The player taps repeatedly. Each tap is one chop. A progress bar fills up
// as chops land. When the bar is full, the action is done.

class ChopOverlay: StationOverlay {
    
    var isFingerDown = false
    var secondsSinceLastTap = 999.0
    var tapLandedThisFrame = false
    var propKick = 0.0
    var minimumGap = 0.08
    
    
    // ---------------------------------------------------------------
    // WHEN THE PLAYER TOUCHES THE SCREEN
    // ---------------------------------------------------------------
    
    // A chop lands the moment the finger goes down, not when it lifts,
    // because that feels more responsive.
    
    override func setUpStation() {
        amountNeeded = 7.0
        hintWhenIdle = "Tap to chop"
        hintWhenWorking = "Keep chopping"
        prop.size = CGSize(width: 90, height: 8)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isFinished { return }
        
        // A finger is already held down, so this is not a fresh tap.
        if isFingerDown { return }
        isFingerDown = true
        
        // Too soon after the last chop, so ignore it.
        if secondsSinceLastTap < minimumGap { return }
        
        secondsSinceLastTap = 0
        amountDone = amountDone + 1
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
    
    override func readInput(secondsSinceLastFrame: Double) {
        secondsSinceLastTap = secondsSinceLastTap + secondsSinceLastFrame
        
        // A tap just landed, so kick the prop.
        if tapLandedThisFrame {
            propKick = 1.0
            tapLandedThisFrame = false
        }
        
        // Counted as working if they chopped in the last moment or so.
        if secondsSinceLastTap < 0.6 {
            isWorking = true
        }
    }
}
    
    
    class ChopPreviewScene: SKScene {
        
        var overlay: ChopOverlay?
        var timeOfLastFrame = 0.0
        
        override func didMove(to view: SKView) {
            backgroundColor = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
            showChopScreen()
        }
        
        func showChopScreen() {
            overlay?.removeFromParent()
            
            let newOverlay = ChopOverlay(screenSize: size, actionName: "Chop strawberries")
            
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
