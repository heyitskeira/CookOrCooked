//
//  BowlStationView.swift
//  Cooked
//
//  The bowl counters (bowl 1 and bowl 2) rebuilt against final art, on one
//  full-screen page — the second station to move off the SpriteKit overlays
//  after chopping. Positions come from the shared station artboard; see
//  `StationCanvas` for what that box is, and `StationChrome` for the header
//  bar, corner buttons, ground and paws every station page shares.
//
//  Unlike the chopping board, a bowl does more than one thing: both bowls
//  share a pool of actions (`GameState.sharesActions`) and the chef picks
//  which one to do. So the arrival state is an empty bowl, a card per action
//  showing what that action needs, and a button that tips whatever is in hand
//  into the bowl. A card only becomes tappable once everything it needs is
//  actually in the bowl.
//
//  Nothing here is written per-ingredient or per-action: the cards, their
//  requirement icons, the drop button's label, what the bowl looks like with
//  food in it and which instruction overlay a choice raises are all read from
//  `Recipe`/`GatingBridge` and the asset catalog. Adding a fifth bowl action
//  to the recipe puts a fifth card on this page with no edit here.
//
//  Scope: this is the arrival state. Choosing an action flashes its
//  instruction overlay for a beat, the way chopping does — the minigame that
//  instruction is teaching is the next piece of work, and `chosenAction` is
//  the seam it hangs off.
//

import SwiftUI

struct BowlStationView: View {

    let station: StationID
    @ObservedObject var session: KitchenSession
    @ObservedObject var inventory: PlayerInventory
    var onClose: () -> Void

    @State private var alert: String?
    /// What the chef picked to do here. Nil is the arrival state.
    @State private var chosenAction: CookAction?
    @State private var showTutorial = false
    /// The action being performed right now, and how far through it the chef
    /// is. Nil whenever the chef is still choosing.
    ///
    /// Plain `@State` rather than `@StateObject` because it isn't one object
    /// for the life of the screen — it's a fresh one per attempt, built for
    /// whichever motion was picked. Whatever needs to watch it observes it
    /// itself; see `BowlWorkLayer`.
    @State private var game: StationMinigame?
    /// Stamps each flash of the overlay. Picking a second action restarts the
    /// 1.5s timer, and without this the *first* timer would still fire and cut
    /// the second instruction short.
    @State private var tutorialFlash = 0

    // MARK: Layout — design-space frames (see `StationCanvas`)

    /// From the art brief: (299, 98), 276x231. The source PNG is 828x693,
    /// ratio 1.195, and 276x231 is 1.195 — so unlike the chopping board's box
    /// this one needed no correcting.
    private static let bowlFrame = CGRect(x: 299, y: 98, width: 276, height: 231)

    /// Where food actually rests: the bowl's interior floor, not the whole
    /// image. Kept as fractions of `bowlFrame` so it follows the bowl if the
    /// bowl is ever repositioned.
    private static let wellInset = (x: 0.19, y: 0.32, w: 0.62, h: 0.36)

    /// The row of action cards, centred over the bowl.
    ///
    /// Sits ~28 units higher than the art direction places it. In the
    /// reference the cards cover the middle of the bowl, which is fine for a
    /// mockup of an *empty* bowl but hides the food the moment anything is
    /// dropped in — and seeing it land is the whole point of the drop button.
    /// Raising the row clears the bowl's floor band instead.
    private static let actionRowFrame = CGRect(x: 235, y: 83, width: 405, height: 120)

    /// The drop / pick-up row under the cards. Wider than a single button
    /// needs: a bowl holding two ingredients offers a way back out for each of
    /// them, alongside whatever the chef is still carrying.
    private static let controlFrame = CGRect(x: 250, y: 254, width: 375, height: 46)

    // MARK: Snapshot-derived state

