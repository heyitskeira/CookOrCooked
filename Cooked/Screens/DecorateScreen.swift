//
//  DecorateScreen.swift
//  Cooked
//
//  Created by Keira on 16/08/26.
//
//  Decorating the cake, in two beats.
//
//  Beat one: circle the phone in the air, like holding a piping bag. It has
//  to be slow and steady. Going too fast warns the player and stops the
//  progress, so rushing actively costs time.
//
//  Beat two: place the macerated strawberries by tapping the marked spots
//  on the cake. Accuracy matters, not speed.
//
//  Uses CoreMotion, so the piping needs a real device. There is a touch
//  fallback for the simulator.
//  HOW THE CIRCLING IS DETECTED
//
//  Gravity cannot be used here, because gravity only changes when the phone
//  is rotated, not when it is moved around. Holding it steady and circling
//  it leaves gravity completely still.
//
//  So this reads userAcceleration instead. When something moves in a circle
//  its acceleration points towards the centre of that circle, and that
//  direction sweeps all the way round once per lap. Tracking the angle of
//  the acceleration therefore counts laps.
//
//  The catch is that slow circles produce small accelerations, so the signal
//  is weak and needs heavy smoothing. If this proves too unreliable in the
//  hand, motionFloor and the smoothing are the first things to loosen.
//

import SpriteKit
import SwiftUI
import CoreMotion


class DecorateOverlay: StationOverlay {

    // ---- Settings ----

    // Must the phone be held top edge down before cream comes out.
    var needTopDown = true

    // How far tipped it has to be. 1.0 is perfectly upside down, 0.6 allows
    // a fairly generous angle.
    var tiltNeeded = 0.55

    // Movement quieter than this is treated as noise and ignored, in G.
    // Lower it if slow circles are not registering.
    var motionFloor = 0.025

    // How slowly the circles must be made, in radians per second.
    // Below the first number nothing happens, above the second is too fast.
    var pipeTooSlow = 0.25
    var pipeTooFast = 5.5

    // How many full circles of piping are needed.
    var turnsNeeded = 2.5

    // How many strawberries go on top.
    var strawberryCount = 7

    // How close a tap has to be to a spot to count, in points.
    var tapAccuracy = 46.0

    // How much of the bar the piping is worth. The rest is the strawberries.
    var pipeShare = 0.7

    // Lets you pipe by dragging when there is no motion sensor.
    var allowTouchFallback = true

    // ---- Things this screen shows ----

    let cake = SKSpriteNode()
    let cream = SKShapeNode()
    let warningLabel = SKLabelNode(fontNamed: "SFProText-Bold")

    var spotNodes: [SKShapeNode] = []
    var berryNodes: [SKSpriteNode] = []
    var spotPoints: [CGPoint] = []

    // ---- Working values ----

    var hasPiped = false
    var berriesPlaced = 0

    // Orientation.
    var isHeldRight = false

    // Circling, read from the acceleration vector.
    var turnedSoFar = 0.0
    var previousAngle = 0.0
    var hasPreviousAngle = false
    var turnDirection = 0.0
    var turnedThisFrame = 0.0
    var currentSpeed = 0.0
    var isTooFast = false

    // Touch fallback, kept completely separate so it cannot interfere.
    var isTouching = false
    var previousTouchAngle = 0.0
    var hasPreviousTouchAngle = false

    var hasMotionSensor = false

    let motionManager = CMMotionManager()

    let colorCake = SKColor(red: 0.86, green: 0.74, blue: 0.55, alpha: 1)
    let colorCream = SKColor(white: 0.97, alpha: 1)
    let colorBerry = SKColor(red: 0.85, green: 0.20, blue: 0.28, alpha: 1)
    let colorWarn = SKColor(.red)

    // ---------------------------------------------------------------
    // SETUP
    // ---------------------------------------------------------------

    override func setUpStation() {
        amountNeeded = 1.0          // a share of the whole job
        hintWhenIdle = "Point the phone down and circle slowly"
        hintWhenWorking = "Nice and steady"
        hintWhenDone = "Decorated"

        prop.isHidden = true

        buildCake()
        startReadingMotion()
    }

    func buildCake() {
        cake.color = colorCake
        cake.size = CGSize(width: 190, height: 130)
        cake.position = CGPoint(x: centerX, y: propRestY - 10)
        cake.zPosition = -2
        addChild(cake)

        // The cream, drawn as a spiral that grows as the player pipes.
        cream.strokeColor = colorCream
        cream.lineWidth = 9
        cream.lineCap = .round
        cream.fillColor = .clear
        cream.position = CGPoint(x: centerX, y: propRestY - 10)
        cream.zPosition = -1
        addChild(cream)

        warningLabel.text = ""
        warningLabel.fontSize = 14
        warningLabel.fontColor = colorWarn
        warningLabel.position = CGPoint(x: centerX, y: propRestY + 92)
        addChild(warningLabel)

        buildSpots()
    }

