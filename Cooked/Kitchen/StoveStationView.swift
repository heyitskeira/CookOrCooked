//
//  StoveStationView.swift
//  Cooked
//
//  The stove, rebuilt against final art — the third illustrated station page,
//  after chopping and the bowls. Shared pieces come from `StationCanvas`
//  (the artboard), `StationChrome` (bar, corner buttons, ground, paws) and
//  `StationMinigame` (how the melting is actually performed).
//
//  What makes this station its own screen rather than another bowl:
//
//  • **The chef brings the pan.** The stove starts bare — two rings and a
//    thermometer, nothing on them. Setting the butter down puts the pan down
//    with it, because you cannot melt butter on a bare ring. That is one
//    action on one button, not two.
//  • **The wrong tool blocks the drop.** Every other station lets you put an
//    ingredient down and fetch the tool afterwards. Here the tool is what the
//    ingredient sits in, so arriving with a whisk means the butter stays in
//    hand.
//  • **Melting starts on its own.** There is no "start" button in the art
//    direction, and the reason is that setting a pan of butter on a hot ring
//    *is* starting: the fire is already climbing. The instruction flashes for
//    a beat and the chef is straight into it.
//
//  The heat is `StationMinigame`'s blow mechanic, tuning intact from
//  `BlowMeltOverlay`: the fire climbs by itself, blowing into the microphone
//  pushes it down, and the butter only melts while the needle sits in the
//  green-to-yellow band.
//

import SwiftUI

struct StoveStationView: View {

    let station: StationID
    @ObservedObject var session: KitchenSession
    @ObservedObject var inventory: PlayerInventory
    var onClose: () -> Void

    @State private var alert: String?
    @State private var game: StationMinigame?
    @State private var showTutorial = false
    @State private var tutorialFlash = 0
    /// The pan is on the rings because somebody set it there this visit.
    /// Anything already in the pan means one is there too — see `panIsOn`.
    @State private var panSetDown = false

    // MARK: Layout — design-space frames (see `StationCanvas`)

    private static let stoveFrame = CGRect(x: 272, y: 113, width: 331, height: 205)
    private static let meterFrame = CGRect(x: 182, y: 127, width: 107, height: 160)

    /// The pan sits across the rings at an angle. Its x/y is the corner of the
    /// *rotated* box, not of the pan itself — see `figmaPlaced(rotation:)`.
    ///
    /// The brief's (397, -30) put the bowl down and to the right of the ring,
    /// hanging off the edge of the board. The size and angle are the brief's;
    /// the position is derived instead, from where the two pictures actually
    /// have their metal: the ring's centre in `stove top.png` and the bowl's
    /// centre in `pan.png`, measured off the artwork and solved through the
    /// rotation so the bowl lands on the ring. See `panOrigin`.
    private static let panSize = CGSize(width: 178.68, height: 338.46)
    /// The brief says -49.35°, which is Figma's number — and Figma measures
    /// rotation anticlockwise while SwiftUI measures it clockwise. Handed
    /// straight over, the pan lies with its handle up and to the *left*, the
    /// mirror image of the art direction. Negating it is the conversion, not
    /// a correction to the brief.
    private static let panAngle = Angle(degrees: 49.35)

    /// Where the metal actually is in each picture, as fractions of it —
    /// measured off the art, not guessed. The stove's two rings sit at 0.276
    /// and 0.749 across; the pan's bowl at 0.491, 0.723 down its own image.
    private static let rightRingInStove = CGPoint(x: 0.749, y: 0.454)
    private static let bowlInPan = CGPoint(x: 0.491, y: 0.723)

    private static let butterOnPan = CGRect(x: 471, y: 162, width: 103, height: 89)
    private static let meltedOnPan = CGRect(x: 468, y: 151, width: 116, height: 99)
    private static var stoveCentre: CGPoint { CGPoint(x: stoveFrame.midX, y: stoveFrame.midY) }

