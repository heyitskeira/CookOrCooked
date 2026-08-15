//
//  MixingScreen.swift
//  Cooked
//
//  Created by Keira on 15/08/26.
//
//  Mixing: the same circular swipe as whisking, but the phone rumbles like
//  a running mixer while the player stirs.
//
//  Because the motion is identical, this builds on WhiskOverlay instead of
//  repeating the angle maths. Everything below is only the mixer part.
//
//  Haptics need a real device. Nothing happens on the simulator, and the
//  station still plays normally without them.
//

import SpriteKit
import CoreHaptics


class MixOverlay: WhiskOverlay {

    // ---- Settings ----

    // How strong the rumble is at its weakest and strongest.
    // Both run from 0 to 1.
    var rumbleWeakest = 0.3
    var rumbleStrongest = 1.0

    // How fast the player has to stir to feel the strongest rumble.
    var speedForFullRumble = 4.0

    // ---- Haptics ----

    // The engine that produces the vibration.
    var hapticEngine: CHHapticEngine?

    // The thing actually playing the rumble. Kept running and turned up
    // or down, rather than started and stopped constantly.
    var rumblePlayer: CHHapticAdvancedPatternPlayer?

    var isRumbling = false

    // ---------------------------------------------------------------
    // SETUP
    // ---------------------------------------------------------------

    override func setUpStation() {
        // Take everything whisking sets up, then change what differs.
        super.setUpStation()

        amountNeeded = 7.0          // seconds of mixing
        hintWhenIdle = "Swipe in circles to mix"
        hintWhenWorking = "Mixing"
        hintWhenDone = "Mixed"

        prop.size = CGSize(width: 120, height: 12)

        prepareHaptics()
    }

    // ---------------------------------------------------------------
    // SETTING UP THE VIBRATION
    // ---------------------------------------------------------------

    func prepareHaptics() {
        // Older devices and the simulator cannot do this.
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics == false {
            return
        }

        hapticEngine = try? CHHapticEngine()

        // iOS sometimes shuts the engine down, for example after a phone
        // call. These two handlers start it again when that happens.
        hapticEngine?.stoppedHandler = { reason in
            self.isRumbling = false
        }
        hapticEngine?.resetHandler = {
            try? self.hapticEngine?.start()
            self.rumblePlayer = nil
        }

        try? hapticEngine?.start()

        makeRumblePlayer()
    }

    func makeRumblePlayer() {
        guard let engine = hapticEngine else { return }

        // How strong the vibration is.
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity,
                                               value: Float(rumbleWeakest))

        // How sharp it feels. Low values are a soft rumble, high values
        // are a crisp buzz. A motor is somewhere in the middle.
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness,
                                               value: 0.35)

        // A continuous event is a sustained buzz rather than a single tap.
        // The duration is long because the player loops it anyway.
        let event = CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: [intensity, sharpness],
                                  relativeTime: 0,
                                  duration: 30)

        let pattern = try? CHHapticPattern(events: [event], parameters: [])
        guard let pattern = pattern else { return }

        rumblePlayer = try? engine.makeAdvancedPlayer(with: pattern)
        rumblePlayer?.loopEnabled = true
    }

    // Turns the rumble on and sets how strong it is.
    func startRumble() {
        if isRumbling { return }
        try? rumblePlayer?.start(atTime: CHHapticTimeImmediate)
        isRumbling = true
    }

    func stopRumble() {
        if isRumbling == false { return }
        try? rumblePlayer?.stop(atTime: CHHapticTimeImmediate)
        isRumbling = false
    }

    // Changes the strength of a rumble that is already playing, without
    // stopping and restarting it.
    func setRumbleStrength(_ amount: Double) {
        var value = amount
        if value < 0 { value = 0 }
        if value > 1 { value = 1 }

        let strength = rumbleWeakest + (rumbleStrongest - rumbleWeakest) * value

        let change = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: Float(strength),
            relativeTime: 0)

        try? rumblePlayer?.sendParameters([change], atTime: CHHapticTimeImmediate)
    }

    // Always switch the engine off when the screen closes.
    override func cleanUp() {
        super.cleanUp()
        stopRumble()
        hapticEngine?.stop()
        hapticEngine = nil
        rumblePlayer = nil
    }
    // ---------------------------------------------------------------
    // EVERY FRAME
    // ---------------------------------------------------------------

    override func readInput(secondsSinceLastFrame: Double) {
        // Let whisking work out the angles, the speed and the progress.
        super.readInput(secondsSinceLastFrame: secondsSinceLastFrame)

        // Then rumble whenever they are actually mixing.
        if isWorking {
            startRumble()

            // Stir faster, feel a stronger motor.
            setRumbleStrength(currentSpeed / speedForFullRumble)
        } else {
            stopRumble()
        }
    }
}

class MixingScreen: SKScene {
    
    var overlay: MixOverlay!
    var timeOfLastFrame = 0.0
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        showMixScreen()
    }
    
    func showMixScreen() {
        overlay?.removeFromParent()
        
        let newOverlay = MixOverlay(screenSize: size, actionName: "Mix the dough to make preps")
        
        // When it finishes, wait a moment and show it again so you can retry.
        newOverlay.whenFinished = {
            let wait = SKAction.wait(forDuration: 0.6)
            let again = SKAction.run {
                self.showMixScreen()
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
            let scene = MixingScreen(size: geometry.size)
            scene.scaleMode = .resizeFill
            return scene
        }())
        .ignoresSafeArea()
    }
}
#endif