    private var completed: Set<Int> { Set(session.snapshot.completed) }
    // Read through the session's own host-aware accessors, not
    // `session.snapshot` directly: the snapshot only refreshes on the 10Hz
    // tick that `startCooking()` starts, which needs two connected players. A
    // solo/preview session never starts that tick, so a direct snapshot read
    // would show a deposit as never having happened at all — not late, just
    // permanently invisible, which would leave every card here dimmed for
    // good. See `KitchenScene.depositedFoods`.
    private var depositedFoods: [String] { session.depositedFoods(at: station) }
    private var deposited: Set<String> { Set(depositedFoods) }
    private var output: String? { session.outputFood(at: station) }

    /// Every action this counter offers, in recipe order.
    ///
    /// Both bowls share one pool, so they show the same cards — that is the
    /// point of a bowl: the station doesn't decide, the chef does.
    private var actions: [CookAction] {
        Recipe.actions.filter {
            $0.id != GatingBridge.trashActionID && GameState.sharesActions(station, $0.station)
        }
    }

    /// Done for good. Repeatable actions never count as finished.
    private func isFinished(_ action: CookAction) -> Bool {
        !action.isRepeatable && completed.contains(action.id)
    }

    /// A card lights up only when everything it needs is in the bowl already —
    /// plus the tool it takes, if it takes one, being in hand.
    private func canDo(_ action: CookAction) -> Bool {
        guard output == nil, !isFinished(action) else { return false }
        guard GatingBridge.requiredIngredients(for: action).isSubset(of: deposited) else { return false }
        if let need = GatingBridge.requiredUtensil(for: action) {
            return inventory.utensil?.id == need.rawValue
        }
        return true
    }

    /// What a card shows: everything the action needs, ingredients first and
    /// the tool last.
    ///
    /// `requiredIngredients` hands back a Set, which has no order — a card
    /// whose icons shuffled between launches would look broken — so they're
    /// sorted by display name, which is also the order the art direction lays
    /// them out in.
    private func requirements(of action: CookAction) -> [String] {
        let foods = GatingBridge.requiredIngredients(for: action).sorted {
            GatingBridge.displayName($0) < GatingBridge.displayName($1)
        }
        return foods + [GatingBridge.requiredUtensil(for: action)?.rawValue].compactMap { $0 }
    }

    private var handBlockMessage: String? {
        if inventory.isHoldingRotten { return Rotten.blockedMessage }
        if inventory.isHoldingPrep   { return "You already held on to a prep!" }
        return nil
    }

    /// What the chef could tip into the bowl right now — whatever is in hand,
    /// as long as the bowl isn't already holding a finished prep and doesn't
    /// already have one of these in it.
    private var depositable: HeldIngredient? {
        guard output == nil, let ing = inventory.ingredient,
              !ing.isRotten, !deposited.contains(ing.id) else { return nil }
        return ing
    }

