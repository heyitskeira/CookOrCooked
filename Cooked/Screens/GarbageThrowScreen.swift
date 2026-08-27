//
//  GarbageThrowScreen.swift
//  Cooked
//
//  The garbage bin's minigame: throwing the rotten thing away.
//
//  The bin stands across the clearing and slides left and right along a rail.
//  TILT the phone to steer it — roll left, the bin goes left — and hold it
//  level to keep the bin over the centre line, straight above your hands. Then
//  TAP AND HOLD: a power meter sweeps up and back down, and letting go throws
//  the rot straight up. Land it in the bin and it's gone.
//
//  A miss costs nothing but time, which is the whole point: the bin never takes
//  the trash off you, so a bad thrower keeps the station (and anybody queueing
//  behind them) until they land one.
//
//  Two things have to be right at the moment you let go: the bin has to be
//  centred (that is the tilt), and the power has to carry the throw up to the
//  bin's row (that is the timing). Neither alone is enough.
//
//  Rebuilt against final art — the dark clearing, the wooden bin, the paws —
//  replacing the earlier first-person depth-aiming version. The bin now moves
//  on one axis, which is what the tutorial ("tilt left / centre / tilt right")
//  teaches.
//

import SpriteKit
import CoreMotion

// MARK: - Tuning
//
// The numbers to play with. Fractions of the screen, so they hold on any size.

private enum Throwing {

    /// How far the bin can slide from the centre, as a fraction of screen width.
    static let railHalfWidth = 0.30
    /// The bin's row and the hands' row, as fractions of height above centre.
    static let binRowAboveCentre = 0.05
    static let handsBelowCentre = 0.30

    /// The bin is drawn this wide (points); its height follows the art's ratio.
    static let binWidth = 104.0
    static let binArtRatio = 137.0 / 112.0     // ui-empty-garbage-bin @1x

    /// Seconds for the power meter to sweep all the way up and back down.
    static let chargeCycle = 1.15
    /// The power that just reaches the bin's row. Below 1 so a good throw sits
    /// mid-sweep, not at the very top where it's hardest to release on time.
    static let powerToReachBin = 0.8

    /// How wrong you can be and still land it. Generous on purpose: there is no
    /// walking away from the bin, so a chef who cannot hit it cannot play.
    static let centreTolerance = 0.11    // fraction of screen width, either side
    static let heightTolerance = 0.09    // fraction of screen height, short/long

    /// Tilt handling: how much stance a tilt buys, what counts as still, and how
    /// hard the reading is smoothed.
    static let tiltSensitivity = 2.4
    static let tiltDeadzone = 0.03
    static let tiltSmoothing = 0.16

    /// A tap shorter than this isn't a throw — it's a slip. Charging just stops
    /// and you keep the shot.
    static let minimumCharge = 0.18

    static let flightTime = 0.6
    static let missPause = 1.1
    /// How long the how-to card stays up when the screen opens.
    static let tutorialSeconds = 2.6
}

// MARK: - The screen

final class GarbageThrowOverlay: StationOverlay {

    private enum Phase {
        case calibrating   // waiting for the first gravity reading to set neutral
        case aiming        // steering the bin
        case charging      // finger down, meter sweeping
        case flying        // the rot is in the air
        case missed        // short pause, then back to aiming
        case landed        // it went in
    }

    private var phase: Phase = .calibrating

    // ---- Tilt ----

    private let motionManager = CMMotionManager()
    /// The pose held when the screen opened. Steering is measured from THIS,
    /// not from flat, so a phone held at an angle still starts centred.
    private var neutral: CMAcceleration?
    private var tilt = 0.0            // smoothed, calibrated, -1...1
    private var tiltSign = 1.0        // landscape-left vs -right flip
    private var usesTouchAiming = false

    // ---- State ----

    private var power = 0.0
    private var chargeTime = 0.0
    private var flightProgress = 0.0
    private var missTimer = 0.0
    private var tutorialTimer = 0.0
    private var attempt = 1
    /// Snapshot of the shot at the instant of release.
    private var thrownFromX = 0.0
    private var thrownPeakY = 0.0
    private var binXAtThrow = 0.0

    // ---- Drawing ----

    private let binNode = SKSpriteNode()
    private let binShadow = SKShapeNode()
    private let railNode = SKShapeNode()
    private let centreTick = SKShapeNode()
    private let aimLine = SKShapeNode()
    private let handsNode = SKSpriteNode()
    private let barfNode = SKLabelNode(text: "🤢")
    private let powerTrack = SKSpriteNode()
    private let powerFill = SKSpriteNode()
    private let statusLabel = SKLabelNode(fontNamed: "SFProText-Bold")
    private let attemptLabel = SKLabelNode(fontNamed: "SFProText-Regular")
    private let tutorialNode = SKSpriteNode()

