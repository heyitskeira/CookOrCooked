//
//  KitchenScene.swift
//  Cooked
//
//  Created by Keira on 10/08/26.
//

import SpriteKit

// Explicit even though SKScene already inherits main-actor isolation from
// UIResponder — this scene touches KitchenSession, which is @MainActor, and
// being explicit means a future SDK change can't silently break that.
@MainActor
final class KitchenScene: SKScene {

    // MARK: State

    /// nil = offline single player, exactly as before. Non-nil = the host's
    /// snapshot drives everything shared, and this scene only owns the local
    /// chef's movement (predicted locally so it stays smooth between packets).
    weak var session: KitchenSession?

    private let state = GameState()

    private var chef = SKShapeNode(circleOfRadius: 13)
    private var remoteChefs: [String: SKShapeNode] = [:]
    private var stationNodes: [StationID: SKShapeNode] = [:]
    private var stationPoints: [StationID: CGPoint] = [:]
    private var checklistLabels: [Int: SKLabelNode] = [:]

    private let hudTime = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let hudMess = SKLabelNode(fontNamed: "AvenirNext-Regular")
    private let toast   = SKLabelNode(fontNamed: "AvenirNext-Regular")

    /// The station screen currently open, if any. While this exists the
    /// player is heads-down and cannot see the kitchen.
    private var stationOverlay: StationOverlay?
    private var endOverlay: SKNode?
    private var activeAction: CookAction?

    private var chefStation: StationID?
    private var isWalking = false
    private var lastUpdate: TimeInterval = 0

