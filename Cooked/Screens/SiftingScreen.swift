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

class SiftOverlay: StationOverlay {
    
    // How hard the phone must be moving for it to count, measured in G.
    // About 0.35 is a gentle shake, 1.0 is vigorous.
    var shakeNeeded = 0.55
    
    // Lets you test on the simulator by holding a finger down instead of
    // shaking. Turn this off before you ship.
    var allowTapFallback = true
    
    // Working values.
    var shakeAmount = 0.0
    var isTapping = false
    
    // The object that reads the phone's motion sensors.
    let motionManager = CMMotionManager()
    
    // ---------------------------------------------------------------
    // READING THE PHONE'S MOVEMENT
    // ---------------------------------------------------------------
    
    override func setUpStation() {
        amountNeeded = 9.0
        hintWhenIdle = "Shake to sift"
        hintWhenWorking = "Keep shaking"
        prop.size = CGSize(width: 110, height: 10)
        
        startReadingMotion()
    }
    
    // Ask for a reading 60 times a second, matching the frame rate.
    func startReadingMotion() {
        // Device motion is not available on the simulator.
        if motionManager.isDeviceMotionAvailable == false { return }
        
        // Ask for a reading 60 times a second, matching the frame rate.
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        
        // The phone now calls this closure over and over with new data.
        motionManager.startDeviceMotionUpdates(to: OperationQueue.main) {
            motion, error in
            
            guard let motion = motion else { return }
            
            // userAcceleration is how much the player is moving the phone,
            // with gravity already taken out.
            let sideways = motion.userAcceleration.x
            let upDown = motion.userAcceleration.y
            let forward = motion.userAcceleration.z
            
            // Combine the three directions into one overall strength.
            let strength = sqrt(sideways * sideways
                                + upDown * upDown
                                + forward * forward)
            
            // Ease towards the new reading so the bar does not flicker.
            self.shakeAmount = self.shakeAmount + (strength - self.shakeAmount) * 0.4
        }
    }
    
    override func cleanUp() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    
    // Always switch the sensors off when this screen goes away, otherwise
    // they keep running and drain the battery.
    
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
    
    override func readInput(secondsSinceLastFrame: Double) {
        isWorking = shakeAmount >= shakeNeeded
        
        // On the simulator there is no motion, so holding a finger counts.
        if allowTapFallback && motionManager.isDeviceMotionAvailable == false {
            if isTapping {
                isWorking = true
            }
        }
        
        if isWorking {
            amountDone = amountDone + secondsSinceLastFrame
        }
    }
    
    override func animateProp(secondsSinceLastFrame: Double) {
        // Cap the wobble so a violent shake does not throw it off screen.
        var wobble = shakeAmount * 26
        if wobble > 22 {
            wobble = 22
        }
        
        // A random offset each frame reads as vibration.
        let offset = Double.random(in: -wobble...wobble)
        prop.position = CGPoint(x: centerX + offset, y: propRestY)
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