    private var screenW = 0.0
    private var screenH = 0.0
    private var binRowY = 0.0
    private var handsY = 0.0
    private var binSize = CGSize.zero

    // MARK: Setup

    override func setUpStation() {
        amountNeeded = 1                       // one throw in, and you're done
        hintWhenIdle = "Tilt to centre the bin · hold to throw"
        hintWhenWorking = "Let go with the power on the bin"
        hintWhenDone = "In the bin!"

        screenW = Double(background.size.width)
        screenH = Double(background.size.height)
        binRowY = centerY + screenH * Throwing.binRowAboveCentre
        handsY = centerY - screenH * Throwing.handsBelowCentre
        binSize = CGSize(width: Throwing.binWidth,
                         height: Throwing.binWidth * Throwing.binArtRatio)

        // The base class's prop and progress bar belong to a hold-to-work
        // screen. This one draws its own room and its own meter.
        prop.isHidden = true
        barBackground.isHidden = true
        barFill.isHidden = true

        setBackdrop()
        buildRail()
        buildBin()
        buildHandsAndBarf()
        buildMeter()
        buildTutorial()

        startTilt()
    }

    private func setBackdrop() {
        if let art = UIImage(named: "ui-dark-blank-layout") {
            background.texture = SKTexture(image: art)
            background.colorBlendFactor = 0
        }
    }

    /// The rail the bin rides, and the centre tick that marks "straight above
    /// your hands" — without it "keep it centred" is a guess, and the whole
    /// game is that judgement.
    private func buildRail() {
        let half = screenW * Throwing.railHalfWidth
        let rail = CGMutablePath()
        rail.move(to: CGPoint(x: centerX - half, y: binRowY))
        rail.addLine(to: CGPoint(x: centerX + half, y: binRowY))
        railNode.path = rail
        railNode.strokeColor = SKColor(white: 1, alpha: 0.28)
        railNode.lineWidth = 3
        railNode.lineCap = .round
        railNode.zPosition = 2
        addChild(railNode)

        centreTick.path = CGPath(rect: CGRect(x: -2, y: -10, width: 4, height: 20), transform: nil)
        centreTick.fillColor = SKColor(red: 0.55, green: 0.85, blue: 0.45, alpha: 0.9)
        centreTick.strokeColor = .clear
        centreTick.position = CGPoint(x: centerX, y: binRowY)
        centreTick.zPosition = 3
        addChild(centreTick)

        // The faint vertical thread from the paws up to the centre of the rail:
        // the path the rot will take, so aiming reads as "put the bin on this
        // line". It brightens while charging.
        aimLine.strokeColor = SKColor(white: 1, alpha: 0.1)
        aimLine.lineWidth = 2
        aimLine.zPosition = 2
        let thread = CGMutablePath()
        thread.move(to: CGPoint(x: centerX, y: handsY))
        thread.addLine(to: CGPoint(x: centerX, y: binRowY))
        aimLine.path = thread.copy(dashingWithPhase: 0, lengths: [7, 8])
        addChild(aimLine)
    }

    private func buildBin() {
        binShadow.path = CGPath(ellipseIn: CGRect(x: -binSize.width * 0.42, y: -10,
                                                  width: binSize.width * 0.84, height: 20),
                                transform: nil)
        binShadow.fillColor = SKColor(white: 0, alpha: 0.33)
        binShadow.strokeColor = .clear
        binShadow.zPosition = 3
        addChild(binShadow)

        binNode.texture = emptyBinTexture
        binNode.size = binSize
        binNode.anchorPoint = CGPoint(x: 0.5, y: 0)   // sits ON the rail
        binNode.zPosition = 4
        addChild(binNode)
    }

    private func buildHandsAndBarf() {
        if let art = UIImage(named: "hands") {
            handsNode.texture = SKTexture(image: art)
            let w = screenW * 0.2
            handsNode.size = CGSize(width: w, height: w * (art.size.height / art.size.width))
            handsNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            handsNode.position = CGPoint(x: centerX, y: handsY - handsNode.size.height * 0.3)
            handsNode.zPosition = 7
            addChild(handsNode)
        }

        barfNode.fontSize = 46
        barfNode.verticalAlignmentMode = .center
        barfNode.horizontalAlignmentMode = .center
        barfNode.position = CGPoint(x: centerX, y: handsY)
        barfNode.zPosition = 8
        addChild(barfNode)
    }