    /// Where each of this station's items hangs in a paw. Measured per item,
    /// because a pan, a block of butter and a bowl of melted butter are three
    /// very different shapes.
    private static let handFrames: [String: CGRect] = [
        "butter":       CGRect(x: 687, y: 271, width: 85, height: 96),
        "pan":          CGRect(x: 778, y: 266, width: 56, height: 106),
        "meltedButter": CGRect(x: 715, y: 286, width: 116.78, height: 97.56)
    ]

    private static let controlFrame = CGRect(x: 300, y: 340, width: 280, height: 44)

    /// Where the thermometer's own colours are, measured off the artwork as
    /// fractions of its frame: red from 0.138, the orange-into-yellow stretch
    /// to 0.481, green to 0.606, and the blue bulb below that. The needle is
    /// pinned to these rather than spread evenly over the tube, because the
    /// scale isn't evenly divided and the colours are what the chef reads.
    private static let redTop = 0.138
    private static let yellowTop = 0.38
    private static let greenBottom = 0.606
    private static let coldMiddle = 0.72

    /// The needle, in fractions of the meter's own width — so it stays the
    /// same size relative to the thermometer on any screen. The art direction
    /// draws a chunky pointer about a third as wide as the tube, with its tip
    /// reaching into the colour rather than hovering outside the frame. The
    /// first version was a small triangle placed in artboard coordinates,
    /// which left it stranded out on the forest floor.
    private static let needleWidth = 0.34
    private static let needleHeight = 0.26
    /// Where the tip lands, as a fraction of the meter's width. Set by eye
    /// against the art direction rather than from the column's own 0.327:
    /// the thermometer picture carries a wide wooden surround, and a tip
    ///calculated to the colour's edge stops short at the wood.
    private static let needleTip = 0.46

    /// Where `StationMinigame` starts the fire, so the idle needle matches
    /// where it will be the moment melting begins.
    private static let restingFire = 0.4

    // MARK: Snapshot-derived state

    private var completed: Set<Int> { Set(session.snapshot.completed) }
    // The session's own host-aware accessors rather than `session.snapshot`:
    // the snapshot only refreshes on the tick `startCooking()` starts, which
    // needs two connected players, so a solo or preview session would never
    // see its own deposit. See `KitchenScene.depositedFoods`.
    private var deposited: [String] { session.depositedFoods(at: station) }
    private var output: String? { session.outputFood(at: station) }

    /// The stove's one action. Read from the recipe rather than hardcoded, so
    /// a second stove action would be picked up here.
    private var action: CookAction? {
        Recipe.actions.first {
            $0.id != GatingBridge.trashActionID
            && GameState.sharesActions(station, $0.station)
            && (!completed.contains($0.id) || $0.isRepeatable)
        }
    }

    /// Something is in the pan, so a pan is on the stove whether or not this
    /// chef is the one who put it there.
    private var panIsOn: Bool { panSetDown || !deposited.isEmpty || output != nil }

    /// What's sitting in the pan: the finished butter, or the block waiting to
    /// melt.
    private var panContents: String? { output ?? deposited.first }

    private var handBlockMessage: String? {
        if inventory.isHoldingRotten { return Rotten.blockedMessage }
        if inventory.isHoldingPrep   { return "You already held on to a prep!" }
        return nil
    }

    /// What the chef could set down: an ingredient this station wants, that
    /// isn't already here, with nothing finished in the way.
    private var droppable: HeldIngredient? {
        guard output == nil, let action, let ing = inventory.ingredient,
              !ing.isRotten, !deposited.contains(ing.id),
              GatingBridge.requiredIngredients(for: action).contains(ing.id) else { return nil }
        return ing
    }

