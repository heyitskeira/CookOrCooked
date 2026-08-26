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
    ///
    /// Measured off the reference art rather than eyeballed at dead centre: the
    /// clearing's middle stone is where the mockup letters GATHER HERE TO
    /// SERVE, and it sits a little below the geometric centre of the screen.
    /// Only the position moved — the ritual itself is untouched.
    static let zoneUnitPosition = CGPoint(x: 0.5031, y: 0.4447)

    /// The zone is an **ellipse**, not a circle, because the stone it sits on is
    /// one: measured off `bg-kitchen-clearing` the middle stone is 263x97 on the
    /// 1748x804 artboard — a flat oval in perspective, not a disc seen head-on.
    ///
    /// A circle that fit inside it would have to shrink to the stone's *short*
    /// axis and end up too small to stand four chefs on; a circle that held the
    /// chefs spilled well past the stone onto the grass. Matching the shape
    /// solves both, and is the only way the ring reads as painted onto the
    /// clearing rather than laid over it.
    ///
    /// Fractions of `KitchenArt.mapRect`, so the ring tracks the stone at any
    /// screen size. Inset slightly so the stroke sits just inside the stone's
    /// edge instead of straddling it.
    static let zoneUnitRadii = CGSize(width: 0.0752 * 0.94, height: 0.0603 * 0.94)

    /// The zone's radii in points, for drawing and for the containment tests.
    static func zoneRadii(for sceneSize: CGSize) -> CGSize {
        let map = KitchenArt.mapRect(in: sceneSize)
        return CGSize(width: zoneUnitRadii.width * map.width,
                      height: zoneUnitRadii.height * map.height)
    }

    /// Is `point` inside the zone centred on `centre`?
    ///
    /// The ellipse equivalent of the distance check this replaced: normalise
    /// each axis by its own radius and ask whether the result lands inside the
    /// unit circle. `slack` widens both axes by a few points, which is what
    /// gives a tap a little forgiveness without moving the ring you can see.
    static func zoneContains(_ point: CGPoint,
                             centre: CGPoint,
                             in sceneSize: CGSize,
                             slack: CGFloat = 0) -> Bool {
        let r = zoneRadii(for: sceneSize)
        let rx = r.width + slack
        let ry = r.height + slack
        guard rx > 0, ry > 0 else { return false }
        let nx = (point.x - centre.x) / rx
        let ny = (point.y - centre.y) / ry
        return nx * nx + ny * ny <= 1
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

    /// Four marks in a shallow row rather than a 2x2 block.
    ///
    /// The stone is roughly three times wider than it is deep, so a square of
    /// marks does not fit on it — the old ±0.062 vertical offset alone was
    /// taller than the stone's whole half-height. Spread along the wide axis
    /// with a slight stagger, they sit on the stone and still read as four
    /// separate places to stand.
    static let spawnOffsets = [
        CGPoint(x: -0.042, y:  0.006),
        CGPoint(x: -0.014, y: -0.006),
        CGPoint(x:  0.014, y:  0.006),
        CGPoint(x:  0.042, y: -0.006)
    ]

    /// Radius of a floor mark, sized from the zone rather than fixed.
    ///
    /// A fixed 11pt looked right on a big phone and spilled off the stone on an
    /// SE, where the ellipse is only about 35pt tall — the mark plus its offset
    /// came to more than the whole short radius. Tied to the zone, all four fit
    /// on every screen. The floor keeps it visible when the stone is small.
    static func markRadius(for sceneSize: CGSize) -> CGFloat {
        max(5, zoneRadii(for: sceneSize).height * 0.32)
    }

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

    /// Replaced in `init` with the real ellipse; this is just a placeholder so
    /// the property is initialised before `super.init()`.
    private var zone = SKShapeNode()
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
        // Against the artboard, not the scene: the serve stone is painted into
        // the background, so the circle has to follow the picture.
        zonePoint = KitchenArt.mapPoint(ServeRitual.zoneUnitPosition, in: sceneSize)

        zone = SKShapeNode(path: Self.zonePath(for: sceneSize))
        zone.position = zonePoint
        zone.lineWidth = 3
        zone.strokeColor = waiting
        zone.fillColor = waiting.withAlphaComponent(0.10)
        addChild(zone)

        // One mark per chef. Standing on your own spot is what makes a missing
        // team-mate obvious at a glance instead of a headcount.
        for offset in ServeRitual.spawnOffsets {
            let mark = SKShapeNode(circleOfRadius: ServeRitual.markRadius(for: sceneSize))
            let map = KitchenArt.mapRect(in: sceneSize)
            mark.position = CGPoint(x: offset.x * map.width + zonePoint.x,
                                    y: offset.y * map.height + zonePoint.y)
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
                                     y: zonePoint.y + ServeRitual.zoneRadii(for: sceneSize).height + 11)
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

    /// The zone's outline. Rebuilt rather than resized, because an SKShapeNode
    /// keeps whatever path it was born with — and the scene is built at the
    /// safe-area size then resized to the view's real bounds, so "born with" is
    /// the wrong size on the very first frame.
    private static func zonePath(for sceneSize: CGSize) -> CGPath {
        let r = ServeRitual.zoneRadii(for: sceneSize)
        return CGPath(ellipseIn: CGRect(x: -r.width, y: -r.height,
                                        width: r.width * 2, height: r.height * 2),
                      transform: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// The scene is built at the safe-area size and resized to the view's real
    /// bounds, so anything centred or pinned to an edge has to be told.
    func layout(for sceneSize: CGSize) {
        // Against the artboard, not the scene: the serve stone is painted into
        // the background, so the circle has to follow the picture.
        zonePoint = KitchenArt.mapPoint(ServeRitual.zoneUnitPosition, in: sceneSize)
        zone.position = zonePoint
        zone.path = Self.zonePath(for: sceneSize)
        zoneLabel.position = CGPoint(x: zonePoint.x,
                                     y: zonePoint.y + ServeRitual.zoneRadii(for: sceneSize).height + 11)

        let markR = ServeRitual.markRadius(for: sceneSize)
        for (mark, offset) in zip(children.filter { $0.name == "mark" },
                                  ServeRitual.spawnOffsets) {
            let map = KitchenArt.mapRect(in: sceneSize)
            mark.position = CGPoint(x: offset.x * map.width + zonePoint.x,
                                    y: offset.y * map.height + zonePoint.y)
            // Same reason the zone's own path is rebuilt: a shape node keeps
            // the radius it was created with.
            (mark as? SKShapeNode)?.path = CGPath(
                ellipseIn: CGRect(x: -markR, y: -markR, width: markR * 2, height: markR * 2),
                transform: nil)
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
