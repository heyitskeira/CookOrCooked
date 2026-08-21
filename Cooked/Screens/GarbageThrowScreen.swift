//
//  GarbageThrowScreen.swift
//  Cooked
//
//  The garbage bin's minigame: throwing the rotten thing away, first person.
//
//  You are looking at the bin a few metres ahead with the trash in your hand.
//  TILT the phone to shift your stance — roll slides you sideways, pitch walks
//  you closer or further — until the bin sits in the middle of the screen.
//  Then TAP AND HOLD: the power meter sweeps up and back down, and letting go
//  decides how far the throw carries. Land it in the bin and the rot is gone.
//
//  A miss costs nothing but time, which is the whole point: the bin never takes
//  the trash off you, so a bad thrower keeps the station (and anybody queueing
//  behind them) until they land one.
//
//  Everything is drawn from flat nodes — the "3D" is one scale factor per
//  depth, applied to the bin's size, its height on screen, and the trash in
//  flight. No camera, no physics engine.
//

import SpriteKit
import CoreMotion

// MARK: - Tuning
//
// These are the numbers to play with. Distances are in metres so the maths
// reads like the room it's pretending to be.

private enum Throwing {

    /// How far away the bin stands when you walk up to it.
    static let restDepth = 6.0
    /// How far tilting can walk you in and out, and slide you side to side.
    static let stepRange = 2.0
    static let strafeRange = 1.8
    /// Clamps, so nobody tilts their way into the bin or out of the kitchen.
    static let nearestDepth = 3.2
    static let farthestDepth = 9.0

    /// The depth that draws at scale 1. Everything nearer looks bigger.
    static let focalDepth = 6.0

    /// What the power meter maps onto, end to end.
    static let minThrow = 2.5
    static let maxThrow = 10.5
    /// Seconds for the meter to sweep all the way up and back down.
    static let chargeCycle = 1.15

    /// How wrong you can be and still land it. Generous on purpose: there is no
    /// walking away from the bin, so a chef who cannot hit it is a chef who
    /// cannot play.
    static let lateralTolerance = 0.5      // metres either side of the middle
    static let depthTolerance = 1.15       // metres short or long

    /// Tilt handling: how much of a stance a given tilt buys, how still counts
    /// as still, and how hard the reading is smoothed.
    static let tiltSensitivity = 2.4
    static let tiltDeadzone = 0.035
    static let tiltSmoothing = 0.16

    /// A tap shorter than this isn't a throw — it's a slip, a stray touch, or a
    /// finger brushing the screen. Charging just stops and you keep the shot.
    static let minimumCharge = 0.18

    static let flightTime = 0.75
    static let missPause = 1.25
}

// MARK: - The screen

final class GarbageThrowOverlay: StationOverlay {

    /// Where the throw is up to. The whole screen is this one state machine.
    private enum Phase {
        case calibrating   // waiting for the first gravity reading to set neutral
        case aiming        // tilting the bin into the middle
        case charging      // finger down, meter sweeping
        case flying        // it's in the air
        case missed        // short pause, then back to aiming
    }

    private var phase: Phase = .calibrating

    // ---- Tilt ----

    private let motionManager = CMMotionManager()
    /// The pose the player was holding when the screen opened. Aim is measured
    /// from THIS, not from flat: a phone held at 45° on a couch and one flat on
    /// a table must both start pointing at the bin.
    private var neutral: CMAcceleration?
    /// Smoothed, calibrated tilt in -1...1 on each axis.
    private var tilt = CGPoint.zero
    /// Screen-space sign of the device axes, fixed at calibration time —
    /// landscape-left and landscape-right disagree about which way is right.
    private var tiltSign: CGFloat = 1
    /// No gyro (the simulator, mostly). Aim with a dragged finger instead so
    /// the geometry is still testable.
    private var usesTouchAiming = false

    // ---- Where you stand, and what you threw ----

    /// x = metres sidestepped, y = metres walked forward.
    private var stance = CGPoint.zero
    private var power = 0.0
    private var chargeTime = 0.0
    private var flightProgress = 0.0
    private var missTimer = 0.0
    private var attempt = 1
    /// The throw being animated: how far it carries, and how far off-centre the
    /// thrower was standing.
    private var thrownDistance = 0.0
    private var thrownLateral = 0.0

    // ---- Drawing ----

