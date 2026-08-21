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

    // Added (additive):
    /// The local chef's hands. Gating reads this to require the right utensil.
    var inventory: PlayerInventory?
    /// Called when the chef reaches storage — ContentView opens the pantry.
    var onOpenStorage: (() -> Void)?
    /// Called when the chef reaches the drawer — opens the 2x2 shelf overlay.
    var onOpenDrawer: (() -> Void)?
    /// True while a station screen is up. SwiftUI draws its own chrome on top
    /// of the SpriteView, and nothing inside the scene can hide it — so the
    /// inventory bar would sit over the station screen showing the same two
    /// slots the hands were hidden to get out of the way.
    var onHeadsDownChanged: ((Bool) -> Void)?

    /// Called when the chef reaches any other station — SwiftUI shows the
    /// station popup (drop/pick-up vs do-action). The scene no longer opens the
    /// minigame itself; `beginAction` does, once the popup asks it to.
    var onArriveStation: ((StationID) -> Void)?

    /// The action a chef chose from the popup and is now queueing for. Kept so
    /// the grant opens *that* action, not just whatever `availableAction` picks
    /// first (bowls offer several).
    private var pendingAction: CookAction?

    /// Called when a producing action finishes — SwiftUI shows the "you got a
    /// prep" result popup (station id + the produced foodID).
    var onActionFinished: ((StationID, String) -> Void)?

    /// Called when a chef carrying something rotten taps anywhere but the bin —
    /// SwiftUI shows the "throw it away first" alert.
    var onRottenBlocked: (() -> Void)?

    /// Rot in hand locks the chef out of the whole kitchen except the garbage
    /// bin: no storage, no drawer, no station, no serve circle.
    private var isCarryingRotten: Bool { inventory?.isHoldingRotten == true }
    /// Ingredients deposited per station when playing offline (no session). In a
    /// networked game the host owns this via the snapshot instead.
    private var localDeposited: [StationID: Set<String>] = [:]

    /// Finished prep sitting on a station when playing offline (no session).
    private var localOutput: [StationID: String] = [:]

    /// What's been dropped at a station — from the snapshot if networked, else
    /// the local store.
    private func depositedFoods(at station: StationID) -> Set<String> {
        if let session { return Set(session.snapshot.depositedFoods(at: station)) }
        return localDeposited[station] ?? []
    }

    /// The finished prep on a station (snapshot if networked, else local).
    private func outputFood(at station: StationID) -> String? {
        if let session { return session.outputFood(at: station) }
        return localOutput[station]
    }

    /// Drop an ingredient at a station (host-authoritative when networked).
    private func deposit(_ foodID: String, at station: StationID) {
        if let session { session.deposit(foodID, at: station) }
        else { localDeposited[station, default: []].insert(foodID) }
    }

    private let state = GameState()

    private var chef = SKShapeNode(circleOfRadius: 13)
    private var remoteChefs: [String: SKShapeNode] = [:]
    private var stationNodes: [StationID: SKShapeNode] = [:]
    private var stationPoints: [StationID: CGPoint] = [:]
    /// "Aya is here" caption under an occupied station. Hidden when free.
    private var stationOwnerLabels: [StationID: SKLabelNode] = [:]
    /// Last appearance rendered per station, so the per-frame refresh can skip
    /// stations that haven't changed. See `refreshStations`.
    private var stationLooks: [StationID: String] = [:]
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

    /// The chef's hands, parked in the bottom corners of the map.
    private var hands: HandsNode?

    /// The serve zone, the SERVE button and the "who are we waiting on" line.
    private var serveNode: ServeRitualNode?
    /// Whether this chef is standing in the circle right now.
    private var isInServeZone = false
    /// True while this device's finger is down on the SERVE button.
    private var isHoldingServe = false
    /// The touch doing the holding, so lifting a *different* finger doesn't
    /// release the button.
    private var serveTouch: UITouch?
    /// When this device's finger went down, and whether the host has confirmed
    /// the hold yet. Both exist so "the host dropped my hold" can be told apart
    /// from "the host hasn't answered yet" — see `refreshServe`.
    private var serveHoldStartedAt: TimeInterval?
    private var serveHoldAcknowledged = false
    /// Offline only — when the local bar started filling. Networked games keep
    /// all of this on the host, where it belongs.
    private var localChargeStartedAt: TimeInterval?
    /// White sheet for the flash between a station screen and the kitchen.
    private var flash: SKSpriteNode?

    /// The station this chef has walked to and is queueing for. Set on arrival,
    /// cleared once the host grants it or the chef walks off. While it is set
    /// the chef simply stands at the counter waiting their turn.
    private var waitingStation: StationID?
    /// Stops the "someone's using this" toast re-firing every frame.
    private var lastWaitToastFor: StationID?

    private let ink = SKColor(white: 0.12, alpha: 1)
    private let paper = SKColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1)
    /// The room floor — a shade darker than the page, so the map reads as a
    /// place rather than as diagram on blank paper.
    private let floorColour = SKColor(red: 0.91, green: 0.89, blue: 0.83, alpha: 1)
    /// Counter tops. Filled, not outlined: eight hairline rectangles on cream
    /// was the reason nothing on this screen was legible.
    private let counterColour = SKColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1)
    private let counterEdge = SKColor(red: 0.62, green: 0.55, blue: 0.45, alpha: 1)
    private let readyColour = SKColor(red: 0.15, green: 0.55, blue: 0.30, alpha: 1)

    /// Station boxes. Bigger than they were — the old 84x52 could not hold
    /// "Chopping" at a legible size on a phone.
    private static let stationSize = CGSize(width: 96, height: 58)

    // MARK: Setup

    override func didMove(to view: SKView) {
        backgroundColor = paper

        // Needed for the two finger pull on the egg screen.
        view.isMultipleTouchEnabled = true

        buildFloor()
        buildStations()
        buildChef()
        buildHUD()
        buildHands()
        buildServeRitual()
        if Recipe.showRecipeChecklist { buildChecklist() }
        refreshStations()
    }

    /// The scene is going away — the host quit, the player backed out, SwiftUI
    /// rebuilt the view. Anything a station screen was holding onto has to be
    /// handed back here, because `closeStation` is never reached on this path:
    /// the melt station owns the microphone, and leaving it owned means the
    /// music stays ducked to a whisper for the rest of the app's life.
    override func willMove(from view: SKView) {
        super.willMove(from: view)
        stationOverlay?.cleanUp()
    }

    private func buildHands() {
        // `didMove` can run more than once for the same scene, and a second set
        // of hands would be orphaned on screen forever.
        guard hands == nil else { return }

        let made = HandsNode(screenSize: size)
        addChild(made)
        hands = made
        refreshHands()
        made.appear()

        // Built once and reused. Allocating a full-screen sprite every time a
        // station closes would be a hitch at exactly the wrong moment.
        let sheet = SKSpriteNode(color: .white, size: size)
        sheet.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sheet.zPosition = 300
        sheet.alpha = 0
        // Hidden rather than transparent: an invisible screen-sized quad still
        // gets drawn every frame.
        sheet.isHidden = true
        addChild(sheet)
        flash = sheet
    }

    private func buildServeRitual() {
        guard serveNode == nil else { return }
        let made = ServeRitualNode(sceneSize: size)
        // Under the chefs (5) and the stations (1) — it's paint on the floor.
        // The button inside it carries its own zPosition and still lands above
        // the HUD.
        made.zPosition = 0.5
        addChild(made)
        serveNode = made
    }

    /// The scene is created at the safe-area size and resized to the view's
    /// real bounds a moment later, so anything pinned to an edge or sized to
    /// the screen has to be told.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        hands?.layout(for: size)
        serveNode?.layout(for: size)
        flash?.size = size
        flash?.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Fills the hands from what the chef is actually holding.
    private func refreshHands() {
        // Straight from the model. This used to fall back to a local stand-in
        // because finished preps didn't reach the inventory yet; they do now
        // (see `openStation`), so there is one source of truth again.
        hands?.setItems(prep: inventory?.ingredient?.id,
                        isRotten: inventory?.ingredient?.isRotten ?? false,
                        utensil: inventory?.utensil?.id)
    }

    /// A quick white wipe. Covers the swap from the station screen back to the
    /// kitchen so the two never appear in the same frame.
    private func flashToKitchen() {
        guard let flash else { return }
        flash.removeAllActions()
        flash.isHidden = false
        flash.alpha = 0.9
        flash.run(.sequence([.fadeOut(withDuration: 0.28),
                             .run { flash.isHidden = true }]))
    }

    private func cancelFlash() {
        flash?.removeAllActions()
        flash?.alpha = 0
        flash?.isHidden = true
    }

    /// The room: a floor slab inset from the screen edge, so the counters
    /// around it read as being against walls.
    private func buildFloor() {
        let floor = SKShapeNode(rectOf: CGSize(width: size.width - 24,
                                               height: size.height - 24),
                                cornerRadius: 26)
        floor.position = CGPoint(x: size.width / 2, y: size.height / 2)
        floor.fillColor = floorColour
        floor.strokeColor = counterEdge.withAlphaComponent(0.35)
        floor.lineWidth = 2
        floor.zPosition = -1
        addChild(floor)
    }

    private func buildStations() {
        for id in StationID.allCases {
            let point = CGPoint(x: id.unitPosition.x * size.width,
                                y: id.unitPosition.y * size.height)
            stationPoints[id] = point

            let node = SKShapeNode(rectOf: Self.stationSize, cornerRadius: 12)
            node.position = point
            node.lineWidth = 2.5
            node.strokeColor = counterEdge
            node.fillColor = counterColour
            node.zPosition = 1
            addChild(node)
            stationNodes[id] = node

            let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
            label.text = id.displayName
            label.fontSize = 14
            label.fontColor = ink
            label.verticalAlignmentMode = .center
            label.position = .zero
            node.addChild(label)

            // Sits just under the box so it never collides with the station
            // name. Only visible while someone is working here.
            let owner = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            owner.fontSize = 10
            owner.verticalAlignmentMode = .center
            owner.position = CGPoint(x: 0, y: -Self.stationSize.height / 2 - 11)
            owner.zPosition = 2
            owner.isHidden = true
            node.addChild(owner)
            stationOwnerLabels[id] = owner
        }
    }

    private func buildChef() {
        let index = session?.localPlayer?.colorIndex ?? 0
        chef.fillColor = Self.colour(index)
        chef.strokeColor = ink
        chef.lineWidth = 1.5
        chef.zPosition = 5
        chef.position = spawnPoint(forColorIndex: index)
        addChild(chef)
    }

    /// Kick-off position: in the middle of the ring, spread out so four chefs
    /// don't start stacked on each other. This is the same spot the team has to
    /// come back to in order to serve — the match ends where it began.
    private func spawnPoint(forColorIndex index: Int) -> CGPoint {
        let unit = ServeRitual.spawnUnitPosition(forColorIndex: index)
        return CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }

    /// Built once. `refreshStations` runs every frame, and allocating a colour
    /// per station per frame is pure garbage for the collector to chase.
    private static let palette: [SKColor] = PlayerPalette.rgb.map {
        SKColor(red: $0.r, green: $0.g, blue: $0.b, alpha: 1)
    }
    private static let paletteFills: [SKColor] = palette.map {
        $0.withAlphaComponent(0.22)
    }

    private static func colour(_ index: Int) -> SKColor {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    private static func fill(_ index: Int) -> SKColor {
        paletteFills[((index % paletteFills.count) + paletteFills.count) % paletteFills.count]
    }

    // MARK: Remote chefs
    //
    // One circle per other player, positioned from the host's snapshot. Unit
    // coordinates are used on the wire so a host on an iPad and a guest on an
    // iPhone put each other in the same place.

    private func syncRemoteChefs(_ session: KitchenSession) {
        let others = session.snapshot.chefs.filter { $0.playerID != session.localPlayerID }
        let living = Set(others.map(\ChefSnapshot.playerID))

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
        // Start them on their own spawn stone rather than dead centre, so the
        // first snapshot doesn't drag them across the clearing.
        let index = session?.player(id)?.colorIndex ?? 1
        node.position = spawnPoint(forColorIndex: index)
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

        let point = touch.location(in: self)

        // The SERVE button is checked before the walking guard on purpose: the
        // press has to land the moment you arrive, and a stray animation still
        // running must not eat it.
        if let serveNode, serveNode.buttonContains(point) {
            serveTouch = touch
            beginServeHold()
            return
        }

        // Already walking somewhere.
        if isWalking { return }

        // Carrying rot, the bin is the only place worth walking to. Refusing
        // the tap here rather than on arrival means the chef isn't marched
        // across the kitchen just to be told no.
        if isCarryingRotten, nearestStation(to: point) != .trash {
            onRottenBlocked?()
            return
        }

        // Tapping the circle walks you into it. It isn't a station — that's the
        // whole point of it — so it gets its own target.
        if let serveNode, !serveNode.isHidden, isServeZoneTap(point) {
            walkToServeZone()
            return
        }

        if let target = nearestStation(to: point) {
            walk(to: target)
        }
    }

    /// Sliding the finger off the button counts as letting go. "Keep your thumb
    /// on it" has to mean the thumb, not the screen.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isHoldingServe, let serveTouch, touches.contains(serveTouch),
              let serveNode else { return }
        if !serveNode.buttonContains(serveTouch.location(in: self)) {
            self.serveTouch = nil
            endServeHold()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseServeIfNeeded(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseServeIfNeeded(touches)
    }

    /// Lifting the finger that was on the button is the whole "let go"
    /// mechanic, so it has to be the *same* finger — with two hands on the
    /// screen, releasing the other one must not empty the bar.
    private func releaseServeIfNeeded(_ touches: Set<UITouch>) {
        guard let serveTouch, touches.contains(serveTouch) else { return }
        self.serveTouch = nil
        endServeHold()
    }

    private func isServeZoneTap(_ point: CGPoint) -> Bool {
        guard let serveNode else { return false }
        let dx = point.x - serveNode.zonePoint.x
        let dy = point.y - serveNode.zonePoint.y
        // Barely wider than the circle. Any more and it starts eating the
        // Table station's own tap radius, which sits just above it.
        return sqrt(dx * dx + dy * dy) <= ServeRitual.zoneRadius(for: size) + 8
    }

    /// What can be done at this station right now.
    ///
    /// Everything `GameState` offers, minus serving. Serving used to be an
    /// ordinary action at the oven, which meant one chef could walk over and
    /// end the game on their own — the exact thing the gather-and-press ritual
    /// exists to prevent. It now happens only in the middle of the room.
    private func stationAction(at station: StationID) -> CookAction? {
        guard let action = state.availableAction(at: station),
              action.id != ServeRitual.actionID else { return nil }
        return action
    }

    /// Finds the station closest to where the player tapped, if it is
    /// close enough to count.
    private func nearestStation(to point: CGPoint) -> StationID? {
        var best: StationID?
        var bestDistance: CGFloat = 66
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

        // Leaving is what frees a station for everyone else, including leaving
        // a queue we never got to the front of.
        session?.releaseStation()
        waitingStation = nil
        lastWaitToastFor = nil

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

    /// Walk back to your own mark in the middle of the room.
    ///
    /// Not to the centre of the circle: everybody heading for the same point
    /// would pile four chefs on top of each other, and the reason the marks
    /// exist is so the team can see who has and hasn't come back. You end the
    /// match on the spot you started it.
    private func walkToServeZone() {
        guard serveNode != nil else { return }

        session?.releaseStation()
        waitingStation = nil
        lastWaitToastFor = nil

        isWalking = true
        chefStation = nil

        let destination = spawnPoint(forColorIndex: session?.localPlayer?.colorIndex ?? 0)
        let dx = destination.x - chef.position.x
        let dy = destination.y - chef.position.y
        let duration = TimeInterval(sqrt(dx * dx + dy * dy) / Recipe.chefSpeed)

        chef.removeAllActions()
        let move = SKAction.move(to: destination, duration: duration)
        move.timingMode = .easeInEaseOut
        chef.run(move) { [weak self] in
            self?.isWalking = false
        }
    }

    // MARK: Serving together

    /// Runs every frame. Works out whether this chef is in the circle, tells
    /// the host, and redraws from whatever the host says the team is doing.
    private func refreshServe() {
        guard let serveNode, let serve = ServeRitual.action else { return }

        let unlocked = state.isUnlocked(serve)
        let dx = chef.position.x - serveNode.zonePoint.x
        let dy = chef.position.y - serveNode.zonePoint.y
        // A chef holding rot can't be part of the ritual — the tap gate keeps
        // them out of the circle, and this keeps them out of the host's count
        // if they were already standing on their mark when the rot landed.
        let inZone = unlocked && !isCarryingRotten
            && sqrt(dx * dx + dy * dy) <= ServeRitual.zoneRadius(for: size)

        if inZone != isInServeZone {
            isInServeZone = inZone
            // Step off your mark and your hold goes with you, finger down or
            // not. Otherwise you could press and walk away.
            if !inZone { endServeHold() }
        }
        session?.reportServeReady(inZone)

        var look = ServeRitualNode.State()
        look.unlocked = unlocked

        if let session {
            // Everything here comes from the host's snapshot. This screen never
            // works out for itself that the team served — it only reports a
            // finger going down and coming back up.
            look.total = max(session.connectedCount, 1)
            look.gathered = session.snapshot.serveReady.count
            look.armed = session.snapshot.serveArmed
            look.holdingCount = session.snapshot.serveHolding.count
            look.progress = session.snapshot.serveProgress

            // The pressed-in look comes from this device's own finger, not from
            // the snapshot — a button that waits for a network round trip
            // before it moves feels broken on the one input that has to feel
            // immediate.
            look.holding = isHoldingServe

            // But the *outcome* is still the host's. If it dropped our hold —
            // somebody stepped off a mark, or we pressed early and the gather
            // window ran out — let go locally too, so the button pops out and
            // the player knows they have to press again rather than standing
            // there with a dead finger on the screen.
            //
            // The two flags below are the whole point. "I'm not in the host's
            // list" means two completely different things depending on when you
            // ask: before the first acknowledgement it just means the answer is
            // still in flight, and treating that as a refusal cancelled every
            // hold one frame after it started — the button appeared to do
            // nothing at all. Only believe a refusal once the host has either
            // confirmed us at least once, or had a fair chance to.
            let acknowledged = session.snapshot.serveHolding.contains(session.localPlayerID)
            if acknowledged { serveHoldAcknowledged = true }

            if isHoldingServe, session.snapshot.serveArmed, !acknowledged,
               session.snapshot.serveProgress == 0 {
                let waited = Date.timeIntervalSinceReferenceDate - (serveHoldStartedAt ?? 0)
                if serveHoldAcknowledged || waited > ServeRitual.holdAckGrace {
                    endServeHold()
                    serveNode.nudge()
                    look.holding = false
                }
            }
        } else {
            // Offline there is nobody to be in time with, so holding on your own
            // mark fills the bar by itself. Same two phases, one player — kept
            // working so the whole flow can be tested on one device.
            look.total = 1
            look.gathered = inZone ? 1 : 0
            look.armed = unlocked && inZone
            look.holding = isHoldingServe
            look.holdingCount = isHoldingServe ? 1 : 0

            if isHoldingServe, look.armed {
                let now = Date.timeIntervalSinceReferenceDate
                let startedAt = localChargeStartedAt ?? now
                localChargeStartedAt = startedAt
                look.progress = min(1, (now - startedAt) / ServeRitual.chargeDuration)

                if look.progress >= 1 {
                    state.complete(serve)
                    endServeHold()
                    showToast("Served!")
                }
            } else {
                localChargeStartedAt = nil
            }
        }

        serveNode.apply(look)
    }

    /// Finger down on the button.
    ///
    /// Nothing is decided here. The hold is *reported*; whether it turns into a
    /// served cake depends on everyone else's finger being down at the same
    /// time, which only the host can see.
    private func beginServeHold() {
        guard let serveNode, let serve = ServeRitual.action,
              state.isUnlocked(serve) else { return }

        guard isInServeZone else {
            showToast("Get back on your mark first")
            serveNode.nudge()
            return
        }

        if let session {
            guard session.snapshot.serveArmed else {
                showToast("Wait for the whole kitchen to gather")
                serveNode.nudge()
                return
            }
            session.setServeHold(true)
        }

        isHoldingServe = true
        serveHoldStartedAt = Date.timeIntervalSinceReferenceDate
        serveHoldAcknowledged = false
    }

    /// Finger up — or the chef wandered off, or the game ended underneath us.
    private func endServeHold() {
        guard isHoldingServe else { return }
        isHoldingServe = false
        serveTouch = nil
        serveHoldStartedAt = nil
        serveHoldAcknowledged = false
        localChargeStartedAt = nil
        session?.setServeHold(false)
    }

    private func arrive(at station: StationID) {
        chefStation = station

        // Storage isn't a recipe action — it opens the SwiftUI pantry overlay.
        if station == .storage {
            onOpenStorage?()
            return
        }

        // Neither is the drawer — it opens its own 2x2 shelf overlay.
        if station == .drawer {
            onOpenDrawer?()
            return
        }
        
//        if station == .bowl1{
//            ChooseAction()
//        }
//        
//        if station == .bowl2 {
//            ChooseAction()
//        }
        
        switch evaluateStation(station) {
        case .blocked:
            return

        case .ready(let action):
            // Offline: nobody to share the kitchen with.
            guard let session else {
                openStation(action)
                return
            }

            // Networked: ask the host for the station and stand here until it
            // says yes. `resolveWaiting` opens the screen when the answer
            // arrives, which may be immediately or may be after the current
            // occupant walks off.
            waitingStation = station
            lastWaitToastFor = nil
            session.claimStation(station)
        }
    }

    private enum StationEntry {
        case ready(CookAction)
        /// Nothing to open. A toast has already explained why, or the chef's
        /// ingredient was deposited and that was the whole visit.
        case blocked
    }

    /// Every check that must pass before a station screen opens.
    ///
    /// This lives in one place because there are two ways in: walking up to a
    /// free station (`arrive`) and being handed one you queued for
    /// (`resolveWaiting`). The queued path used to skip all of this and open
    /// whatever was available at that instant, which dropped a waiting chef
    /// into an action they never chose — and the action's product then
    /// overwrote whatever they were holding.
    private func evaluateStation(_ station: StationID) -> StationEntry {
        guard let action = state.availableAction(at: station) else {
            showToast(state.blockReason(at: station))
            return .blocked
            // The recipe itself says no — nothing to queue for.
            guard let action = stationAction(at: station) else {
                // Serving used to happen here, and `blockReason` still thinks it
                // does — it would say "Not ready yet" to someone holding a
                // finished cake. Point them at the middle of the room instead.
                if let serve = ServeRitual.action, station == serve.station,
                   state.isUnlocked(serve) {
                    showToast("Take it to the middle — everyone serves together")
                } else {
                    showToast(state.blockReason(at: station))
                }
            }
        }

        // Deposit: if the chef is holding a raw ingredient this action still
        // needs, drop it here and stop. (Host-authoritative in a networked game.)

        // Serving is no longer something one chef does at the oven: the whole
        // team has to gather in the middle of the room and press together (see
        // ServeRitual). Point anyone who walks up here holding the finished
        // cake at the floor, rather than opening a popup that cannot serve.
        if let serve = ServeRitual.action, station == serve.station,
           state.isUnlocked(serve) {
            showToast("Take it to the middle — everyone serves together")
            return
        }

        // Every other station now shows the SwiftUI popup (drop/pick-up vs do
        // action). The popup calls back into `beginAction` if the chef acts.
        onArriveStation?(station)
    }

    /// Start a specific action the chef picked from the station popup. Runs the
    /// gate (station not blocked by a leftover prep, all ingredients deposited,
    /// right utensil) then opens the minigame — directly offline, or via the
    /// host's station lock in a networked game.
    func beginAction(_ action: CookAction) {
        // Work happens at the counter the chef is STANDING at, which is not
        // always `action.station`: the two bowls are interchangeable, so "Sift
        // flour" (declared on bowl1) is offered at bowl2 as well. Reading the
        // declared station instead of the real one meant the deposits were
        // looked up in the wrong bowl and the gate answered "Need: Flour" for
        // flour the chef had just dropped in front of them.
        let where_ = workingStation(for: action)

        // The bin consumes what's in the hand, not what's deposited, so it gets
        // its own gate: rot in hand, or there is nothing to throw out.
        if action.id == GatingBridge.trashActionID {
            guard isCarryingRotten else {
                showToast("Nothing rotten to throw out")
                return
            }
        } else if isCarryingRotten {
            showToast("Throw the rotten one away first")
            return
        }

        // A finished prep on the station blocks new work until it's collected.
        if let blocking = outputFood(at: where_) {
            showToast("Clear the \(GatingBridge.displayName(blocking)) first")
            return
        }

        let need = GatingBridge.requiredIngredients(for: action)
        let missing = need.subtracting(depositedFoods(at: where_))
        if !missing.isEmpty {
            showToast("Need: " + missing.map { GatingBridge.displayName($0) }.sorted().joined(separator: ", "))
            return
        }

        if let block = GatingBridge.blockReason(for: action, holding: inventory) {
            showToast(block)
            return
        }

        pendingAction = action

        // Offline: nobody to share the kitchen with.
        guard let session else {
            openStation(action, at: where_)
            return
        }

        // Networked: claim the station and wait for the host's grant.
        waitingStation = where_
        lastWaitToastFor = nil
        session.claimStation(where_)
    }

    /// The station this action will actually be performed at — where the chef
    /// stands when that counter offers the action (bowls share), otherwise the
    /// action's own station.
    private func workingStation(for action: CookAction) -> StationID {
        guard let here = chefStation, GameState.sharesActions(here, action.station) else {
            return action.station
        }
        return here
    }

    /// Runs every frame while queueing. Handles the three things that can
    /// happen after a claim: it's granted, it's still busy, or the action gets
    /// finished by the very person we were waiting for.
    private func resolveWaiting(_ session: KitchenSession) {
        // The host can take a lock back — a disconnect, or the game ending.
        // If it does, the screen must not stay open over a stale kitchen.
        if stationOverlay != nil, let open = chefStation, session.heldStation != open {
            // If they'd already finished the motion, credit it. The reveal beat
            // is three quarters of a second long and a revoke landing inside it
            // must not swallow work the player actually did.
            stationOverlay?.announceFinish()
            closeStation()
            return
        }
        guard stationOverlay == nil, let waiting = waitingStation else { return }

        // Whoever was in there may have completed the very action we queued
        // for, in which case there is nothing left to wait around for.
        guard stationAction(at: waiting) != nil else {
            waitingStation = nil
            lastWaitToastFor = nil
            session.releaseStation()
            showToast(state.blockReason(at: waiting))
            return
        }

        // The session can drop a claim behind our back — a host blip, or a
        // grant that arrived after we'd already walked elsewhere. If we're
        // still standing here expecting a turn, ask again; otherwise this chef
        // waits at the counter for the rest of the game.
        if session.heldStation != waiting, !session.isQueueingForStation {
            session.claimStation(waiting)
            return
        }

        if session.heldStation == waiting,
           let action = pendingAction ?? state.availableAction(at: waiting) {
            waitingStation = nil
            lastWaitToastFor = nil
            pendingAction = nil
            openStation(action, at: waiting)
        } else if let occupant = session.occupant(of: waiting),
                  occupant.id != session.localPlayerID,
                  lastWaitToastFor != waiting {
            // Toast once per wait, not once per frame.
            lastWaitToastFor = waiting
            showToast("\(occupant.name) is using the \(waiting.displayName) — waiting…")
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
            return BlowMeltOverlay(screenSize: size, actionName: action.name)
        case .breakEgg:
            return EggOverlay(screenSize: size, actionName: action.name)
        case .hold:
            return HoldOverlay(screenSize: size, actionName: action.name)
        case .throwAway:
            return GarbageThrowOverlay(screenSize: size, actionName: action.name)
        }
    }

    private func openStation(_ action: CookAction, at station: StationID) {
        activeAction = action

        let overlay = makeOverlay(for: action)


        // When the player finishes the motion, mark the action done and
        // put them back in the kitchen.
        overlay.whenFinished = { [weak self] in
            guard let self = self else { return }

            // Networked: report it and let the host confirm via the next
            // snapshot. Applying it locally too would count it twice.
            if let session = self.session {
                session.reportCompletion(actionID: action.id)
            } else {
                self.state.complete(action)
                // Offline: consume the deposits and leave the prep on the station.
                self.localDeposited[station] = nil
                if let out = action.output { self.localOutput[station] = out }
            }

            // Throwing out is the one action whose input is the hand. It
            // makes no prep and consumes no deposit — it just empties the
            // ingredient slot, which is what unlocks the rest of the kitchen.
            if action.id == GatingBridge.trashActionID {
                self.inventory?.dropIngredient()
            }

            self.closeStation(rewarding: true)
            // A producing action shows the "you got a prep" result popup; a
            // non-producing one (pre-heat, serve) just toasts.
            if let out = action.output {
                self.onActionFinished?(station, out)
            } else {
                self.showToast("\(action.name) — done")
            }
        }

        addChild(overlay)
        stationOverlay = overlay

        // Hide the kitchen HUD while heads-down. The map's hands go with it —
        // the station screen owns its own pair from here.
        setHUDHidden(true)
        hands?.vanish(animated: false)
        onHeadsDownChanged?(true)
    }

    /// `rewarding` is the difference between walking out having made something
    /// and being thrown out. Only the first gets the little bounce.
    private func closeStation(rewarding: Bool = false) {
        // Only flash when a screen was actually up. `closeStation` is also
        // called defensively — on restart, on the game ending — and a white
        // wipe over a kitchen nobody left would look like a bug.
        let wasOpen = stationOverlay != nil

        stationOverlay?.cleanUp()
        stationOverlay?.removeFromParent()
        stationOverlay = nil
        activeAction = nil

        // Hand the station back the moment the screen closes, whether the
        // action finished or the game ended underneath it.
        session?.releaseStation()
        waitingStation = nil
        lastWaitToastFor = nil

        setHUDHidden(false)
        onHeadsDownChanged?(false)
        refreshStations()

        if wasOpen {
            // Flash first, hands a beat later — they arrive as the white clears
            // rather than being washed out by it.
            flashToKitchen()
            refreshHands()
            hands?.run(.wait(forDuration: 0.12)) { [weak self] in
                self?.hands?.appear(bounce: rewarding)
            }
        } else {
            refreshHands()
            hands?.appear()
        }
    }

    private func setHUDHidden(_ hidden: Bool) {
        hudTime.isHidden = hidden
        hudMess.isHidden = hidden
        toast.isHidden = hidden
        for label in checklistLabels.values { label.isHidden = hidden }
        // Only ever hides. Whether the ritual is visible at all is decided by
        // `refreshServe` from the recipe state, and letting this un-hide it
        // would flash the serve zone for a frame before the cake exists.
        if hidden { serveNode?.isHidden = true }
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
            resolveWaiting(session)
            session.reportPosition(x: Double(chef.position.x / size.width),
                                   y: Double(chef.position.y / size.height),
                                   station: chefStation?.rawValue,
                                   isBusy: activeAction != nil)
            // Someone else finishing an action can unlock a station in front of
            // us, so availability has to be re-checked continuously.
            refreshStations()
        } else {
            state.tick(gap)
        }

        // Drive whichever station screen is open. Without this the minigames
        // never advance.
        stationOverlay?.update(secondsSinceLastFrame: gap)

        // Picking a knife off the shelf has to show up in the hand without the
        // storage screen having to reach in here. `setItems` diffs internally,
        // so an unchanged hand costs two optional comparisons a frame.
        if stationOverlay == nil {
            refreshHands()
            refreshServe()
        }

        refreshHUD()

        if state.isOver { presentEnd() }
    }

    private func refreshHUD() {
        // Nothing to draw while the player is heads-down.
        if stationOverlay != nil { return }

        let seconds = Int(state.timeRemaining)
        hudTime.text = String(format: "%d:%02d", seconds / 60, seconds % 60)
        // Turns red for the last 10% of the round rather than a fixed 45s. On a
        // 15 minute clock a flat 45 meant the warning arrived with 5% left; on
        // a 2 minute one it was on for a third of the game.
        hudTime.fontColor = state.timeRemaining < Recipe.timeLimit * 0.1 ? SKColor.red : ink
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
    /// Filled in a player's colour = that player is in there and it's closed.
    ///
    /// This runs every frame in a networked game, so each station's appearance
    /// is reduced to a short key and nothing is touched unless the key changed.
    /// Re-assigning `SKLabelNode.text` rebuilds its texture, which at 60fps
    /// across eight stations is a real cost for no visible difference.
    private func refreshStations() {
        for (id, node) in stationNodes {
            let owner = session?.occupant(of: id)
            // The bin is always "available" in recipe terms (repeatable, no
            // requirements), which would leave it lit all game. Light it for
            // the one chef who has something to throw out instead.
            let ready = id == .trash
                ? isCarryingRotten
                : (id == .storage || id == .drawer || state.availableAction(at: id) != nil)
            let key = owner.map { "busy:\($0.id):\($0.colorIndex)" } ?? "free:\(ready)"
            if stationLooks[id] == key { continue }
            stationLooks[id] = key

            let label = stationOwnerLabels[id]

            // Occupancy wins over availability: a station can be perfectly
            // ready and still be someone else's until they walk out.
            if let owner {
                node.strokeColor = Self.colour(owner.colorIndex)
                node.lineWidth = 3
                node.fillColor = Self.fill(owner.colorIndex)
                label?.isHidden = false
                label?.fontColor = Self.colour(owner.colorIndex)
                label?.text = owner.id == session?.localPlayerID
                    ? "you're here"
                    : "\(owner.name) is here"
            } else {
                // Free. "Ready" is a filled green tint rather than a slightly
                // greener outline — at arm's length on a phone, line weight is
                // not a signal anyone reads.
                node.fillColor = ready
                    ? readyColour.withAlphaComponent(0.18)
                    : counterColour
                node.strokeColor = ready ? readyColour : counterEdge
                node.lineWidth = ready ? 4 : 2.5
                label?.isHidden = true
            }
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

        // Close any station screen that was still open — but bank a finished
        // action first. The clock running out during the reveal beat used to
        // discard the action, which could turn a win into a loss.
        stationOverlay?.announceFinish()
        closeStation()
        endServeHold()

        // Nobody is holding anything once the service is over, and no white
        // wipe over the results card.
        hands?.vanish()
        cancelFlash()

        let node = SKNode()
        // Above the flash sheet at 300, or a close-and-end in the same frame
        // washes the results card white.
        node.zPosition = 400

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
        waitingStation = nil
        lastWaitToastFor = nil
        isWalking = false
        chef.removeAllActions()
        chef.position = spawnPoint(forColorIndex: session?.localPlayer?.colorIndex ?? 0)

        isInServeZone = false
        endServeHold()
        inventory?.clear()
        localDeposited.removeAll()
        cancelFlash()
        refreshHands()
        hands?.appear()

        state.reset()
        stationLooks.removeAll()   // force a full redraw past the change check
        refreshStations()
    }
}