    /// Why the drop is refused, or nil if it's allowed. The pan is the whole
    /// reason: it's what the butter has to sit in.
    private var dropBlockedReason: String? {
        guard let action else { return nil }
        return GatingBridge.blockReason(for: action, holding: inventory)
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StationGround(geo: geo)
                stoveLayer(geo)
                thermometer(geo)

                StationHands(inventory: inventory, geo: geo, frames: Self.handFrames)

                StationHeaderBar(title: action?.name ?? station.displayName,
                                 progress: headerProgress, geo: geo)

                // Only reachable while melting, and only for the chef with no
                // microphone — see `StationMinigame.blow`. Below the corner
                // buttons in z-order so backing out stays possible.
                if let game { MinigameSurface(game: game) }

                StationBackButton(geo: geo, action: leave)
                StationHelpButton(geo: geo, action: flashTutorial)

                if game == nil { controls(geo) }
                if let game, game.isTooHot { tooHotWarning(geo) }

                if let alert {
                    PrepHeldAlert(message: alert) { self.alert = nil }
                }

                if showTutorial, let motion = action?.motion {
                    StationInstructionOverlay(motion: motion, caption: action?.name) {
                        withAnimation(.easeOut(duration: 0.2)) { showTutorial = false }
                    }
                }
            }
        }
        .ignoresSafeArea()
        // Leaving by any route has to switch the microphone off, or it keeps
        // listening (and the music keeps ducking) from across the kitchen.
        .onDisappear { game?.stop() }
    }

    private var headerProgress: CGFloat {
        if let game { return game.progress }
        return output == nil ? 0 : 1
    }

    // MARK: The stove

    /// The stove, with the pan and the butter drawn as part of it.
    ///
    /// They have to share one space. `.scaledToFit()` letterboxes art inside
    /// its frame whenever the screen's aspect differs from the artboard's —
    /// and it always does, because the page is stretched to fill the device.
    /// A tall pan letterboxes by a different amount than a wide stove, so a
    /// pan positioned in artboard coordinates slides off its ring by tens of
    /// points on any screen but the one the art was drawn at. Hanging both off
    /// the stove at one uniform scale keeps the pan on the ring and the butter
    /// in the pan, whatever the phone.
    private func stoveLayer(_ geo: GeometryProxy) -> some View {
        let box = StationCanvas.rect(Self.stoveFrame, in: geo)
        // The scale `.scaledToFit()` is about to pick for the stove art.
        let scale = min(box.width / Self.stoveFrame.width, box.height / Self.stoveFrame.height)

        return ZStack {
            if let art = FoodArt.art("stove-top") {
                Image(uiImage: art).resizable().scaledToFit()
                    .frame(width: Self.stoveFrame.width * scale,
                           height: Self.stoveFrame.height * scale)
            }

            if panIsOn { panLayer(scale) }
            panContentsLayer(scale)
        }
        .frame(width: box.width, height: box.height)
        .position(x: box.midX, y: box.midY)
    }

    /// The pan, resting on the right-hand ring.
    ///
    /// Its size and angle are the brief's. Its position is worked out from
    /// where the two pictures actually keep their metal — the ring's centre in
    /// `stove top.png`, the bowl's centre in `pan.png` — turned through the
    /// rotation so the bowl comes down on the ring. The brief's own (397, -30)
    /// put the bowl to the right of the ring, half off the board.
    private func panLayer(_ scale: CGFloat) -> some View {
        // Both offsets are measured from the middle of the stove, which is
        // where this ZStack's own centre is.
        let ring = CGPoint(x: (Self.rightRingInStove.x - 0.5) * Self.stoveFrame.width,
                           y: (Self.rightRingInStove.y - 0.5) * Self.stoveFrame.height)
        let bowl = CGPoint(x: (Self.bowlInPan.x - 0.5) * Self.panSize.width,
                           y: (Self.bowlInPan.y - 0.5) * Self.panSize.height)

        // Where the rotation carries the bowl. Screen coordinates run y-down,
        // so this is the clockwise turn the view is given.
        let turn = Self.panAngle.radians
        let spun = CGPoint(x: bowl.x * cos(turn) - bowl.y * sin(turn),
                           y: bowl.x * sin(turn) + bowl.y * cos(turn))

        return Group {
            if let art = FoodArt.art("pan") {
                Image(uiImage: art).resizable().scaledToFit()
            }
        }
        .frame(width: Self.panSize.width * scale, height: Self.panSize.height * scale)
        .rotationEffect(Self.panAngle)
        .offset(x: (ring.x - spun.x) * scale, y: (ring.y - spun.y) * scale)
        .transition(.opacity)
    }

    /// The butter in the pan, unwrapped on the way in and a puddle on the way
    /// out. Both come from `looseArt`: the carried pictures are a wrapped
    /// block and a bowl, neither of which belongs in a frying pan.
    private func panContentsLayer(_ scale: CGFloat) -> some View {
        Group {
            if let food = output, let art = FoodArt.looseArt(food) {
                inPan(art, Self.meltedOnPan, scale)
            } else if let food = panContents, let art = FoodArt.looseArt(food) {
                inPan(art, Self.butterOnPan, scale)
                    // Butter softening on a hot ring: it sags a little while
                    // the fire sits in the melting band, and sits still when
                    // it doesn't. The only cue the heat is right, besides the
                    // needle.
                    .scaleEffect(x: melting ? 1.06 : 1.0, y: melting ? 0.9 : 1.0, anchor: .bottom)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                               value: melting)
            }
        }
    }

    /// Something sitting in the pan, placed by its artboard rect but drawn at
    /// the stove's scale — see `stoveLayer` for why that distinction matters.
    private func inPan(_ art: UIImage, _ frame: CGRect, _ scale: CGFloat) -> some View {
        Image(uiImage: art).resizable().scaledToFit()
            .frame(width: frame.width * scale, height: frame.height * scale)
            .offset(x: (frame.midX - Self.stoveCentre.x) * scale,
                    y: (frame.midY - Self.stoveCentre.y) * scale)
    }

    private var melting: Bool { game?.isWorking == true }

    // MARK: The thermometer

    private func thermometer(_ geo: GeometryProxy) -> some View {
        let box = StationCanvas.rect(Self.meterFrame, in: geo)
        // Same reason as the stove: the needle has to be measured against the
        // art as drawn, not against the box the art is letterboxed inside.
        let scale = min(box.width / Self.meterFrame.width, box.height / Self.meterFrame.height)
        let size = CGSize(width: Self.meterFrame.width * scale,
                          height: Self.meterFrame.height * scale)
        let level = game?.fireLevel ?? Self.restingFire

        return ZStack {
            if let art = FoodArt.art("temperature-meter") {
                Image(uiImage: art).resizable().scaledToFit()
                    .frame(width: size.width, height: size.height)
            }

            // The pointer is drawn rather than placed: the thermometer artwork
            // is only the tube, and a needle baked into it couldn't move —
            // which is the whole point of it.
            NeedleShape()
                .fill(StationPalette.ink)
                .frame(width: size.width * Self.needleWidth,
                       height: size.width * Self.needleHeight)
                .offset(x: (Self.needleTip - 0.5) * size.width - size.width * Self.needleWidth / 2,
                        y: (Self.trackFraction(for: level) - 0.5) * size.height)
                .animation(.easeOut(duration: 0.12), value: level)
                .accessibilityLabel("Heat")
        }
        .frame(width: box.width, height: box.height)
        .position(x: box.midX, y: box.midY)
    }

    /// Fire level (0 cold, 1 burning) to a height on the thermometer.
    ///
    /// Anchored to the colours rather than stretched evenly, so that "the
    /// needle is in the green-to-yellow stripe" and "the butter is actually
    /// melting" are the same statement. `StationMinigame`'s safe band is
    /// 0.25...0.60, and those two levels land exactly on the bottom of the
    /// green and the top of the yellow. Spread evenly instead, the top of the
    /// band pointed at orange while the butter was melting perfectly well —
    /// a gauge that lies about the one thing it exists to say.
    private static func trackFraction(for level: Double) -> Double {
        func between(_ level: Double, _ fromLevel: Double, _ toLevel: Double,
                     _ fromY: Double, _ toY: Double) -> Double {
            let share = (level - fromLevel) / (toLevel - fromLevel)
            return fromY + (toY - fromY) * share
        }
        switch level {
        case ..<StationMinigame.safeBand.lowerBound:
            return between(level, 0, StationMinigame.safeBand.lowerBound, coldMiddle, greenBottom)
        case ..<StationMinigame.safeBand.upperBound:
            return between(level, StationMinigame.safeBand.lowerBound,
                           StationMinigame.safeBand.upperBound, greenBottom, yellowTop)
        default:
            return between(level, StationMinigame.safeBand.upperBound, 1, yellowTop, redTop)
        }
    }

    // MARK: Warning

    private func tooHotWarning(_ geo: GeometryProxy) -> some View {
        Text("Too hot — blow it down!")
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(StationPalette.cream)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(red: 0.78, green: 0.22, blue: 0.16)))
            .figmaPlaced(Self.controlFrame, in: geo)
            .transition(.opacity)
    }

    // MARK: Controls

    private func controls(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 10) {
            if let food = output {
                controlButton("Pick up") { collect(food) }
                controlButton("Leave", action: leave)
            } else if let drop = droppable {
                // One button for two objects: the butter goes down in the pan,
                // so the pan goes down with it.
                controlButton("Drop \(drop.name)", dimmed: dropBlockedReason != nil) {
                    setDown(drop)
                }
            } else if panContents != nil, action != nil {
                // Butter already waiting in the pan — someone set it down and
                // walked off, or this chef backed out mid-melt.
                controlButton("Start melting") { begin() }
            }
        }
        .figmaPlaced(Self.controlFrame, in: geo)
    }

    private func controlButton(_ title: String, dimmed: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(StationPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(StationPalette.cream))
                .overlay(Capsule().stroke(StationPalette.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
        // Dimmed but still tappable on purpose: a blocked drop has a reason,
        // and a button that does nothing at all never tells the chef what it
        // is. Tapping explains instead.
        .opacity(dimmed ? 0.5 : 1)
    }

    // MARK: Doing the thing

    /// Set the butter down — and the pan under it.
    private func setDown(_ butter: HeldIngredient) {
        if let reason = dropBlockedReason { alert = reason; return }

        session.deposit(butter.id, at: station)
        inventory.dropIngredient()
        // The pan stays on the stove with the butter in it. That is why the
        // chef had to bring one, and why both paws are empty in the art the
        // moment the butter goes down.
        inventory.dropUtensil()
        panSetDown = true

        begin()
    }

    /// Straight into the melting: the ring is already hot.
    private func begin() {
        guard let action, game == nil else { return }
        let game = StationMinigame(motion: action.motion)
        game.onFinish = { finish(action) }
        self.game = game
        game.start()
        flashTutorial()
    }

    private func finish(_ action: CookAction) {
        session.reportCompletion(actionID: action.id)
        game?.stop()
        // Clearing this is also what repaints the page — `session`'s station
        // tables aren't `@Published`, so the melted butter would otherwise sit
        // in the pan unseen until something else happened to redraw.
        withAnimation(.easeOut(duration: 0.35)) { game = nil }
    }

    private func collect(_ food: String) {
        if let blocked = handBlockMessage { alert = blocked; return }
        guard let taken = session.pickUpOutput(at: station) else { return }
        inventory.pickUp(HeldIngredient(id: taken,
                                        name: GatingBridge.displayName(taken),
                                        isPrep: true))
        onClose()
    }

    private func leave() {
        game?.stop()
        game = nil
        onClose()
    }

    /// The instruction, for a beat — the same 1.5s flash every station gives.
    private func flashTutorial() {
        tutorialFlash += 1
        let flash = tutorialFlash
        withAnimation(.easeInOut(duration: 0.15)) { showTutorial = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard flash == tutorialFlash else { return }
            withAnimation(.easeOut(duration: 0.3)) { showTutorial = false }
        }
    }
}

// MARK: - The needle

/// A small triangle pointing right, at the thermometer's scale.
private struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Nothing on the stove") {
    StoveStationView(station: .stove,
                     session: KitchenSession(role: .host),
                     inventory: PlayerInventory(ingredient: HeldIngredient(id: "butter", name: "Butter"),
                                                utensil: HeldUtensil(id: "pan", name: "Pan")),
                     onClose: {})
}

#Preview("Wrong tool in hand") {
    StoveStationView(station: .stove,
                     session: KitchenSession(role: .host),
                     inventory: PlayerInventory(ingredient: HeldIngredient(id: "butter", name: "Butter"),
                                                utensil: HeldUtensil(id: "whisk", name: "Whisk")),
                     onClose: {})
}