    private let floorNode = SKSpriteNode()
    private let horizonNode = SKSpriteNode()
    private let binNode = SKNode()
    private let binBody = SKShapeNode()
    private let binMouth = SKShapeNode()
    private let binShadow = SKShapeNode()
    private let arcNode = SKShapeNode()
    /// The throw's shadow on the floor. In a first-person view the trash flies
    /// straight up the centre line, so height on screen alone can't say whether
    /// it's rising or going long — the shadow travelling towards the horizon is
    /// what actually reads as distance.
    private let flightShadow = SKShapeNode(ellipseOf: CGSize(width: 46, height: 16))
    /// Where this much power would drop it. The dashed track ends here.
    private let landingRing = SKShapeNode(ellipseOf: CGSize(width: 54, height: 20))
    private let trashNode = SKLabelNode(text: "🤢")
    private let powerTrack = SKSpriteNode()
    private let powerFill = SKSpriteNode()
    private let statusLabel = SKLabelNode(fontNamed: "SFProText-Bold")
    private let attemptLabel = SKLabelNode(fontNamed: "SFProText-Regular")

    private var horizonY = 0.0
    private var groundDrop = 0.0
    private var pixelsPerMetre = 0.0
    private var handY = 0.0
    private var screenWidth = 0.0

    // MARK: Setup

    override func setUpStation() {
        amountNeeded = 1                     // one throw in, and you're done
        hintWhenIdle = "Tilt to line up the bin · hold to throw"
        hintWhenWorking = "Let go at the right power"
        hintWhenDone = "In the bin!"

        screenWidth = Double(background.size.width)
        let height = Double(background.size.height)

        // The base class's prop and progress bar belong to a hold-to-work
        // screen. This one has a room to draw and a power meter of its own.
        prop.isHidden = true
        barBackground.isHidden = true
        barFill.isHidden = true

        horizonY = centerY + height * 0.12
        groundDrop = height * 0.20
        pixelsPerMetre = screenWidth * 0.17
        handY = centerY - height * 0.32

        buildRoom(width: screenWidth, height: height)
        buildBin()
        buildAimAids()

        startTilt()
    }

    private func buildRoom(width: Double, height: Double) {
        // Floor: everything below the horizon. Slightly lighter than the walls
        // so the bin has something to stand on.
        floorNode.color = SKColor(red: 0.17, green: 0.16, blue: 0.19, alpha: 1)
        floorNode.size = CGSize(width: width, height: height)
        floorNode.anchorPoint = CGPoint(x: 0.5, y: 1)
        floorNode.position = CGPoint(x: centerX, y: horizonY)
        floorNode.zPosition = 1
        addChild(floorNode)

        horizonNode.color = SKColor(white: 0.32, alpha: 1)
        horizonNode.size = CGSize(width: width, height: 2)
        horizonNode.position = CGPoint(x: centerX, y: horizonY)
        horizonNode.zPosition = 2
        addChild(horizonNode)

        // A centre line to aim down. Without it "line the bin up in the middle"
        // is a guess, and the whole game is that judgement.
        let centreLine = SKSpriteNode(color: SKColor(white: 1, alpha: 0.12),
                                      size: CGSize(width: 1.5, height: horizonY - handY))
        centreLine.anchorPoint = CGPoint(x: 0.5, y: 0)
        centreLine.position = CGPoint(x: centerX, y: handY)
        centreLine.zPosition = 2
        addChild(centreLine)
    }

    private func buildBin() {
        binShadow.path = CGPath(ellipseIn: CGRect(x: -46, y: -12, width: 92, height: 24),
                                transform: nil)
        binShadow.fillColor = SKColor(white: 0, alpha: 0.35)
        binShadow.strokeColor = .clear
        binShadow.zPosition = 3
        binNode.addChild(binShadow)

        // A plain tapered bin: body, then a darker ellipse for the mouth so you
        // can see you're throwing INTO something.
        binBody.path = CGPath(roundedRect: CGRect(x: -38, y: 0, width: 76, height: 74),
                              cornerWidth: 8, cornerHeight: 8, transform: nil)
        binBody.fillColor = SKColor(red: 0.36, green: 0.42, blue: 0.40, alpha: 1)
        binBody.strokeColor = SKColor(white: 0.08, alpha: 1)
        binBody.lineWidth = 3
        binBody.zPosition = 4
        binNode.addChild(binBody)

        binMouth.path = CGPath(ellipseIn: CGRect(x: -38, y: 62, width: 76, height: 24),
                               transform: nil)
        binMouth.fillColor = SKColor(red: 0.13, green: 0.15, blue: 0.15, alpha: 1)
        binMouth.strokeColor = SKColor(white: 0.08, alpha: 1)
        binMouth.lineWidth = 3
        binMouth.zPosition = 5
        binNode.addChild(binMouth)

        binNode.zPosition = 3
        addChild(binNode)
    }

