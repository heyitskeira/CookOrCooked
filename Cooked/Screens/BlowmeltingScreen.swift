//
//  Melting.swift
//  Cooked
//
//  Created by Keira on 14/08/26.
//
//  Melting butter, blowing version.
//
//  The fire climbs on its own. Blowing into the phone pushes it back down.
//  Progress only fills while the flame sits in the medium band, so the player
//  has to keep nudging it rather than blowing constantly.
//
//  This sits alongside MeltOverlay (the sliding version) so you can try both.
//
//  IMPORTANT: the microphone needs a permission line or the app crashes.
//  Project settings -> Cooked target -> Info tab
//  Add: "Privacy - Microphone Usage Description"
//  Value: something like "Used to blow on the flame while cooking."
//

import SpriteKit
import AVFoundation


class BlowMeltOverlay: StationOverlay {

    // ---- Settings ----

    // How loud the blowing has to be before it counts.
    // Decibels, where 0 is the loudest possible and -60 is near silence.
    // Closer to 0 means they must blow harder.
    var blowNeeded = -22.0

    // How fast the fire climbs on its own, per second.
    var fireRiseSpeed = 0.30

    // How fast blowing pushes the fire down, per second.
    var fireDropSpeed = 0.75

    // The safe band. Progress only fills while the fire is between these.
    var mediumLow = 0.25
    var mediumHigh = 0.60

    // How fast progress drains while the fire is too high, per second.
    // The butter is burning. Set to 0 if you would rather it just pause.
    var burnDrainSpeed = 0.4

    // Lets you test without a microphone by holding a finger down.
    // Turn this off before you ship.
    var allowTapFallback = true

    // ---- Things this screen shows ----

    let flame = SKSpriteNode()
    let heatTrack = SKSpriteNode()
    let safeZone = SKSpriteNode()
    let heatMarker = SKSpriteNode()

    // ---- Working values ----

    var fireLevel = 0.4         // how high the fire is, from 0 to 1
    var loudness = -60.0        // what the microphone is hearing, in decibels

    var isBlowing = false
    var isTooHot = false

    var gaugeHeight = 150.0
    var gaugeY = 0.0

    // The object that listens to the microphone.
    var recorder: AVAudioRecorder?

    let colorSafe = SKColor(.orange)
    let colorBurning = SKColor(.red)

    // ---------------------------------------------------------------
    // SETUP
    // ---------------------------------------------------------------

    override func setUpStation() {
        amountNeeded = 6.0          // seconds spent in the safe band
        hintWhenIdle = "Blow to lower the flame"
        hintWhenWorking = "Hold it steady"
        hintWhenDone = "Melted"

        // The base class prop is not used here, so hide it.
        prop.isHidden = true

        buildGauge()
        startListening()
    }

    // A vertical gauge showing the fire level, with the safe band marked.
    func buildGauge() {
        gaugeY = centerY + 80

        // The tall dark track the marker slides along.
        heatTrack.color = SKColor(white: 0.22, alpha: 1)
        heatTrack.size = CGSize(width: 14, height: gaugeHeight)
        heatTrack.position = CGPoint(x: centerX, y: gaugeY)
        addChild(heatTrack)

        // The lighter band showing where the fire should sit.
        let bandHeight = (mediumHigh - mediumLow) * gaugeHeight
        let bandMiddle = (mediumLow + mediumHigh) / 2
        safeZone.color = SKColor(white: 0.45, alpha: 1)
        safeZone.size = CGSize(width: 14, height: bandHeight)
        safeZone.position = CGPoint(x: centerX,
                                    y: gaugeBottom() + bandMiddle * gaugeHeight)
        addChild(safeZone)

        // The marker showing the current fire level.
        heatMarker.color = SKColor.white
        heatMarker.size = CGSize(width: 34, height: 6)
        heatMarker.position = CGPoint(x: centerX, y: gaugeY)
        addChild(heatMarker)

        // A simple flame beside the gauge. Swap for artwork later.
        flame.color = colorSafe
        flame.size = CGSize(width: 40, height: 40)
        flame.position = CGPoint(x: centerX - 70, y: gaugeY)
        addChild(flame)
    }