    private let ink = SKColor(white: 0.12, alpha: 1)
    private let paper = SKColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1)

    // MARK: Setup

    override func didMove(to view: SKView) {
        backgroundColor = paper

        // Needed for the two finger pull on the egg screen.
        view.isMultipleTouchEnabled = true

        buildStations()
        buildChef()
        buildHUD()
        if Recipe.showRecipeChecklist { buildChecklist() }
        refreshStations()
    }

    private func buildStations() {
        for id in StationID.allCases {
            let point = CGPoint(x: id.unitPosition.x * size.width,
                                y: id.unitPosition.y * size.height)
            stationPoints[id] = point

            let node = SKShapeNode(rectOf: CGSize(width: 84, height: 52), cornerRadius: 10)
            node.position = point
            node.lineWidth = 1.5
            node.strokeColor = ink
            node.fillColor = .clear
            node.zPosition = 1
            addChild(node)
            stationNodes[id] = node

            let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            label.text = id.displayName
            label.fontSize = 11
            label.fontColor = ink
            label.verticalAlignmentMode = .center
            label.position = .zero
            node.addChild(label)
        }
    }

    private func buildChef() {
        let index = session?.localPlayer?.colorIndex ?? 0
        chef.fillColor = Self.colour(index)
        chef.strokeColor = ink
        chef.lineWidth = 1.5
        chef.zPosition = 5
        chef.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        addChild(chef)
    }

    private static func colour(_ index: Int) -> SKColor {
        let c = PlayerPalette.components(index)
        return SKColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    // MARK: Remote chefs
    //
    // One circle per other player, positioned from the host's snapshot. Unit
    // coordinates are used on the wire so a host on an iPad and a guest on an
    // iPhone put each other in the same place.

    private func syncRemoteChefs(_ session: KitchenSession) {
        let others = session.snapshot.chefs.filter { $0.playerID != session.localPlayerID }
        let living = Set(others.map(\.playerID))

        for (id, node) in remoteChefs where !living.contains(id) {
            node.removeFromParent()
            remoteChefs.removeValue(forKey: id)
        }

        for other in others {
            let player = session.players.first { $0.id == other.playerID }
            let node = remoteChefs[other.playerID] ?? makeRemoteChef(for: other.playerID)
            let target = CGPoint(x: CGFloat(other.x) * size.width,
                                 y: CGFloat(other.y) * size.height)

            // Snapshots land at 10Hz; the scene runs at 60. Easing between
            // them hides the gap without any real interpolation machinery.
            node.position = CGPoint(x: node.position.x + (target.x - node.position.x) * 0.35,
                                    y: node.position.y + (target.y - node.position.y) * 0.35)

            let connected = player?.isConnected ?? true
            node.fillColor = connected
                ? Self.colour(player?.colorIndex ?? 1)
                : SKColor(white: 0.72, alpha: 1)
            node.alpha = connected ? 1 : 0.5
            // A ring means they're heads-down at a station and can't see you.
            node.lineWidth = other.isBusy ? 4 : 1.5
        }
    }

    private func makeRemoteChef(for id: String) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: 13)
        node.strokeColor = ink
        node.lineWidth = 1.5
        node.zPosition = 4
        node.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        addChild(node)
        remoteChefs[id] = node
        return node
    }

    private func buildHUD() {
        hudTime.fontSize = 22
        hudTime.fontColor = ink
        hudTime.horizontalAlignmentMode = .right
        hudTime.position = CGPoint(x: size.width - 20, y: size.height - 38)
        hudTime.zPosition = 20
        addChild(hudTime)

        hudMess.fontSize = 13
        hudMess.fontColor = ink
        hudMess.horizontalAlignmentMode = .right
        hudMess.position = CGPoint(x: size.width - 20, y: size.height - 60)
        hudMess.zPosition = 20
        addChild(hudMess)

        toast.fontSize = 14
        toast.fontColor = ink
        toast.horizontalAlignmentMode = .center
        toast.position = CGPoint(x: size.width * 0.5, y: 26)
        toast.zPosition = 20
        toast.alpha = 0
        addChild(toast)
    }

    private func buildChecklist() {
        var y = size.height - 38
        for action in Recipe.actions where !action.isRepeatable {
            let label = SKLabelNode(fontNamed: "AvenirNext-Regular")
            label.fontSize = 11
            label.horizontalAlignmentMode = .left
            label.position = CGPoint(x: 16, y: y)
            label.zPosition = 20
            addChild(label)
            checklistLabels[action.id] = label
            y -= 15
        }
    }

    // MARK: Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        // The game is over, so any tap restarts it.
        if state.isOver {
            // Only offline games restart on tap. In a networked game the host
            // owns the lifecycle, and one player tapping must not silently
            // reset everyone else's kitchen.
            if session == nil { restart() }
            return
        }

        // A station screen is open, so it handles its own touches.
        if stationOverlay != nil { return }

        // Already walking somewhere.
        if isWalking { return }

        let point = touch.location(in: self)
        if let target = nearestStation(to: point) {
            walk(to: target)
        }
    }

    /// Finds the station closest to where the player tapped, if it is
    /// close enough to count.
    private func nearestStation(to point: CGPoint) -> StationID? {
        var best: StationID?
        var bestDistance: CGFloat = 60
        for (id, position) in stationPoints {
            let dx = position.x - point.x
            let dy = position.y - point.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance < bestDistance {
                bestDistance = distance
                best = id
            }
        }
        return best
    }

    // MARK: Movement

    private func walk(to station: StationID) {
        guard let destination = stationPoints[station] else { return }
        isWalking = true
        chefStation = nil

        let dx = destination.x - chef.position.x
        let dy = destination.y - chef.position.y
        let distance = sqrt(dx * dx + dy * dy)
        let duration = TimeInterval(distance / Recipe.chefSpeed)

        chef.removeAllActions()
        let move = SKAction.move(to: destination, duration: duration)
        move.timingMode = .easeInEaseOut
        chef.run(move) { [weak self] in
            self?.isWalking = false
            self?.arrive(at: station)
        }
    }

    private func arrive(at station: StationID) {
        chefStation = station
        if let action = state.availableAction(at: station) {
            openStation(action)
        } else {
            showToast(state.blockReason(at: station))
        }
    }

    // MARK: Station screens — the "going heads-down" moment

    /// Builds the right screen for this action and shows it.
    private func makeOverlay(for action: CookAction) -> StationOverlay {
        switch action.motion {
        case .chop:
            return ChopOverlay(screenSize: size, actionName: action.name)
        case .whisk:
            return WhiskOverlay(screenSize: size, actionName: action.name)
        case .mix:
            return MixOverlay(screenSize: size, actionName: action.name)
        case .sift:
            return SiftOverlay(screenSize: size, actionName: action.name)
        case .melt:
            return MeltOverlay(screenSize: size, actionName: action.name)
        case .breakEgg:
            return EggOverlay(screenSize: size, actionName: action.name)
        case .hold:
            return HoldOverlay(screenSize: size, actionName: action.name)
        }
    }

    private func openStation(_ action: CookAction) {
        activeAction = action

        let overlay = makeOverlay(for: action)

        // When the player finishes the motion, mark the action done and
        // put them back in the kitchen.
        overlay.whenFinished = { [weak self] in
            guard let self = self else { return }
            self.state.complete(action)
            self.closeStation()
            self.showToast("\(action.name) — done")
        }

        addChild(overlay)
        stationOverlay = overlay

        // Hide the kitchen HUD while heads-down.
        setHUDHidden(true)
    }

    private func closeStation() {
        stationOverlay?.cleanUp()
        stationOverlay?.removeFromParent()
        stationOverlay = nil
        activeAction = nil

        setHUDHidden(false)
        refreshStations()
    }

    private func setHUDHidden(_ hidden: Bool) {
        hudTime.isHidden = hidden
        hudMess.isHidden = hidden
        toast.isHidden = hidden
        for label in checklistLabels.values { label.isHidden = hidden }
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        if lastUpdate == 0 { lastUpdate = currentTime }
        var gap = currentTime - lastUpdate
        if gap > 0.1 { gap = 0.1 }
        lastUpdate = currentTime

        if let session {
            // The host's snapshot is the truth. Mirror it, then draw everyone
            // else, then tell the host where we are.
            state.apply(session.snapshot)
            syncRemoteChefs(session)
            session.reportPosition(x: Double(chef.position.x / size.width),
                                   y: Double(chef.position.y / size.height),
                                   station: chefStation?.rawValue,
                                   isBusy: activeAction != nil)
            // Someone else finishing an action can unlock a station in front
            // of us, so availability has to be re-checked continuously rather
            // than only when we close an overlay.
            refreshStations()
        } else {
            state.tick(dt)
        }

        if let action = activeAction {
            if isHolding {
                cookProgress += dt
                if let bar = overlay?.childNode(withName: "progress") as? SKSpriteNode {
                    bar.xScale = max(0.001, CGFloat(cookProgress / action.duration))
                }
                if cookProgress >= action.duration {
                    // Networked: report it and wait for the host to confirm via
                    // the next snapshot. Never apply it locally as well, or a
                    // repeatable action would count its mess twice.
                    if let session {
                        session.reportCompletion(actionID: action.id)
                    } else {
                        state.complete(action)
                    }
                    closeStation()
                    showToast("\(action.name) — done")
                }
            }
        }

        refreshHUD()

        if state.isOver { presentEnd() }
    }

    private func refreshHUD() {
        // Nothing to draw while the player is heads-down.
        if stationOverlay != nil { return }

        let seconds = Int(state.timeRemaining)
        hudTime.text = String(format: "%d:%02d", seconds / 60, seconds % 60)
        hudTime.fontColor = state.timeRemaining < 45 ? SKColor.red : ink
        hudMess.text = "\(state.completedGoalCount)/\(Recipe.goalIDs.count)"

        for (id, label) in checklistLabels {
            guard let action = Recipe.action(id) else { continue }
            if state.completed.contains(id) {
                label.text = "· \(action.name)"
                label.fontColor = SKColor(white: 0.62, alpha: 1)
            } else if state.isUnlocked(action) {
                label.text = "→ \(action.name)"
                label.fontColor = SKColor(red: 0.15, green: 0.45, blue: 0.25, alpha: 1)
            } else {
                label.text = "  \(action.name)"
                label.fontColor = SKColor(white: 0.75, alpha: 1)
            }
        }
    }

    /// Green outline = something is doable here right now.
    private func refreshStations() {
        for (id, node) in stationNodes {
            let ready = state.availableAction(at: id) != nil
            node.strokeColor = ready
                ? SKColor(red: 0.15, green: 0.55, blue: 0.30, alpha: 1)
                : SKColor(white: 0.72, alpha: 1)
            node.lineWidth = ready ? 2.5 : 1.5
        }
    }

    private func showToast(_ text: String) {
        toast.removeAllActions()
        toast.text = text
        toast.alpha = 1
        toast.run(.sequence([.wait(forDuration: 1.6), .fadeOut(withDuration: 0.4)]))
    }

    // MARK: End of game

    private func presentEnd() {
        if endOverlay != nil { return }

        // Close any station screen that was still open.
        closeStation()

        let node = SKNode()
        node.zPosition = 200

        let fill = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.92), size: size)
        fill.position = CGPoint(x: size.width / 2, y: size.height / 2)
        node.addChild(fill)

        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        title.text = state.didWin ? "Cook" : "Cooked"
        title.fontSize = 44
        title.fontColor = .white
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 10)
        node.addChild(title)

        let sub = SKLabelNode(fontNamed: "AvenirNext-Regular")
        sub.text = state.didWin
            ? "Served with \(Int(state.timeRemaining))s to spare — tap to replay"
            : "\(state.completedGoalCount)/\(Recipe.goalIDs.count) done — tap to replay"
        sub.fontSize = 14
        sub.fontColor = SKColor(white: 0.7, alpha: 1)
        sub.position = CGPoint(x: size.width / 2, y: size.height / 2 - 28)
        node.addChild(sub)

        addChild(node)
        endOverlay = node
    }

    private func restart() {
        endOverlay?.removeFromParent()
        endOverlay = nil

        closeStation()

        chefStation = nil
        isWalking = false
        chef.removeAllActions()
        chef.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)

        state.reset()
        refreshStations()
    }
}
