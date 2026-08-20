//
//  ServeRitual.swift
//  Cooked
//
//  Serving the cake, which is the one thing in this kitchen nobody can do on
//  their own.
//
//  Every other action is a chef alone at a counter. This one asks the whole
//  team to stop, walk to the same spot, and press together — so the last beat
//  of the game is the only one that can't be soloed.
//
//  Two parts, deliberately kept apart:
//
//    • `ServeRitual` — the numbers. Where the zone is, how big, how tight the
//      window is. These are the knobs to play with on device.
//    • `ServeRitualNode` — what it looks like. Draws itself from state it is
//      handed and answers "did they hit the button", nothing more. The rules
//      live on the host (see KitchenSession), never here: a screen that could
//      decide a serve had happened is a screen that can serve alone.
//

import SpriteKit

// MARK: - Tuning

nonisolated enum ServeRitual {

    /// The open floor in the middle of the kitchen, with the counters around
    /// its edges.
    ///
    /// This one spot does double duty: it is where every chef starts the match
    /// and where the whole team has to come back to serve. Start together,
    /// finish together.
    static let zoneUnitPosition = CGPoint(x: 0.50, y: 0.52)

    /// Big enough to hold four chefs on their own marks without them touching.
    ///
    /// Use `zoneRadius(for:)` rather than this raw number: the marks are placed
    /// in screen-relative units and this is in points, so on a very different
    /// aspect ratio the marks can fall outside a fixed circle — which would put
    /// a chef on their own mark and *outside* the serve zone, making the serve
    /// impossible.
    static let zoneRadius: CGFloat = 58

    static func zoneRadius(for sceneSize: CGSize) -> CGFloat {
        let furthest = spawnOffsets
            .map { hypot($0.x * sceneSize.width, $0.y * sceneSize.height) }
            .max() ?? 0
        return max(zoneRadius, furthest + 22)
    }

    /// The four marks on the floor, one per chef.
    ///
    /// Spread far enough apart that you can count the team at a glance and
    /// tell who is missing — the whole point of opening and closing the match
    /// in the same place. Keyed by `Player.colorIndex`, which the host hands
    /// out on join, so a chef stands on the same mark on every device.
    static func spawnUnitPosition(forColorIndex index: Int) -> CGPoint {
        let offset = spawnOffsets[((index % spawnOffsets.count) + spawnOffsets.count)
                                  % spawnOffsets.count]
        return CGPoint(x: zoneUnitPosition.x + offset.x,
                       y: zoneUnitPosition.y + offset.y)
    }

    static let spawnOffsets = [
        CGPoint(x: -0.034, y:  0.062),
        CGPoint(x:  0.034, y:  0.062),
        CGPoint(x: -0.034, y: -0.062),
        CGPoint(x:  0.034, y: -0.062)
    ]

    /// Testing knob: draw the serve zone from the first frame instead of
    /// waiting for the cake to be decorated.
    ///
    /// The circle correctly stays invisible for most of a match, which makes it
    /// impossible to check the layout without playing the whole recipe. Set
    /// false before shipping.
    static let previewZoneBeforeUnlocked = true

    /// How long a lone hold survives while it waits for the rest of the team.
    ///
    /// Press and nobody joins you inside this, and your hold is dropped — the
    /// button pops back out. Short enough that you can't just lean on it and
    /// wait, long enough that "three, two, one, now" works.
    static let gatherWindow: TimeInterval = 2

    /// How long to wait for the host to confirm a hold before believing it was
    /// refused.
    ///
    /// The host rebuilds its snapshot ten times a second, so an acknowledgement
    /// is never less than 100ms away, plus the round trip. Anything shorter
    /// than that and a device concludes its own press was rejected one frame
    /// after making it — which is exactly the bug that made the button do
    /// nothing at all. Comfortably under `gatherWindow`, so a genuinely refused
    /// hold still pops out well before the window closes.
    static let holdAckGrace: TimeInterval = 0.75

    /// How long everyone has to keep holding, together, to fill the bar.
    ///
    /// The spike-defuse beat: the moment anyone lets go or steps off their
    /// mark, it empties. Three seconds of the whole team committed at once.
    static let chargeDuration: TimeInterval = 3

    /// The action id being performed. `Recipe.actions` id 12, "Serve the Cake".
    static let actionID = 12

    /// Cached: this was a linear scan over `Recipe.actions` running once per
    /// frame in the scene and once per tick on the host.
    static let action: CookAction? = Recipe.action(actionID)
}

// MARK: - What it looks like

/// The zone, the button and the line of text that says who you're waiting on.
///
/// Hidden entirely until the cake is decorated. Before that the middle of the
/// room is just floor.
@MainActor
final class ServeRitualNode: SKNode {

    private var zone = SKShapeNode(circleOfRadius: ServeRitual.zoneRadius)
    private let zoneLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")

    private let button = SKShapeNode(rectOf: CGSize(width: 190, height: 56),
                                     cornerRadius: 28)
    private let buttonLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let statusLabel = SKLabelNode(fontNamed: "AvenirNext-Regular")

