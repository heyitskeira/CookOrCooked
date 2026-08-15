//
//  Untitled.swift
//  Cooked
//
//  Created by Keira on 10/08/26.
//

import SpriteKit

final class KitchenScene: SKScene {

    // MARK: State

    /// Called when the chef reaches the storage station. ContentView wires this
    /// to present the SwiftUI StorageView over the scene.
    var onOpenStorage: (() -> Void)?

    private let state = GameState()

    private var chef = SKShapeNode(circleOfRadius: 13)
    private var stationNodes: [StationID: SKShapeNode] = [:]
    private var stationPoints: [StationID: CGPoint] = [:]
    private var checklistLabels: [Int: SKLabelNode] = [:]

    private let hudTime = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let hudMess = SKLabelNode(fontNamed: "AvenirNext-Regular")
    private let toast   = SKLabelNode(fontNamed: "AvenirNext-Regular")

    private var overlay: SKNode?
    private var overlayFill: SKSpriteNode?
    private var overlayHint = SKLabelNode(fontNamed: "AvenirNext-Regular")
    private var activeAction: CookAction?
    private var cookProgress: TimeInterval = 0
    private var isHolding = false

    private var chefStation: StationID?
    private var isWalking = false
    private var lastUpdate: TimeInterval = 0

    private let ink = SKColor(white: 0.12, alpha: 1)
    private let paper = SKColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1)

    // MARK: Setup

    override func didMove(to view: SKView) {
        backgroundColor = paper
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
        chef.fillColor = SKColor(red: 0.85, green: 0.35, blue: 0.19, alpha: 1)
        chef.strokeColor = ink
        chef.lineWidth = 1.5
        chef.zPosition = 5
        chef.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        addChild(chef)
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

        if state.isOver {
            restart()
            return
        }
        if activeAction != nil {
            isHolding = true
            overlayHint.text = "Keep holding…"
            return
        }
        guard !isWalking else { return }

        let point = touch.location(in: self)
        if let target = nearestStation(to: point) {
            walk(to: target)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHolding = false
        if activeAction != nil { overlayHint.text = "Hold to cook" }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHolding = false
    }

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
        // Storage isn't a recipe action — it opens the SwiftUI pantry overlay.
        if station == .storage {
            onOpenStorage?()
            return
        }
        if let action = state.availableAction(at: station) {
            openStation(action)
        } else {
            showToast(state.blockReason(at: station))
        }
    }

    // MARK: Station overlay — this is the "going heads-down" moment

    private func openStation(_ action: CookAction) {
        activeAction = action
        cookProgress = 0
        isHolding = false

        let node = SKNode()
        node.zPosition = 100

        // Opaque fill. The kitchen, the timer and the checklist all vanish.
        let fill = SKSpriteNode(color: SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1),
                                size: size)
        fill.position = CGPoint(x: size.width / 2, y: size.height / 2)
        node.addChild(fill)
        overlayFill = fill

        let station = SKLabelNode(fontNamed: "AvenirNext-Regular")
        station.text = action.station.displayName.uppercased()
        station.fontSize = 12
        station.fontColor = SKColor(white: 0.55, alpha: 1)
        station.position = CGPoint(x: size.width / 2, y: size.height / 2 + 66)
        node.addChild(station)

        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        title.text = action.name
        title.fontSize = 26
        title.fontColor = .white
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 24)
        node.addChild(title)

        let barWidth: CGFloat = min(300, size.width - 80)
        let track = SKSpriteNode(color: SKColor(white: 0.25, alpha: 1),
                                 size: CGSize(width: barWidth, height: 10))
        track.position = CGPoint(x: size.width / 2, y: size.height / 2 - 16)
        node.addChild(track)

        let bar = SKSpriteNode(color: SKColor(red: 0.95, green: 0.6, blue: 0.25, alpha: 1),
                               size: CGSize(width: barWidth, height: 10))
        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        bar.position = CGPoint(x: size.width / 2 - barWidth / 2, y: size.height / 2 - 16)
        bar.xScale = 0.001
        bar.name = "progress"
        node.addChild(bar)

        overlayHint.text = "Hold to cook"
        overlayHint.fontSize = 14
        overlayHint.fontColor = SKColor(white: 0.6, alpha: 1)
        overlayHint.position = CGPoint(x: size.width / 2, y: size.height / 2 - 52)
        overlayHint.removeFromParent()
        node.addChild(overlayHint)

        let blind = SKLabelNode(fontNamed: "AvenirNext-Regular")
        blind.text = "You cannot see the kitchen while you work"
        blind.fontSize = 11
        blind.fontColor = SKColor(white: 0.4, alpha: 1)
        blind.position = CGPoint(x: size.width / 2, y: 30)
        node.addChild(blind)

        addChild(node)
        overlay = node
    }

    private func closeStation() {
        overlay?.removeFromParent()
        overlay = nil
        overlayFill = nil
        activeAction = nil
        isHolding = false
        cookProgress = 0
        refreshStations()
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        if lastUpdate == 0 { lastUpdate = currentTime }
        let dt = min(currentTime - lastUpdate, 0.1)
        lastUpdate = currentTime

        state.tick(dt)

        if let action = activeAction {
            if isHolding {
                cookProgress += dt
                if let bar = overlay?.childNode(withName: "progress") as? SKSpriteNode {
                    bar.xScale = max(0.001, CGFloat(cookProgress / action.duration))
                }
                if cookProgress >= action.duration {
                    state.complete(action)
                    closeStation()
                    showToast("\(action.name) — done")
                }
            }
        }

        refreshHUD()
        if state.isOver { presentEnd() }
    }

    private func refreshHUD() {
        // While heads-down, the HUD is hidden too. That is the point.
        let blind = (activeAction != nil)
        hudTime.isHidden = blind
        hudMess.isHidden = blind
        for label in checklistLabels.values { label.isHidden = blind }

        let seconds = Int(state.timeRemaining)
        hudTime.text = String(format: "%d:%02d", seconds / 60, seconds % 60)
        hudTime.fontColor = state.timeRemaining < 45 ? SKColor.red : ink
        hudMess.text = "mess \(state.mess)   ·   \(state.completedGoalCount)/\(Recipe.goalIDs.count)"

        guard !blind else { return }
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
            // Storage is always open for business.
            let ready = id == .storage || state.availableAction(at: id) != nil
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

    private func presentEnd() {
        guard overlay == nil else { return }
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
        overlay = node
        overlayFill = fill
    }

    private func restart() {
        overlay?.removeFromParent()
        overlay = nil
        overlayFill = nil
        activeAction = nil
        isHolding = false
        cookProgress = 0
        chefStation = nil
        isWalking = false
        chef.removeAllActions()
        chef.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        state.reset()
        refreshStations()
    }
}