    // The y position of the bottom of the gauge.
    func gaugeBottom() -> Double {
        return gaugeY - gaugeHeight / 2
    }

    // ---------------------------------------------------------------
    // LISTENING TO THE MICROPHONE
    // ---------------------------------------------------------------

    func startListening() {
        // Ask the player for permission the first time.
        AVAudioApplication.requestRecordPermission { granted in
            if granted {
                DispatchQueue.main.async {
                    self.beginRecording()
                }
            }
        }
    }

    func beginRecording() {
        // Tell iOS we want to use the microphone.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement,
                                 options: [.defaultToSpeaker])
        try? session.setActive(true)

        // We never keep the audio, so record it to a throwaway path.
        let path = URL(fileURLWithPath: "/dev/null")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1
        ]

        recorder = try? AVAudioRecorder(url: path, settings: settings)

        // Metering is what lets us read how loud the sound is.
        recorder?.isMeteringEnabled = true
        recorder?.record()
    }

    override func cleanUp() {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // ---------------------------------------------------------------
    // EVERY FRAME
    // ---------------------------------------------------------------

    override func readInput(secondsSinceLastFrame: Double) {

        // Read how loud the microphone is right now.
        if let recorder = recorder {
            recorder.updateMeters()
            let reading = Double(recorder.averagePower(forChannel: 0))

            // Ease towards the new reading so one loud frame does not jolt it.
            loudness = loudness + (reading - loudness) * 0.4
        }

        isBlowing = loudness >= blowNeeded


        // The fire climbs on its own, and blowing pushes it back down.
        if isBlowing {
            fireLevel = fireLevel - fireDropSpeed * secondsSinceLastFrame
        } else {
            fireLevel = fireLevel + fireRiseSpeed * secondsSinceLastFrame
        }

        // Keep it inside 0 to 1.
        if fireLevel < 0 { fireLevel = 0 }
        if fireLevel > 1 { fireLevel = 1 }

        // Where the fire sits decides what happens to the butter.
        isTooHot = fireLevel > mediumHigh
        isWorking = fireLevel >= mediumLow && fireLevel <= mediumHigh

        if isWorking {
            amountDone = amountDone + secondsSinceLastFrame
        } else if isTooHot && burnDrainSpeed > 0 {
            // Burning, so the work already done starts to spoil.
            amountDone = amountDone - burnDrainSpeed * secondsSinceLastFrame
            if amountDone < 0 { amountDone = 0 }
        }

        // Warn the player when the flame is too high.
        if isTooHot {
            hintWhenIdle = "Too hot, blow it down"
        } else {
            hintWhenIdle = "Blow to lower the flame"
        }
    }

    override func animateProp(secondsSinceLastFrame: Double) {

        // Slide the marker up and down the gauge.
        let markerY = gaugeBottom() + fireLevel * gaugeHeight
        heatMarker.position = CGPoint(x: centerX, y: markerY)

        // Grow the flame with the heat, and turn it red when it is too high.
        let flameSize = 26 + fireLevel * 46
        flame.size = CGSize(width: flameSize * 0.7, height: flameSize)

        if isTooHot {
            flame.color = colorBurning
        } else {
            flame.color = colorSafe
        }

        // A small flicker so the flame never looks frozen.
        let flicker = Double.random(in: -2...2)
        flame.position = CGPoint(x: centerX - 70 + flicker, y: gaugeY)
    }
}


class BlowmeltingScreen: SKScene {
    
    var overlay: BlowMeltOverlay!
    var timeOfLastFrame = 0.0
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        showWhiskScreen()
    }
    
    func showWhiskScreen() {
        overlay?.removeFromParent()
        
        let newOverlay = BlowMeltOverlay(screenSize: size, actionName: "Melt the Butter")
        
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
            let scene = BlowmeltingScreen(size: geometry.size)
            scene.scaleMode = .resizeFill
            return scene
        }())
        .ignoresSafeArea()
    }
}
#endif