    /// What's lying loose in the bowl, in the order it went in.
    ///
    /// A finished prep is deliberately not in this list: it has swallowed the
    /// ingredients it was made from and become the bowl itself — see
    /// `bowlLayer`.
    private var bowlContents: [String] {
        output == nil ? depositedFoods : []
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StationGround(geo: geo)
                bowlLayer(geo)

                // Mid-action, everything that changes as the chef works lives
                // in one child view, because a child is what gets to observe
                // the minigame. The choices vanish while it runs: there's
                // nothing to drop, pick up, or start twice until it ends.
                if let game, let action = chosenAction {
                    BowlWorkLayer(game: game, title: action.name,
                                  foods: bowlContents, well: Self.well, geo: geo)
                } else {
                    choosingLayer(geo)
                }

                StationHands(inventory: inventory, geo: geo)
                StationTimer(secondsRemaining: session.secondsRemaining, geo: geo)

                StationBackButton(geo: geo, action: leave)
                StationHelpButton(geo: geo, action: flashTutorial)

                if let alert {
                    PrepHeldAlert(message: alert) { self.alert = nil }
                }

                if showTutorial, let motion = chosenAction?.motion {
                    StationInstructionOverlay(motion: motion, caption: chosenAction?.name) {
                        withAnimation(.easeOut(duration: 0.2)) { showTutorial = false }
                    }
                }
            }
        }
        .ignoresSafeArea()
        // Walking away with the cover, not just with the back button: the
        // sensors have to be switched off either way.
        .onDisappear { game?.stop() }
    }

    /// The arrival state: what's in the bowl, what this counter can do, and
    /// what the chef can move in or out of it.
    private func choosingLayer(_ geo: GeometryProxy) -> some View {
        // Lifting straight from the bowl is off while a finished prep is
        // sitting in it — that one leaves by its own button, into a hand the
        // station has to check first.
        var lift: ((String) -> Void)?
        if output == nil { lift = { food in takeBack(food) } }

        return ZStack {
            BowlContents(foods: bowlContents, well: Self.well, geo: geo, onTap: lift)
            StationHeaderBar(title: chosenAction?.name ?? station.displayName, geo: geo)
            // The cards come down while a finished prep is sitting in the
            // bowl: not one of them can run until it's taken, and they'd be
            // covering the very thing the chef came back for.
            if output == nil {
                actionCards(geo)
            }
            controls(geo)
        }
    }

    // MARK: The bowl and what's in it

    /// The bowl — or, once an action has been finished here, the prep itself.
    ///
    /// Every prep's artwork is a bowl with the prep sitting in it, so a
    /// finished prep replaces the empty bowl rather than being drawn inside
    /// it. The box is taller than `bowlFrame` and bottom-aligned: some preps
    /// stand proud of the rim (whipped cream peaks well above it), and giving
    /// them room upwards keeps every bowl's base on the same line.
    private func bowlLayer(_ geo: GeometryProxy) -> some View {
        let bowl = Self.bowlFrame
        let box = CGRect(x: bowl.minX, y: bowl.minY - bowl.height * 0.14,
                         width: bowl.width, height: bowl.height * 1.14)

        return Group {
            if let food = output, let art = FoodArt.art(food) {
                Image(uiImage: art).resizable().scaledToFit()
            } else if let art = FoodArt.art("empty-bowl") {
                Image(uiImage: art).resizable().scaledToFit()
            }
        }
        .figmaPlaced(box, alignment: .bottom, in: geo)
        // Swapped rather than cross-faded in place, so the finished prep
        // arrives as an event the chef can see.
        .id(output ?? "empty-bowl")
        .transition(.opacity)
    }

    /// The bowl's interior floor, in design space.
    private static var well: CGRect {
        CGRect(x: bowlFrame.minX + bowlFrame.width * wellInset.x,
               y: bowlFrame.minY + bowlFrame.height * wellInset.y,
               width: bowlFrame.width * wellInset.w,
               height: bowlFrame.height * wellInset.h)
    }

    // MARK: The action cards

    private func actionCards(_ geo: GeometryProxy) -> some View {
        let row = StationCanvas.rect(Self.actionRowFrame, in: geo)

        return HStack(spacing: row.width * 0.015) {
            ForEach(actions, id: \.id) { action in
                actionCard(action)
            }
        }
        .figmaPlaced(Self.actionRowFrame, in: geo)
    }

    private func actionCard(_ action: CookAction) -> some View {
        let enabled = canDo(action)

        return Button { choose(action) } label: {
            VStack(spacing: 6) {
                Text(action.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(StationPalette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)

                HStack(spacing: 4) {
                    ForEach(requirements(of: action), id: \.self) { needed in
                        requirementIcon(needed)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            // Only the card's *contents* dim. Fading the whole card fades its
            // cream backing too, and four ghost cards over a busy forest are
            // unreadable — the first build of this screen looked like the
            // bowl was sitting on top of them.
            .opacity(enabled ? 1 : 0.4)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(StationPalette.cream))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StationPalette.ink.opacity(enabled ? 0.5 : 0.15), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        // Deliberately NOT `.disabled()`: SwiftUI fades a disabled button's
        // whole label, cream backing and all, and four washed-out cards over a
        // busy forest are unreadable — which is the opposite of the point,
        // since a chef reads the dim cards to learn what to go and fetch. The
        // taps are turned off instead, and `choose` re-checks so nothing can
        // sneak through.
        .allowsHitTesting(enabled)
        .accessibilityLabel(accessibilityLabel(for: action, enabled: enabled))
    }

    /// One ingredient or tool a card asks for. Drawn bare — the art direction
    /// puts the items straight on the card, with no tile behind them.
    private func requirementIcon(_ id: String) -> some View {
        Group {
            if let art = FoodArt.art(id) {
                Image(uiImage: art).resizable().scaledToFit()
            } else {
                // No artwork yet: the tinted symbol `FoodArt` keeps for
                // exactly this, so a new ingredient is still legible.
                Image(systemName: FoodArt.look(id).symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(FoodArt.look(id).tint)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func accessibilityLabel(for action: CookAction, enabled: Bool) -> String {
        let needs = requirements(of: action).map { GatingBridge.displayName($0) }
        let list = needs.joined(separator: ", ")
        if isFinished(action) { return "\(action.name), already done" }
        return enabled ? action.name : "\(action.name), needs \(list)"
    }

    // MARK: Drop / pick up

    /// The row under the bowl: tip what's in hand in, take a finished prep
    /// out, or take back anything already dropped.
    ///
    /// One button per thing that can move, rather than a single button that
    /// changes meaning — a bowl can hold several ingredients at once (macerate
    /// takes two), so "the" ingredient to pick up isn't a thing the station
    /// can guess at.
    private func controls(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 8) {
            if let food = output {
                // A finished prep is on its own: the ingredients that went
                // into it are gone, so there is nothing else to take.
                controlButton("Pick up \(GatingBridge.displayName(food))") {
                    collectOutput(food)
                }
            } else {
                if let drop = depositable {
                    // Label comes from whatever is actually in hand — this
                    // button is never written for one ingredient.
                    controlButton("Drop \(drop.name)") {
                        session.deposit(drop.id, at: station)
                        inventory.dropIngredient()
                        // Stays open: the bowl art and the cards above update
                        // on their own now the bowl holds one more thing.
                    }
                }

                ForEach(depositedFoods, id: \.self) { food in
                    controlButton("Pick up \(GatingBridge.displayName(food))") {
                        takeBack(food)
                    }
                }
            }
        }
        .figmaPlaced(Self.controlFrame, in: geo)
    }

    /// Take one ingredient back out of the bowl.
    ///
    /// Refuses rather than overwrites when the hand isn't free:
    /// `PlayerInventory.pickUp` replaces the ingredient slot outright, and the
    /// thing it replaced is simply gone — an ingredient the team may have to
    /// walk back to storage for.
    private func takeBack(_ food: String) {
        if let blocked = handBlockMessage { alert = blocked; return }
        guard inventory.ingredient == nil else {
            alert = "Your hands are already full!"
            return
        }
        guard session.takeDeposit(food, at: station) else { return }
        inventory.pickUp(HeldIngredient(id: food,
                                        name: GatingBridge.displayName(food),
                                        isPrep: isPrep(food)))
    }

    private func collectOutput(_ food: String) {
        if let blocked = handBlockMessage { alert = blocked; return }
        guard let taken = session.pickUpOutput(at: station) else { return }
        inventory.pickUp(HeldIngredient(id: taken,
                                        name: GatingBridge.displayName(taken),
                                        isPrep: true))
        onClose()
    }

    /// A prep rather than a raw ingredient: anything some action produces.
    /// Worth getting right on the way back into the hand — a held prep locks
    /// that hand until it's put down, and a prep mislabelled as raw would slip
    /// straight past that rule.
    private func isPrep(_ food: String) -> Bool {
        Recipe.actions.contains { $0.output == food }
    }

    private func controlButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(StationPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(StationPalette.cream))
                .overlay(Capsule().stroke(StationPalette.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Choosing an action, and doing it

    private func choose(_ action: CookAction) {
        // The card row already stops taps on a card that isn't ready; this is
        // the check that makes that a rule rather than a look.
        guard canDo(action) else { return }

        chosenAction = action
        let game = StationMinigame(motion: action.motion)
        game.onFinish = { finish(action) }
        self.game = game
        game.start()
        // The instruction flashes over the top while the action is already
        // live underneath, so the chef starts working the moment it clears —
        // the same quick pop-up the chopping station gives.
        flashTutorial()
    }

    /// The action is done: hand it to the session, which consumes what was in
    /// the bowl and leaves the prep sitting there.
    private func finish(_ action: CookAction) {
        session.reportCompletion(actionID: action.id)
        game?.stop()
        withAnimation(.easeOut(duration: 0.35)) { swapInPrep() }
    }

    /// Clearing these is also what repaints the page — `session`'s station
    /// tables aren't `@Published`, so the new prep would otherwise sit in the
    /// bowl unseen until something else happened to redraw.
    private func swapInPrep() {
        game = nil
        chosenAction = nil
    }

    /// Out of the station. Stops the clock and the sensors on the way — device
    /// motion left running keeps draining the battery at the other end of the
    /// kitchen.
    private func leave() {
        game?.stop()
        game = nil
        onClose()
    }

    /// Shows the instruction for the chosen action and takes it away again
    /// after a beat — the same 1.5s flash the chopping station uses. The help
    /// block calls this too, which is what makes it a re-read rather than a
    /// separate screen.
    private func flashTutorial() {
        guard chosenAction != nil else { return }
        tutorialFlash += 1
        let flash = tutorialFlash
        withAnimation(.easeInOut(duration: 0.15)) { showTutorial = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Only the newest flash may put the overlay away; an older timer
            // firing late would cut a fresh instruction short.
            guard flash == tutorialFlash else { return }
            withAnimation(.easeOut(duration: 0.3)) { showTutorial = false }
        }
    }
}

// MARK: - What's in the bowl

/// Everything sitting in the bowl, shared out across the floor of it.
///
/// Each item is bottom-aligned so it reads as resting on the floor rather than
/// floating in the middle, and the slots narrow as more goes in, so two
/// ingredients sit side by side instead of one hiding the other.
private struct BowlContents: View {

    let foods: [String]
    /// The bowl's interior floor, in design space.
    let well: CGRect
    let geo: GeometryProxy
    /// The motion being performed right now, or nil when nobody's working.
    ///
    /// The food moves the way the action does — swirling under a whisk,
    /// juddering under a shake — which is what tells the chef the action is
    /// running now that there's no label saying so.
    var working: ActionMotion?
    /// Lifting something straight out of the bowl. Nil once there's a finished
    /// prep in there, or while an action is running.
    var onTap: ((String) -> Void)?

    /// Flipped on once the action starts, and the repeating animation runs
    /// off that single change — the value it settles on doesn't matter, only
    /// that it changed.
    @State private var phase = false

    /// Whisking: the food goes round with the finger.
    private var spin: Double { working == .whisk && phase ? 360 : 0 }

    /// Shaking and flicking: a fast little sideways judder. It starts at the
    /// far side so the first frame is already off-centre, or the shake reads
    /// as a drift rather than a jolt.
    private var judder: CGFloat {
        guard working == .sift || working == .breakEgg else { return 0 }
        return phase ? 5 : -5
    }

    /// Holding: the pile is pressed down and lets go.
    private var squash: CGFloat {
        guard working == .hold || working == .mix || working == .melt else { return 1 }
        return phase ? 0.9 : 1
    }

    private var workAnimation: Animation? {
        switch working {
        case .whisk:
            // No autoreverse: a full turn that repeats reads as continuous
            // stirring rather than a wrist twisting back and forth.
            return .linear(duration: 1.1).repeatForever(autoreverses: false)
        case .sift, .breakEgg:
            return .easeInOut(duration: 0.07).repeatForever(autoreverses: true)
        case .none:
            // Nil, so putting the food back where it was is instant — an
            // animation here would leave it drifting after the chef stopped.
            return nil
        default:
            return .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
        }
    }

    var body: some View {
        let slot = foods.isEmpty ? well.width : well.width / CGFloat(foods.count)
        // A single item shouldn't swell to fill the whole bowl, and a crowd
        // shouldn't shrink to nothing.
        let itemWidth = min(slot * 0.95, well.width * 0.62)

        ZStack {
            ForEach(Array(foods.enumerated()), id: \.offset) { index, food in
                if let art = bowlArt(food) {
                    Image(uiImage: art)
                        .resizable()
                        .scaledToFit()
                        .rotationEffect(.degrees(spin))
                        .offset(x: judder)
                        .scaleEffect(squash)
                        .animation(workAnimation, value: phase)
                        // The direct way back out: what's in the bowl can be
                        // lifted straight from it. The buttons below say the
                        // same thing in words, for anyone who doesn't think to
                        // try the bowl.
                        .contentShape(Rectangle())
                        .onTapGesture { onTap?(food) }
                        .allowsHitTesting(onTap != nil)
                        .accessibilityLabel("Pick up \(GatingBridge.displayName(food))")
                        .figmaPlaced(well.minX + slot * CGFloat(index) + (slot - itemWidth) / 2,
                                     well.minY,
                                     itemWidth,
                                     well.height,
                                     alignment: .bottom,
                                     in: geo)
                }
            }
        }
        .onAppear { phase = working != nil }
        .onChange(of: working) { _, now in phase = now != nil }
    }

    /// How a food looks lying loose in the bowl rather than in the thing that
    /// carries it — see `FoodArt.looseArt`.
    private func bowlArt(_ food: String) -> UIImage? { FoodArt.looseArt(food) }
}

// MARK: - Doing the action

/// The station while an action is being performed: the bowl, the bar filling
/// up, what to do in words, and the surface that listens for it.
///
/// A view of its own because it's what observes the minigame — the page around
/// it doesn't need to redraw sixty times a second.
private struct BowlWorkLayer: View {

    @ObservedObject var game: StationMinigame
    let title: String
    let foods: [String]
    let well: CGRect
    let geo: GeometryProxy

    /// Under the bowl, where the choices were.
    private static let noticeFrame = CGRect(x: 250, y: 250, width: 375, height: 34)

    var body: some View {
        ZStack {
            BowlContents(foods: foods, well: well, geo: geo,
                         working: game.isWorking ? game.motion : nil)

            StationHeaderBar(title: title, progress: game.progress, geo: geo)

            // No standing "how to do it" label any more — that lives in the
            // instruction overlay now, and the food's own movement is what
            // says the action is under way. This is only the egg's per-attempt
            // verdict ("Too soft"), which nothing else can tell the chef.
            if let notice = game.notice {
                Text(notice)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(StationPalette.cream)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(StationPalette.ink))
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: game.notice)
                    .figmaPlaced(Self.noticeFrame, in: geo)
            }

            // Last, so it covers the bowl and the hint — but the page draws
            // the back and help buttons after this layer, which keeps those
            // two reachable mid-action.
            MinigameSurface(game: game)
        }
    }
}

#Preview("Empty bowl, sugar in hand") {
    BowlStationView(station: .bowl2,
                    session: KitchenSession(role: .host),
                    inventory: PlayerInventory(ingredient: HeldIngredient(id: "sugar", name: "Sugar")),
                    onClose: {})
}

#Preview("Whisk in hand") {
    BowlStationView(station: .bowl2,
                    session: KitchenSession(role: .host),
                    inventory: PlayerInventory(ingredient: HeldIngredient(id: "cream", name: "Cream"),
                                               utensil: HeldUtensil(id: "whisk", name: "Whisk")),
                    onClose: {})
}
