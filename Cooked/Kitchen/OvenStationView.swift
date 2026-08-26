//
//  OvenStationView.swift
//  Cooked
//
//  The oven counter rebuilt against final art, following the same shape as
//  `ChoppingStationView` and `BowlStationView`: one full-screen illustrated
//  page, every position measured on the shared artboard (see `StationCanvas`)
//  and scaled to whatever the device gives us.
//
//  Reference: `Asset-Final/Screens/11-stations/preheat-oven/`. Only three
//  frames were drawn — tutorial, enter-start, end-leave — because holding has
//  fewer distinct moments than the motion stations, and the oven itself is
//  still a dashed "oven here" placeholder in all of them. So the composition
//  comes from the chopping page, which was drawn properly: same header bar,
//  same corner buttons, same paws, and the prop centred on the same slab.
//
//  ---
//
//  Two actions live at this counter, and this page serves both:
//
//    8  Pre-heat oven   nothing to drop, no prep produced — just the hold
//    9  Bake base       raw dough goes in, a baked base comes out
//
//  Serving (12) is deliberately NOT one of them. It has its own ritual out on
//  the map (`ServeRitual`), and `KitchenScene.availableAction` already filters
//  it out of the station's action list — `action` below applies the same rule,
//  so routing this counter to a page cannot quietly swallow the serve flow.
//
//  ---
//
//  The oven door is the reward, not a progress read-out: it stays shut for the
//  whole hold and swings open at the end, with a short flash as the fire
//  catches. Once pre-heat is done it stays open, including on a later visit to
//  bake — which is the honest picture, since the oven really is still lit.
//
//  The hold itself is untouched: `StationMinigame(motion: .hold)` carries
//  `amountNeeded = 3.0` straight from `HoldOverlay`, so moving this counter
//  onto an illustrated page does not re-balance it.
//

import SwiftUI

struct OvenStationView: View {

    let station: StationID
    @ObservedObject var session: KitchenSession
    @ObservedObject var inventory: PlayerInventory
    var onClose: () -> Void

    @State private var alert: String?
    @State private var showTutorial = false
    /// Bumped on every flash so an older timer can't cut a fresh one short.
    @State private var tutorialFlash = 0

    /// The hold in progress, or nil while the chef is just standing here.
    ///
    /// Plain `@State` rather than `@StateObject` for the same reason
    /// `BowlStationView` uses it: this is not one long-lived object, it is a
    /// fresh game per action and nil in between.
    @State private var game: StationMinigame?
    @State private var runningAction: CookAction?

    /// Drives the white wipe as the fire catches. Separate from `ovenIsLit` so
    /// the flash only plays on the visit that actually lit it.
    @State private var flash: CGFloat = 0

    // MARK: Snapshot-derived state — same rules as the other station pages

    private var completed: Set<Int> { Set(session.snapshot.completed) }
    // Read through the session's host-aware accessors rather than the snapshot
    // directly: a solo session never starts the tick that refreshes it, so a
    // direct read would show a deposit as never having happened at all.
    private var deposited: Set<String> { Set(session.depositedFoods(at: station)) }
    private var output: String? { session.outputFood(at: station) }

    /// The next thing to do at this counter, or nil if there is nothing.
    ///
    /// The serve action is excluded to match `KitchenScene.availableAction`,
    /// which has always filtered it: serving is the ritual out on the map, not
    /// a counter action, and offering it here would give it a hold bar it was
    /// never designed to have.
    private var action: CookAction? {
        Recipe.actions.first {
            $0.id != ServeRitual.actionID
            && $0.id != GatingBridge.trashActionID
            && GameState.sharesActions(station, $0.station)
            && (!completed.contains($0.id) || $0.isRepeatable)
        }
    }