    // Marks where the strawberries go, spread evenly around the cake.
    func buildSpots() {
        for index in 0..<strawberryCount {
            let turn = (Double(index) / Double(strawberryCount)) * 2 * Double.pi
            let spotX = centerX + cos(turn) * 62
            let spotY = (propRestY - 10) + sin(turn) * 38
            let point = CGPoint(x: spotX, y: spotY)
            spotPoints.append(point)

            let marker = SKShapeNode(circleOfRadius: 15)
            marker.position = point
            marker.strokeColor = SKColor(white: 0.6, alpha: 1)
            marker.lineWidth = 2
            marker.fillColor = .clear
            marker.isHidden = true          // only shown once piping is done
            addChild(marker)
            spotNodes.append(marker)
        }
    }

    // ---------------------------------------------------------------
    // READING THE PHONE'S MOVEMENT
    // ---------------------------------------------------------------

    func startReadingMotion() {
        hasMotionSensor = motionManager.isDeviceMotionAvailable
        if hasMotionSensor == false { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0

        motionManager.startDeviceMotionUpdates(to: OperationQueue.main) {
            motion, error in

            guard let motion = motion else { return }

            self.checkOrientation(motion)
            self.readCircling(motion)
        }
    }

    // Is the phone being held with the top edge pointing at the floor.
    //
    // Held upright, gravity points along negative y. Turn the phone upside
    // down and it points along positive y instead, so a positive y reading
    // means the top edge is down.
    func checkOrientation(_ motion: CMDeviceMotion) {
        if needTopDown == false {
            isHeldRight = true
            return
        }
        isHeldRight = motion.gravity.y > tiltNeeded
    }

    // Works out how far round the circle the phone has travelled.
    func readCircling(_ motion: CMDeviceMotion) {

        // Only the movement across the circle matters, so use the two axes
        // that lie flat when the phone is pointing down: side to side (x)
        // and in and out of the screen (z).
        let acrossX = motion.userAcceleration.x
        let acrossZ = motion.userAcceleration.z

        // How strong the movement is in that flat plane.
        let strength = sqrt(acrossX * acrossX + acrossZ * acrossZ)

        // Too quiet to be a real circle, so ignore it and start fresh.
        // Without this, a still phone would jitter its way to a full lap.
        if strength < motionFloor {
            hasPreviousAngle = false
            return
        }

        let newAngle = atan2(acrossZ, acrossX)
        feedAngle(newAngle)
    }

    // Takes a new angle and adds however far it moved since the last one.
    func feedAngle(_ newAngle: Double) {
        if hasPreviousAngle == false {
            previousAngle = newAngle
            hasPreviousAngle = true
            return
        }

        var change = newAngle - previousAngle
        previousAngle = newAngle

        // Angles wrap around from +pi to -pi, which looks like a huge jump.
        if change > Double.pi { change = change - 2 * Double.pi }
        if change < -Double.pi { change = change + 2 * Double.pi }

        // A single frame should never contain most of a lap. Anything that
        // big is noise, not a person moving their arm.
        if abs(change) > 1.2 { return }

        // The first real movement decides which way counts as forwards.
        if turnDirection == 0 && abs(change) > 0.03 {
            if change > 0 {
                turnDirection = 1
            } else {
                turnDirection = -1
            }
        }

        let forwardTurn = change * turnDirection
        if forwardTurn > 0 {
            turnedThisFrame = turnedThisFrame + forwardTurn
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
        guard let touch = touches.first else { return }

        // Once the cream is on, taps place the strawberries.
        if hasPiped {
            placeBerry(near: touch.location(in: self))
            return
        }

        // Otherwise this is the fallback for devices with no sensor.
        isTouching = true
        previousTouchAngle = angleFromCake(touch.location(in: self))
        hasPreviousTouchAngle = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isFinished { return }
        if hasPiped { return }
        if isTouching == false { return }
        if allowTouchFallback == false { return }
        if hasMotionSensor { return }
        guard let touch = touches.first else { return }

        let newAngle = angleFromCake(touch.location(in: self))

        if hasPreviousTouchAngle == false {
            previousTouchAngle = newAngle
            hasPreviousTouchAngle = true
            return
        }

        var change = newAngle - previousTouchAngle
        previousTouchAngle = newAngle

        if change > Double.pi { change = change - 2 * Double.pi }
        if change < -Double.pi { change = change + 2 * Double.pi }

        if turnDirection == 0 && abs(change) > 0.03 {
            if change > 0 {
                turnDirection = 1
            } else {
                turnDirection = -1
            }
        }

        let forwardTurn = change * turnDirection
        if forwardTurn > 0 {
            turnedThisFrame = turnedThisFrame + forwardTurn
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        hasPreviousTouchAngle = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        hasPreviousTouchAngle = false
    }

    // The angle of a point measured from the middle of the cake.
    func angleFromCake(_ point: CGPoint) -> Double {
        let acrossX = Double(point.x) - centerX
        let acrossY = Double(point.y) - (propRestY - 10)
        return atan2(acrossY, acrossX)
    }

    // ---------------------------------------------------------------
    // PLACING THE STRAWBERRIES
    // ---------------------------------------------------------------

    func placeBerry(near point: CGPoint) {
        if berriesPlaced >= strawberryCount { return }

        // Only the next spot in the sequence counts.
        let target = spotPoints[berriesPlaced]
        let acrossX = Double(point.x) - Double(target.x)
        let acrossY = Double(point.y) - Double(target.y)
        let distance = sqrt(acrossX * acrossX + acrossY * acrossY)

        if distance > tapAccuracy {
            showWarning("Not on the spot")
            return
        }

        let berry = SKSpriteNode(color: colorBerry, size: CGSize(width: 20, height: 20))
        berry.position = target
        berry.zPosition = 1
        addChild(berry)
        berryNodes.append(berry)

        spotNodes[berriesPlaced].isHidden = true
        berriesPlaced = berriesPlaced + 1

        // Light up the next spot.
        if berriesPlaced < strawberryCount {
            spotNodes[berriesPlaced].isHidden = false
        }
    }

    func showWarning(_ words: String) {
        warningLabel.text = words
        warningLabel.removeAllActions()
        warningLabel.alpha = 1
        let wait = SKAction.wait(forDuration: 0.8)
        let fade = SKAction.fadeOut(withDuration: 0.4)
        warningLabel.run(SKAction.sequence([wait, fade]))
    }

    // ---------------------------------------------------------------
    // EVERY FRAME
    // ---------------------------------------------------------------

    override func readInput(secondsSinceLastFrame: Double) {

        if hasPiped == false {
            pipe(secondsSinceLastFrame: secondsSinceLastFrame)
        } else {
            let berryShare = (Double(berriesPlaced) / Double(strawberryCount))
                             * (1 - pipeShare)
            amountDone = pipeShare + berryShare
            isWorking = berriesPlaced > 0
            hintWhenIdle = "Tap the marked spots"
            hintWhenWorking = "Keep going"
        }
    }

    func pipe(secondsSinceLastFrame: Double) {

        // How fast the circles are being made.
        let speedRightNow = turnedThisFrame / secondsSinceLastFrame
        turnedThisFrame = 0

        // Heavy smoothing, because the acceleration signal is noisy at the
        // slow speeds this station asks for.
        currentSpeed = currentSpeed + (speedRightNow - currentSpeed) * 0.15

        isTooFast = currentSpeed > pipeTooFast

        // Cream needs the right grip AND a slow steady circle.
        let isMovingWell = currentSpeed >= pipeTooSlow && isTooFast == false
        let isSteady = isHeldRight && isMovingWell

        if isHeldRight == false {
            hintWhenIdle = "Point the top of the phone down"
        } else if isTooFast {
            showWarning("Careful, you might ruin the cake")
            hintWhenIdle = "Too fast, slow down"
        } else {
            hintWhenIdle = "Circle the phone slowly"
        }

        if isSteady {
            turnedSoFar = turnedSoFar + currentSpeed * secondsSinceLastFrame
        }

        isWorking = isSteady

        let turnsDone = turnedSoFar / (2 * Double.pi)
        amountDone = (turnsDone / turnsNeeded) * pipeShare
        if amountDone > pipeShare { amountDone = pipeShare }

        // Enough cream on the cake, so move to the strawberries.
        if turnsDone >= turnsNeeded {
            hasPiped = true
            amountDone = pipeShare
            spotNodes[0].isHidden = false
            warningLabel.text = ""
        }
    }

    override func animateProp(secondsSinceLastFrame: Double) {

        // Draw the cream as a spiral that grows with the piping.
        let turnsDone = turnedSoFar / (2 * Double.pi)
        var drawn = turnsDone
        if drawn > turnsNeeded { drawn = turnsNeeded }

        let steps = Int(drawn * 40)
        if steps > 1 {
            let path = CGMutablePath()
            for step in 0...steps {
                let along = Double(step) / Double(steps)
                let angle = along * drawn * 2 * Double.pi
                // The spiral winds outward as more cream goes on.
                let radius = 16 + along * 52
                let spotX = cos(angle) * radius
                let spotY = sin(angle) * radius * 0.6
                if step == 0 {
                    path.move(to: CGPoint(x: spotX, y: spotY))
                } else {
                    path.addLine(to: CGPoint(x: spotX, y: spotY))
                }
            }
            cream.path = path
        }

        // The cream flushes red while the player is going too fast.
        if isTooFast {
            cream.strokeColor = colorWarn
        } else {
            cream.strokeColor = colorCream
        }

        // Dim the cake while the phone is held wrong, so it is obvious why
        // nothing is happening.
        if hasPiped == false && isHeldRight == false {
            cake.alpha = 0.4
        } else {
            cake.alpha = 1
        }
    }
}


class DecorateScreen: SKScene{
    
    var overlay: DecorateOverlay!
    var timeOfLastFrame = 0.0
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        showEggscreen()
    }
    
    func showEggscreen() {
        overlay?.removeFromParent()
        
        let newOverlay = DecorateOverlay(screenSize: size, actionName: "Add whipping cream and macerated strawberries")
        
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
            let scene = DecorateScreen(size: geometry.size)
            scene.scaleMode = .resizeFill
            return scene
        }())
        .ignoresSafeArea()
    }
}
#endif