    private func buildAimAids() {
        arcNode.strokeColor = SKColor(red: 0.45, green: 0.75, blue: 1, alpha: 0.75)
        arcNode.lineWidth = 2.5
        arcNode.zPosition = 6
        arcNode.isHidden = true
        addChild(arcNode)

        flightShadow.fillColor = SKColor(white: 0, alpha: 0.4)
        flightShadow.strokeColor = .clear
        flightShadow.zPosition = 4
        flightShadow.isHidden = true
        addChild(flightShadow)

        landingRing.fillColor = .clear
        landingRing.strokeColor = SKColor(red: 0.45, green: 0.75, blue: 1, alpha: 0.8)
        landingRing.lineWidth = 2.5
        landingRing.zPosition = 6
        landingRing.isHidden = true
        addChild(landingRing)

        trashNode.fontSize = 44
        trashNode.verticalAlignmentMode = .center
        trashNode.position = CGPoint(x: centerX, y: handY)
        trashNode.zPosition = 8
        addChild(trashNode)

        let meterWidth = min(300.0, screenWidth - 120)
        powerTrack.color = SKColor(white: 0.24, alpha: 1)
        powerTrack.size = CGSize(width: meterWidth, height: 12)
        powerTrack.position = CGPoint(x: centerX, y: handY - 46)
        powerTrack.zPosition = 7
        addChild(powerTrack)

        powerFill.color = SKColor.orange
        powerFill.size = CGSize(width: meterWidth, height: 12)
        powerFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        powerFill.position = CGPoint(x: centerX - meterWidth / 2, y: handY - 46)
        powerFill.xScale = 0.0001
        powerFill.zPosition = 8
        addChild(powerFill)

        statusLabel.fontSize = 20
        statusLabel.fontColor = SKColor(red: 1, green: 0.72, blue: 0.35, alpha: 1)
        statusLabel.position = CGPoint(x: centerX, y: centerY + 34)
        statusLabel.zPosition = 9
        statusLabel.text = "Hold still…"
        addChild(statusLabel)

        attemptLabel.fontSize = 13
        attemptLabel.fontColor = SKColor(white: 0.5, alpha: 1)
        attemptLabel.position = CGPoint(x: centerX, y: handY - 72)
        attemptLabel.zPosition = 9
        attemptLabel.text = ""
        addChild(attemptLabel)
    }

    // MARK: Tilt

    private func startTilt() {
        guard motionManager.isDeviceMotionAvailable else {
            // No gyro: drag to aim instead. Same numbers, different input, so
            // the geometry can still be checked in the simulator.
            usesTouchAiming = true
            phase = .aiming
            statusLabel.text = "Drag to line up · hold to throw"
            return
        }

        // Landscape-left and landscape-right hold the device's axes the
        // opposite way round, so the same roll means opposite directions.
        if let orientation = scene?.view?.window?.windowScene?.interfaceOrientation,
           orientation == .landscapeLeft {
            tiltSign = -1
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.readGravity(motion.gravity)
        }
    }