    private func buildMeter() {
        let meterWidth = min(320.0, screenW - 140)
        let meterY = handsY - 54

        powerTrack.color = SKColor(white: 0.22, alpha: 0.9)
        powerTrack.size = CGSize(width: meterWidth, height: 12)
        powerTrack.position = CGPoint(x: centerX, y: meterY)
        powerTrack.zPosition = 7
        addChild(powerTrack)

        powerFill.color = .orange
        powerFill.size = CGSize(width: meterWidth, height: 12)
        powerFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        powerFill.position = CGPoint(x: centerX - meterWidth / 2, y: meterY)
        powerFill.xScale = 0.0001
        powerFill.zPosition = 8
        addChild(powerFill)

        // A mark on the meter at the power that reaches the bin, so the target
        // is on the meter and not just felt out.
        let sweet = SKSpriteNode(color: SKColor(red: 0.55, green: 0.85, blue: 0.45, alpha: 0.95),
                                 size: CGSize(width: 3, height: 20))
        sweet.position = CGPoint(x: centerX - meterWidth / 2 + meterWidth * Throwing.powerToReachBin,
                                 y: meterY)
        sweet.zPosition = 9
        addChild(sweet)

        statusLabel.fontSize = 22
        statusLabel.fontColor = SKColor(red: 1, green: 0.78, blue: 0.4, alpha: 1)
        statusLabel.position = CGPoint(x: centerX, y: centerY - screenH * 0.02)
        statusLabel.zPosition = 9
        statusLabel.text = ""
        addChild(statusLabel)

        attemptLabel.fontSize = 13
        attemptLabel.fontColor = SKColor(white: 0.55, alpha: 1)
        attemptLabel.position = CGPoint(x: centerX, y: meterY - 26)
        attemptLabel.zPosition = 9
        attemptLabel.text = ""
        addChild(attemptLabel)
    }