    /// The defuse bar. Only moves while every chef is holding at once.
    private let barTrack = SKShapeNode(rectOf: CGSize(width: 190, height: 12),
                                       cornerRadius: 6)
    private let barFill = SKSpriteNode()
    private static let barWidth: CGFloat = 190

    /// Where the chef walks to. Scene coordinates, set at build time.
    private(set) var zonePoint: CGPoint = .zero

    /// Last drawn appearance, so a per-frame refresh can skip the work. Setting
    /// `SKLabelNode.text` rebuilds its texture, and this updates at 60fps.
    /// Compared as a struct rather than an interpolated string — building the
    /// key was costing more than the check saved.
    private var lastLook: State?

    private let ink = SKColor(white: 0.12, alpha: 1)
    private let live = SKColor(red: 0.15, green: 0.55, blue: 0.30, alpha: 1)
    private let waiting = SKColor(red: 0.80, green: 0.55, blue: 0.15, alpha: 1)

    // MARK: Setup

    init(sceneSize: CGSize) {
        super.init()

        zPosition = 2
        zonePoint = CGPoint(x: ServeRitual.zoneUnitPosition.x * sceneSize.width,
                            y: ServeRitual.zoneUnitPosition.y * sceneSize.height)

        zone = SKShapeNode(circleOfRadius: ServeRitual.zoneRadius(for: sceneSize))
        zone.position = zonePoint
        zone.lineWidth = 3
        zone.strokeColor = waiting
        zone.fillColor = waiting.withAlphaComponent(0.10)
        addChild(zone)

        // One mark per chef. Standing on your own spot is what makes a missing
        // team-mate obvious at a glance instead of a headcount.
        for offset in ServeRitual.spawnOffsets {
            let mark = SKShapeNode(circleOfRadius: 15)
            mark.position = CGPoint(x: offset.x * sceneSize.width + zonePoint.x,
                                    y: offset.y * sceneSize.height + zonePoint.y)
            mark.strokeColor = ink.withAlphaComponent(0.22)
            mark.fillColor = .clear
            mark.lineWidth = 1.5
            mark.name = "mark"
            addChild(mark)
        }

        zoneLabel.text = "SERVE HERE"
        zoneLabel.fontSize = 11
        zoneLabel.fontColor = ink
        zoneLabel.verticalAlignmentMode = .center
        // Inside the circle: below it the label landed inside the Table
        // station's box and painted over it.
        zoneLabel.position = CGPoint(x: zonePoint.x,
                                     y: zonePoint.y + ServeRitual.zoneRadius(for: sceneSize) - 12)
        addChild(zoneLabel)

        // Bottom-centre. It was bottom-right, but the bar and the status line
        // stack *above* the button and that put them straight on top of the
        // Oven. The centre is free now that the SwiftUI inventory bar is gone,
        // and the hands own the bottom-left.
        let buttonPoint = CGPoint(x: sceneSize.width * 0.5, y: 76)
        button.position = buttonPoint
        button.lineWidth = 3
        button.strokeColor = ink
        button.zPosition = 30
        addChild(button)

        buttonLabel.text = "SERVE"
        buttonLabel.fontSize = 22
        buttonLabel.verticalAlignmentMode = .center
        buttonLabel.position = buttonPoint
        buttonLabel.zPosition = 31
        addChild(buttonLabel)

        barTrack.position = CGPoint(x: buttonPoint.x, y: buttonPoint.y + 44)
        barTrack.fillColor = SKColor(white: 0.85, alpha: 1)
        barTrack.strokeColor = ink.withAlphaComponent(0.5)
        barTrack.lineWidth = 2
        barTrack.zPosition = 30
        addChild(barTrack)

        // Anchored left so it grows rightwards from empty.
        barFill.color = live
        barFill.colorBlendFactor = 1
        barFill.size = CGSize(width: Self.barWidth - 6, height: 8)
        barFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        barFill.position = CGPoint(x: barTrack.position.x - (Self.barWidth - 6) / 2,
                                   y: barTrack.position.y)
        barFill.xScale = 0.0001
        barFill.zPosition = 31
        addChild(barFill)

        statusLabel.fontSize = 13
        statusLabel.fontColor = ink
        statusLabel.verticalAlignmentMode = .center
        statusLabel.position = CGPoint(x: buttonPoint.x, y: buttonPoint.y + 70)
        statusLabel.zPosition = 30
        addChild(statusLabel)

        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// The scene is built at the safe-area size and resized to the view's real
    /// bounds, so anything centred or pinned to an edge has to be told.
    func layout(for sceneSize: CGSize) {
        zonePoint = CGPoint(x: ServeRitual.zoneUnitPosition.x * sceneSize.width,
                            y: ServeRitual.zoneUnitPosition.y * sceneSize.height)
        zone.position = zonePoint
        zoneLabel.position = CGPoint(x: zonePoint.x,
                                     y: zonePoint.y + ServeRitual.zoneRadius(for: sceneSize) - 12)

        for (mark, offset) in zip(children.filter { $0.name == "mark" },
                                  ServeRitual.spawnOffsets) {
            mark.position = CGPoint(x: offset.x * sceneSize.width + zonePoint.x,
                                    y: offset.y * sceneSize.height + zonePoint.y)
        }

        let buttonPoint = CGPoint(x: sceneSize.width * 0.5, y: 76)
        button.position = buttonPoint
        buttonLabel.position = buttonPoint
        barTrack.position = CGPoint(x: buttonPoint.x, y: buttonPoint.y + 44)
        barFill.position = CGPoint(x: barTrack.position.x - (Self.barWidth - 6) / 2,
                                   y: barTrack.position.y)
        statusLabel.position = CGPoint(x: buttonPoint.x, y: buttonPoint.y + 70)
    }

    // MARK: Drawing

    /// Everything the ritual needs to draw itself.
    struct State: Equatable {
        /// The cake is decorated — before this the whole thing is invisible.
        var unlocked = false
        /// Chefs standing in the circle, out of how many are still connected.
        var gathered = 0
        var total = 1
        /// Every connected chef is in the zone: the button is live.
        var armed = false
        /// This device is holding the button down right now.
        var holding = false
        /// How many chefs are holding at this instant.
        var holdingCount = 0
        /// How full the bar is, 0...1.
        var progress: Double = 0
    }

    func apply(_ state: State) {
        // The circle can be shown before there's a cake — it's the spot the
        // team spawned on, so it reads as "meet here" rather than appearing
        // out of nowhere at the end of the match.
        let visible = state.unlocked || ServeRitual.previewZoneBeforeUnlocked
        isHidden = !visible
        guard visible else { return }

        // The bar moves continuously, so it is drawn first and outside the
        // change-check below. Putting it inside would mean the check passes ten
        // times a second during a charge and rebuilds every label texture with
        // identical text — exactly the cost the check exists to avoid.
        barFill.xScale = CGFloat(max(0.0001, min(1, state.progress)))

        var key = state
        key.progress = 0
        if key == lastLook { return }
        lastLook = key

        // Only the circle exists until there is something to serve. A live
        // button with no cake behind it would be a promise the kitchen can't
        // keep.
        button.isHidden = !state.unlocked
        buttonLabel.isHidden = !state.unlocked
        statusLabel.isHidden = !state.unlocked
        barTrack.isHidden = !state.unlocked
        barFill.isHidden = !state.unlocked
        zoneLabel.text = state.unlocked ? "SERVE HERE" : "MEET HERE"

        guard state.unlocked else {
            zone.strokeColor = SKColor(white: 0.45, alpha: 0.9)
            zone.fillColor = SKColor(white: 0.45, alpha: 0.08)
            return
        }

        if state.armed {
            zone.strokeColor = live
            zone.fillColor = live.withAlphaComponent(0.16)
        } else {
            zone.strokeColor = waiting
            zone.fillColor = waiting.withAlphaComponent(0.10)
        }

        // The button is always visible once the cake is ready — greyed until
        // everyone has gathered. Hiding it would leave the team guessing what
        // they are supposed to do with a finished cake.
        button.fillColor = state.armed ? live : SKColor(white: 0.78, alpha: 1)
        button.alpha = state.armed ? 1 : 0.65
        buttonLabel.fontColor = state.armed ? .white : SKColor(white: 0.35, alpha: 1)
        buttonLabel.alpha = button.alpha

        barFill.color = state.holdingCount == state.total ? live : waiting

        let everyone = state.holdingCount == state.total && state.total > 0

        if everyone && state.holding {
            buttonLabel.text = "HOLD"
            statusLabel.text = "Keep holding — don't let go!"
        } else if state.holding {
            // You're committed and waiting on the rest. Say who's missing
            // rather than repeating the instruction you've clearly followed.
            buttonLabel.text = "HOLDING"
            statusLabel.text = "\(state.holdingCount)/\(state.total) holding — hurry!"
        } else if state.armed {
            buttonLabel.text = "HOLD"
            statusLabel.text = "Everyone hold together!"
        } else {
            buttonLabel.text = "HOLD"
            statusLabel.text = "\(state.gathered)/\(state.total) chefs on their marks"
        }

        // Pressed-in look while this device is holding.
        button.yScale = state.holding ? 0.94 : 1
    }

    /// Did this touch land on the button? The scene asks; the node does not
    /// handle touches itself, because the scene already owns walk-vs-tap.
    func buttonContains(_ point: CGPoint) -> Bool {
        // `button.isHidden` matters as much as the node's: before the cake is
        // decorated the circle is on show but the button is not, and a hidden
        // SKNode still answers `contains`. Without this there is a dead 190x56
        // hole in the map for the whole match.
        guard !isHidden, !button.isHidden else { return false }
        return button.contains(point)
    }

    /// A missed serve. Nothing failed — the team just wasn't together — so this
    /// is a nudge, not an error.
    func nudge() {
        button.removeAllActions()
        button.run(.sequence([
            .scale(to: 1.08, duration: 0.08),
            .scale(to: 1.0, duration: 0.12)
        ]))
    }
}