    /// Turn the gravity vector into a stance, measured from the pose the player
    /// was already holding.
    private func readGravity(_ gravity: CMAcceleration) {
        guard let neutral else {
            // First reading in: that's neutral, and the game can start.
            self.neutral = gravity
            if phase == .calibrating {
                phase = .aiming
                statusLabel.text = ""
            }
            return
        }

        // In landscape the device's long axis (y) runs across the screen, and
        // rolling about it (x) tips the view towards and away from you.
        var sideways = (gravity.y - neutral.y) * Throwing.tiltSensitivity * tiltSign
        var forwards = (gravity.x - neutral.x) * Throwing.tiltSensitivity * tiltSign

        if abs(sideways) < Throwing.tiltDeadzone { sideways = 0 }
        if abs(forwards) < Throwing.tiltDeadzone { forwards = 0 }

        // Low-pass, or the bin jitters with the player's pulse.
        tilt.x += (clamp(sideways) - tilt.x) * Throwing.tiltSmoothing
        tilt.y += (clamp(forwards) - tilt.y) * Throwing.tiltSmoothing
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(-1, value))
    }

    override func cleanUp() {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phase == .aiming else { return }
        phase = .charging
        chargeTime = 0
        power = 0
        statusLabel.text = ""
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Only when there's no gyro to aim with.
        guard usesTouchAiming, let touch = touches.first else { return }
        let point = touch.location(in: self)
        tilt.x = clamp((Double(point.x) - centerX) / (screenWidth * 0.35))
        tilt.y = clamp((Double(point.y) - centerY) / (groundDrop * 2))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phase == .charging else { return }
        release()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phase == .charging else { return }
        release()
    }

    // MARK: The throw

    private func release() {
        guard chargeTime >= Throwing.minimumCharge else {
            phase = .aiming
            arcNode.isHidden = true
            return
        }
        thrownDistance = Throwing.minThrow + power * (Throwing.maxThrow - Throwing.minThrow)
        // You throw straight ahead, so where you were standing IS your aim.
        thrownLateral = stance.x
        flightProgress = 0
        phase = .flying
        arcNode.isHidden = true
        trashNode.isHidden = false
    }

    /// Did it go in? Two independent errors: how far off the middle you stood,
    /// and how far short or long you threw.
    private func land() {
        let sideError = abs(thrownLateral)
        let depthError = thrownDistance - binDepth

        if sideError <= Throwing.lateralTolerance && abs(depthError) <= Throwing.depthTolerance {
            statusLabel.text = "Straight in!"
            trashNode.isHidden = true
            binNode.run(.sequence([.scaleY(to: binNode.yScale * 0.88, duration: 0.08),
                                   .scaleY(to: binNode.yScale, duration: 0.12)]))
            // Handing the base class a full bar is what completes the action:
            // its own update() sees it and runs the finish/announce pipeline.
            amountDone = amountNeeded
            return
        }

        // Name the mistake. A miss you can't read teaches nothing, and there is
        // no way out of this screen but a hit.
        if sideError > Throwing.lateralTolerance {
            statusLabel.text = thrownLateral > 0 ? "Wide right!" : "Wide left!"
        } else {
            statusLabel.text = depthError < 0 ? "Too short!" : "Too far!"
        }

        attempt += 1
        attemptLabel.text = "Attempt \(attempt)"
        missTimer = 0
        phase = .missed
        binNode.run(.sequence([.moveBy(x: 6, y: 0, duration: 0.05),
                               .moveBy(x: -12, y: 0, duration: 0.1),
                               .moveBy(x: 6, y: 0, duration: 0.05)]))
    }

    // MARK: Every frame

    override func readInput(secondsSinceLastFrame: Double) {
        isWorking = phase == .charging

        switch phase {
        case .calibrating:
            break

        case .aiming:
            applyStance()

        case .charging:
            applyStance()
            // The meter sweeps up and back down for as long as you hold, so
            // there's always another pass coming if you miss the one you wanted.
            chargeTime += secondsSinceLastFrame
            let sweep = chargeTime.truncatingRemainder(dividingBy: Throwing.chargeCycle)
            let half = Throwing.chargeCycle / 2
            power = sweep < half ? sweep / half : (Throwing.chargeCycle - sweep) / half

        case .flying:
            flightProgress += secondsSinceLastFrame / Throwing.flightTime
            if flightProgress >= 1 {
                flightProgress = 1
                land()
            }

        case .missed:
            missTimer += secondsSinceLastFrame
            if missTimer >= Throwing.missPause {
                statusLabel.text = ""
                phase = .aiming
            }
        }
    }

    /// Tilt → where you're standing. Stepping forward is capped so the bin
    /// can't be walked into or out of the room.
    private func applyStance() {
        stance.x = tilt.x * Throwing.strafeRange
        let stepped = tilt.y * Throwing.stepRange
        let depth = min(Throwing.farthestDepth,
                        max(Throwing.nearestDepth, Throwing.restDepth - stepped))
        stance.y = Throwing.restDepth - depth
    }

    /// How far the bin is from where the chef is standing right now.
    private var binDepth: Double {
        Throwing.restDepth - stance.y
    }

    override func animateProp(secondsSinceLastFrame: Double) {
        drawBin()
        drawPowerMeter()
        drawTrash()
    }

    private func drawBin() {
        let projected = project(depth: binDepth, lateral: 0)
        binNode.position = projected.point
        binNode.setScale(projected.scale)
    }

    private func drawPowerMeter() {
        let showing = phase == .charging
        powerFill.xScale = showing ? max(0.0001, power) : 0.0001
        powerTrack.alpha = showing ? 1 : 0.35
        powerFill.color = power > 0.85 ? SKColor.red : SKColor.orange
    }

    private func drawTrash() {
        switch phase {
        case .flying:
            trashNode.isHidden = false
            let travelled = thrownDistance * flightProgress
            let projected = project(depth: max(0.7, travelled), lateral: thrownLateral)
            // Straight ahead means it never leaves the centre line — what moves
            // is the bin, which is the whole read on the shot.
            let lift = sin(Double.pi * flightProgress) * groundDrop * 1.15 * projected.scale
            let ground = flightProgress < 0.06
                ? handY + (projected.point.y - handY) * (flightProgress / 0.06)
                : projected.point.y
            trashNode.position = CGPoint(x: projected.point.x, y: ground + lift)
            trashNode.setScale(max(0.25, projected.scale))

            flightShadow.isHidden = false
            flightShadow.position = CGPoint(x: projected.point.x, y: ground)
            flightShadow.setScale(max(0.2, projected.scale))
            flightShadow.alpha = 0.15 + 0.35 * (1 - sin(Double.pi * flightProgress))

            arcNode.isHidden = true
            landingRing.isHidden = true

        case .charging:
            trashNode.position = CGPoint(x: centerX, y: handY)
            trashNode.setScale(1)
            flightShadow.isHidden = true
            drawArcPreview()

        default:
            trashNode.isHidden = false
            trashNode.position = CGPoint(x: centerX, y: handY)
            trashNode.setScale(1)
            flightShadow.isHidden = true
            arcNode.isHidden = true
            landingRing.isHidden = true
        }
    }

    /// The dashed track along the FLOOR to where this much power drops it, and
    /// a ring at the landing spot. Truthful on purpose: the difficulty is
    /// holding a pose and letting go on time, not guessing at hidden numbers.
    ///
    /// It draws the ground line rather than the flight path because the flight
    /// path, seen from behind, is a vertical line — the rise and the distance
    /// both move the trash up the screen and cancel each other out to the eye.
    private func drawArcPreview() {
        let distance = Throwing.minThrow + power * (Throwing.maxThrow - Throwing.minThrow)
        let path = CGMutablePath()
        var first = true

        for step in 0...16 {
            let t = Double(step) / 16
            let projected = project(depth: max(0.7, distance * t), lateral: stance.x)
            let y = t < 0.06
                ? handY + (projected.point.y - handY) * (t / 0.06)
                : projected.point.y
            let point = CGPoint(x: projected.point.x, y: y)
            if first {
                path.move(to: point)
                first = false
            } else {
                path.addLine(to: point)
            }
        }

        arcNode.path = path.copy(dashingWithPhase: 0, lengths: [8, 7])
        arcNode.isHidden = false

        let landing = project(depth: distance, lateral: stance.x)
        landingRing.position = landing.point
        landingRing.setScale(max(0.2, landing.scale))
        landingRing.isHidden = false
    }

    /// One depth → one scale, and everything else follows from it: how big a
    /// thing draws, how far down the screen it sits, and how far off-centre it
    /// slides as the chef steps sideways.
    private func project(depth: Double, lateral: Double) -> (point: CGPoint, scale: Double) {
        let clamped = max(0.7, depth)
        let scale = Throwing.focalDepth / clamped
        let x = centerX + (lateral - stance.x) * scale * pixelsPerMetre
        let y = horizonY - groundDrop * scale
        return (CGPoint(x: x, y: y), scale)
    }
}

// MARK: - Preview harness

class GarbageThrowPreviewScene: SKScene {

    var overlay: GarbageThrowOverlay?
    var timeOfLastFrame = 0.0

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        showThrowScreen()
    }

    func showThrowScreen() {
        overlay?.cleanUp()
        overlay?.removeFromParent()

        let newOverlay = GarbageThrowOverlay(screenSize: size, actionName: "Throw out the rotten one")

        // Land one and it starts again, so the throw can be practised.
        newOverlay.whenFinished = {
            let wait = SKAction.wait(forDuration: 0.8)
            let again = SKAction.run { self.showThrowScreen() }
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

#Preview("Garbage throw") {
    GeometryReader { geometry in
        SpriteView(scene: {
            let scene = GarbageThrowPreviewScene(size: geometry.size)
            scene.scaleMode = .resizeFill
            return scene
        }())
        .ignoresSafeArea()
    }
}
#endif