    /// The how-to card: shown on open, tap or wait to dismiss. The art carries
    /// its own labels (tilt left / centre / tilt right, press to control power).
    private func buildTutorial() {
        guard let art = UIImage(named: "ui-garbage-bin-tutorial") else { return }
        tutorialNode.texture = SKTexture(image: art)
        let w = screenW * 0.9
        tutorialNode.size = CGSize(width: w, height: w * (art.size.height / art.size.width))
        tutorialNode.position = CGPoint(x: centerX, y: centerY)
        tutorialNode.zPosition = 40
        addChild(tutorialNode)

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.45), size: background.size)
        dim.position = CGPoint(x: centerX, y: centerY)
        dim.zPosition = 39
        dim.name = "tutorialDim"
        addChild(dim)

        tutorialTimer = Throwing.tutorialSeconds
    }

    private lazy var emptyBinTexture: SKTexture? =
        UIImage(named: "ui-empty-garbage-bin").map { SKTexture(image: $0) }
    private lazy var filledBinTexture: SKTexture? =
        UIImage(named: "ui-filled-garbage-bin").map { SKTexture(image: $0) }

    private var tutorialShowing: Bool { tutorialTimer > 0 }

    private func dismissTutorial() {
        tutorialTimer = 0
        tutorialNode.run(.fadeOut(withDuration: 0.2)) { [weak self] in
            self?.tutorialNode.isHidden = true
        }
        childNode(withName: "tutorialDim")?.run(.fadeOut(withDuration: 0.2))
    }

    // MARK: Tilt

    private func startTilt() {
        guard motionManager.isDeviceMotionAvailable else {
            // No gyro (the simulator): drag to steer instead, same geometry.
            usesTouchAiming = true
            hintWhenIdle = "Drag to centre the bin · hold to throw"
            return
        }
        if let orientation = scene?.view?.window?.windowScene?.interfaceOrientation,
           orientation == .landscapeLeft {
            tiltSign = -1
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.readGravity(motion.gravity)
        }
    }

    /// Gravity → a steer in -1...1, measured from the opening pose.
    private func readGravity(_ gravity: CMAcceleration) {
        guard let neutral else {
            self.neutral = gravity
            if phase == .calibrating { phase = .aiming }
            return
        }
        // In landscape the device's long axis (y) runs across the screen.
        var sideways = (gravity.y - neutral.y) * Throwing.tiltSensitivity * tiltSign
        if abs(sideways) < Throwing.tiltDeadzone { sideways = 0 }
        tilt += (clamp(sideways) - tilt) * Throwing.tiltSmoothing
    }

    private func clamp(_ v: Double) -> Double { min(1, max(-1, v)) }

    override func cleanUp() {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if tutorialShowing { dismissTutorial(); return }
        guard phase == .aiming else { return }
        phase = .charging
        chargeTime = 0
        power = 0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard usesTouchAiming, let touch = touches.first else { return }
        let point = touch.location(in: self)
        tilt = clamp((Double(point.x) - centerX) / (screenW * Throwing.railHalfWidth))
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

    private var binX: Double { centerX + tilt * screenW * Throwing.railHalfWidth }

    /// The height a given power carries the rot to, measured up from the hands.
    /// `powerToReachBin` is the power that reaches the bin exactly.
    private func peakY(for power: Double) -> Double {
        let reach = (binRowY - handsY) / Throwing.powerToReachBin
        return handsY + power * reach
    }

    private func release() {
        guard chargeTime >= Throwing.minimumCharge else {
            phase = .aiming
            return
        }
        thrownFromX = centerX          // the rot leaves the hands, straight up
        thrownPeakY = peakY(for: power)
        binXAtThrow = binX
        flightProgress = 0
        phase = .flying
    }

    /// Did it go in? Two independent errors: how far the bin sat off centre,
    /// and how far short or long the throw carried.
    private func land() {
        let sideError = abs(binXAtThrow - centerX)
        let heightError = thrownPeakY - binRowY

        if sideError <= screenW * Throwing.centreTolerance
            && abs(heightError) <= screenH * Throwing.heightTolerance {
            statusLabel.text = "Straight in!"
            barfNode.isHidden = true
            binNode.texture = filledBinTexture
            binNode.run(.sequence([.scaleY(to: 0.9, duration: 0.08),
                                   .scaleY(to: 1, duration: 0.12)]))
            phase = .landed
            amountDone = amountNeeded      // the base class runs the finish pipeline
            return
        }

        if sideError > screenW * Throwing.centreTolerance {
            statusLabel.text = binXAtThrow > centerX ? "Bin too far right!" : "Bin too far left!"
        } else {
            statusLabel.text = heightError < 0 ? "Too soft!" : "Too hard!"
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

    override func readInput(secondsSinceLastFrame dt: Double) {
        isWorking = phase == .charging

        if tutorialShowing {
            tutorialTimer -= dt
            if tutorialTimer <= 0 { dismissTutorial() }
            return
        }

        switch phase {
        case .calibrating, .aiming, .landed:
            break
        case .charging:
            chargeTime += dt
            let sweep = chargeTime.truncatingRemainder(dividingBy: Throwing.chargeCycle)
            let half = Throwing.chargeCycle / 2
            power = sweep < half ? sweep / half : (Throwing.chargeCycle - sweep) / half
        case .flying:
            flightProgress += dt / Throwing.flightTime
            if flightProgress >= 1 { flightProgress = 1; land() }
        case .missed:
            missTimer += dt
            if missTimer >= Throwing.missPause {
                statusLabel.text = ""
                barfNode.isHidden = false
                phase = .aiming
            }
        }
    }

    override func animateProp(secondsSinceLastFrame dt: Double) {
        drawBin()
        drawMeter()
        drawBarf()
    }

    private func drawBin() {
        binNode.position = CGPoint(x: binX, y: binRowY)
        binShadow.position = CGPoint(x: binX, y: binRowY - 4)
    }

    private func drawMeter() {
        let showing = phase == .charging
        powerFill.xScale = showing ? max(0.0001, power) : 0.0001
        powerTrack.alpha = showing ? 1 : 0.4
        powerFill.color = power > Throwing.powerToReachBin + 0.08 ? .red : .orange
        aimLine.strokeColor = SKColor(white: 1, alpha: showing ? 0.3 : 0.1)
    }

    private func drawBarf() {
        switch phase {
        case .flying:
            barfNode.isHidden = false
            // Straight up from the hands to the throw's peak, easing out as it
            // rises and shrinking a little with distance.
            let t = flightProgress
            let eased = 1 - pow(1 - t, 2)
            let y = handsY + (thrownPeakY - handsY) * eased
            barfNode.position = CGPoint(x: thrownFromX, y: y)
            barfNode.setScale(max(0.5, 1 - 0.4 * eased))
        case .landed:
            barfNode.isHidden = true
        default:
            barfNode.isHidden = false
            barfNode.position = CGPoint(x: centerX, y: handsY)
            barfNode.setScale(1)
        }
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
        newOverlay.whenFinished = {
            let wait = SKAction.wait(forDuration: 0.9)
            let again = SKAction.run { self.showThrowScreen() }
            self.run(SKAction.sequence([wait, again]))
        }
        addChild(newOverlay)
        overlay = newOverlay
    }

    override func update(_ currentTime: TimeInterval) {
        if timeOfLastFrame == 0 { timeOfLastFrame = currentTime }
        var gap = currentTime - timeOfLastFrame
        if gap > 0.1 { gap = 0.1 }
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