    /// Pre-heating: the action at this counter that consumes nothing and
    /// produces nothing. Found rather than hardcoded to id 8, so it survives
    /// the recipe being renumbered.
    private var preheatAction: CookAction? {
        Recipe.actions.first {
            $0.id != ServeRitual.actionID
            && GameState.sharesActions(station, $0.station)
            && $0.output == nil
        }
    }

    /// Is the fire lit? True once pre-heat is done — which means walking back
    /// in later to bake still finds an open, glowing oven rather than a cold
    /// shut one.
    private var ovenIsLit: Bool {
        guard let preheatAction else { return false }
        return completed.contains(preheatAction.id)
    }

    private var handBlockMessage: String? {
        if inventory.isHoldingRotten { return Rotten.blockedMessage }
        if inventory.isHoldingPrep   { return "You already held on to a prep!" }
        return nil
    }

    private func canDo(_ action: CookAction) -> Bool {
        guard output == nil else { return false }
        guard GatingBridge.requiredIngredients(for: action).isSubset(of: deposited) else { return false }
        if let need = GatingBridge.requiredUtensil(for: action) {
            return inventory.utensil?.id == need.rawValue
        }
        return true
    }

    private var depositable: HeldIngredient? {
        guard output == nil, let ing = inventory.ingredient,
              !ing.isRotten, !deposited.contains(ing.id) else { return nil }
        return ing
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StationGround(geo: geo)
                ovenLayer(geo)
                StationHands(inventory: inventory, geo: geo, pawAsset: session.localPawAsset)

                StationHeaderBar(title: runningAction?.name ?? action?.name ?? station.displayName,
                                 progress: game?.progress ?? (ovenIsLit ? 1 : 0),
                                 badgeArt: "prop-oven-dome", geo: geo)
                StationTimer(secondsRemaining: session.secondsRemaining, geo: geo)

                // Below the corner buttons in z-order on purpose: backing out
                // and re-reading the instruction stay possible mid-hold, and
                // only input that misses both counts as work.
                if let game {
                    MinigameSurface(game: game)
                }

                StationBackButton(geo: geo, action: leave)
                StationHelpButton(geo: geo, action: flashTutorial)
                controls(geo)

                // The fire catching. Sits over the station but under the
                // alert and the instruction card.
                Color.white
                    .opacity(flash)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if let alert {
                    PrepHeldAlert(message: alert) { self.alert = nil }
                }

                if showTutorial, let motion = (runningAction ?? action)?.motion {
                    StationInstructionOverlay(motion: motion,
                                              caption: (runningAction ?? action)?.name) {
                        withAnimation(.easeOut(duration: 0.2)) { showTutorial = false }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onDisappear { game?.stop() }
    }

    // MARK: The oven

    /// The oven's box, and it does NOT change when the door opens.
    ///
    /// Both exports are 684 tall and draw the dome at the same scale; the open
    /// one is wider only because the door swings out to the right. So both are
    /// drawn into the frame the *open* art needs, left-aligned: the open art
    /// fills it, and the closed art — being narrower — fits inside it at the
    /// same height against the same edge. Same height, same left edge, one
    /// constant frame, so the dome cannot move and the door is the only thing
    /// that appears.
    ///
    /// Giving each state its own frame (the obvious version of this) is what
    /// made the oven look like it grew: SwiftUI animates the layout change
    /// underneath the swap, so the box resizes at the same moment the picture
    /// does and the whole oven reads as stretching rather than opening.
    ///
    /// Sized to sit inside the dashed "oven here" box the reference draws,
    /// which measures (223, 57, 409, 271) on this artboard, and raised so that
    /// the oven and the button beneath it sit as one group in the middle of the
    /// stone rather than the oven alone — see `controlsFrame`.
    private static let ovenFrame = CGRect(x: 303, y: 62, width: 313, height: 250)

    /// The stone the whole station stands on. `StationGround` places it at
    /// (96, 25, 682, 381), so its middle is (437, 215) and its lower edge 406.
    private static let slabCentreX: CGFloat = 437
    private static let slabBottomY: CGFloat = 406

    /// Where the stonework actually ends inside the oven's frame. Both exports
    /// are 684 tall with the drawing occupying rows 43...624, so the frame
    /// carries roughly 6% dead space above the oven and 9% below it.
    ///
    /// The button is positioned off the drawing, not off the frame. Off the
    /// frame it would float a gap under the oven that corresponds to nothing a
    /// player can see.
    private static let ovenInkBottomFraction: CGFloat = 625.0 / 684.0

    private static var ovenInkBottomY: CGFloat {
        ovenFrame.minY + ovenFrame.height * ovenInkBottomFraction
    }

    /// The one thing the shared frame can't fix. Both canvases are 684 tall,
    /// but the closed art's content starts at x = 15 and the open art's at
    /// x = 25 — the door needed the extra room. Left-aligning the canvases
    /// therefore lands the closed dome 10 art-pixels to the left of the open
    /// one. Nudging the closed state right by that same 10, scaled to the box,
    /// puts the two domes on exactly the same pixel.
    private static let closedNudge: CGFloat = 10.0 / 684.0 * ovenFrame.height

    private func ovenLayer(_ geo: GeometryProxy) -> some View {
        let lit = ovenIsLit
        // Design units → device units, so the nudge tracks the screen the same
        // way every other measurement here does.
        let nudge = lit ? 0 : StationCanvas.rect(0, 0, Self.closedNudge, 0, in: geo).width

        return Group {
            if let art = FoodArt.art(lit ? "prop-oven-open" : "prop-oven-closed") {
                Image(uiImage: art).resizable().scaledToFit()
            }
        }
        .figmaPlaced(Self.ovenFrame, alignment: .leading, in: geo)
        .offset(x: nudge)
        // No animation on the swap on purpose. The white flash is already
        // covering this exact moment, and animating anything here is what
        // would put movement back into an oven that must not move.
    }

    // MARK: Controls

    /// Hidden entirely while the hold is running — the whole screen is the
    /// button then, and there is nothing to drop, take or start twice until it
    /// finishes or the chef leaves.
    /// Directly under the oven, not over it. The chopping page centres its
    /// buttons on the board because a board is a flat surface with nothing to
    /// hide; a lit oven is the thing the chef came here to look at, and a
    /// button across its mouth covers the fire.
    ///
    /// The box starts at the stonework's lower edge and runs to the bottom of
    /// the slab, and the buttons are laid out `.top`-aligned inside it — so
    /// they sit flush under the oven whatever height the row turns out to be.
    /// (It can't be pinned in design units: `controlButton` is 42 *points*
    /// tall, which is a different number of design units on every screen.)
    ///
    /// Centred on the slab rather than on the oven's own frame. That frame is
    /// sized for the open door, which hangs off to the right, so centring on it
    /// would shove the button sideways the moment the oven lit.
    private static var controlsFrame: CGRect {
        CGRect(x: slabCentreX - ovenFrame.width / 2,
               y: ovenInkBottomY,
               width: ovenFrame.width,
               height: slabBottomY - ovenInkBottomY)
    }

    private func controls(_ geo: GeometryProxy) -> some View {
        Group {
            if game == nil {
                VStack(spacing: 10) {
                    if let food = output {
                        // Something baked is sitting in the oven. Take it or
                        // leave it for someone else — either way this counter
                        // has nothing else to give.
                        HStack(spacing: 10) {
                            controlButton("Leave", action: onClose)
                            controlButton("Pick up") { collect(food) }
                        }
                    } else if let food = deposited.first {
                        controlButton("Pick up \(GatingBridge.displayName(food))") {
                            takeBack(food)
                        }
                    } else if let drop = depositable {
                        controlButton("Drop \(drop.name)") {
                            session.deposit(drop.id, at: station)
                            inventory.dropIngredient()
                        }
                    }

                    if let action, output == nil {
                        controlButton(startLabel(for: action), enabled: canDo(action)) {
                            begin(action)
                        }
                    }
                }
                .figmaPlaced(Self.controlsFrame, alignment: .top, in: geo)
            }
        }
    }

    private func startLabel(for action: CookAction) -> String {
        action.output == nil ? "Start heating" : "Start baking"
    }

    private func controlButton(_ title: String, enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(StationPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Capsule().fill(StationPalette.cream))
                .overlay(Capsule().stroke(StationPalette.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
    }

    // MARK: Doing it

    private func begin(_ action: CookAction) {
        guard canDo(action) else { return }

        runningAction = action
        let game = StationMinigame(motion: action.motion)
        game.onFinish = { finish(action) }
        self.game = game
        game.start()
        // The instruction flashes over the top while the hold is already live
        // underneath, so the chef starts the moment it clears.
        flashTutorial()
    }

    /// Done. Report it, then light the oven with a flash — the door swap falls
    /// out of `ovenIsLit` once the completion lands.
    private func finish(_ action: CookAction) {
        session.reportCompletion(actionID: action.id)
        game?.stop()

        if action.output == nil { lightTheFire() }

        // Clearing these is also what repaints the page: the session's station
        // tables aren't `@Published`, so the result would otherwise sit unseen
        // until something else happened to redraw.
        withAnimation(.easeOut(duration: 0.35)) {
            game = nil
            runningAction = nil
        }
    }

    /// A short white wipe as the fire catches. Fast in, slower out — a flash
    /// that lingers reads as a loading screen rather than a spark.
    private func lightTheFire() {
        withAnimation(.easeIn(duration: 0.07)) { flash = 0.78 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(.easeOut(duration: 0.3)) { flash = 0 }
        }
    }

    private func takeBack(_ food: String) {
        if let blocked = handBlockMessage { alert = blocked; return }
        if session.takeDeposit(food, at: station) {
            inventory.pickUp(HeldIngredient(id: food, name: GatingBridge.displayName(food)))
        }
    }

    private func collect(_ food: String) {
        if let blocked = handBlockMessage { alert = blocked; return }
        if let taken = session.pickUpOutput(at: station) {
            inventory.pickUp(HeldIngredient(id: taken,
                                            name: GatingBridge.displayName(taken),
                                            isPrep: true))
        }
        // Stays open, like "Drop" does — closing here would hide the one thing
        // this button exists to show: the hand now holding it.
    }

    /// Out of the station. Stops the clock on the way: a timer left running
    /// keeps ticking at the other end of the kitchen.
    private func leave() {
        game?.stop()
        game = nil
        runningAction = nil
        onClose()
    }

    // MARK: Tutorial — a flash, not a screen

    /// Shows the instruction for whatever is next here and takes it away again
    /// after a beat. The help button calls the same thing, which is what makes
    /// it a re-read rather than a separate screen.
    private func flashTutorial() {
        guard (runningAction ?? action) != nil else { return }
        tutorialFlash += 1
        let flash = tutorialFlash
        withAnimation(.easeInOut(duration: 0.15)) { showTutorial = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Only the newest flash may put the card away; an older timer
            // firing late would cut a fresh instruction short.
            guard flash == tutorialFlash else { return }
            withAnimation(.easeOut(duration: 0.3)) { showTutorial = false }
        }
    }
}

#Preview("Cold oven") {
    OvenStationView(station: .ovenServe,
                    session: KitchenSession(role: .host),
                    inventory: PlayerInventory(),
                    onClose: {})
}

#Preview("Dough in hand") {
    OvenStationView(station: .ovenServe,
                    session: KitchenSession(role: .host),
                    inventory: PlayerInventory(ingredient: HeldIngredient(id: "rawDough",
                                                                          name: "Raw dough",
                                                                          isPrep: true)),
                    onClose: {})
}
