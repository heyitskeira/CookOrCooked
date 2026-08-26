//
//  ChoppingStationView.swift
//  Cooked
//
//  The chopping station rebuilt against final art (CH5 art-direction folder,
//  "Chopping" flow). Every position below is copied from the Figma frame the
//  art was measured against, then scaled to whatever size the device
//  actually gives us — the same normalised-coordinate trick
//  `StationID.unitPosition` already uses for the kitchen map itself. See
//  `StationCanvas` for what that artboard actually is.
//
//  Scope: this is the whole chopping station now, start to finish, on one
//  page — arrive at an empty board (drop + a dimmed start button), load it,
//  tap to chop right here (`registerChopTap`), and the board itself swaps to
//  the chopped result once the progress bar fills. `KitchenScene.beginAction`
//  and the old `ChopOverlay` SpriteKit scene are no longer part of this
//  station's flow at all — see the comment on `registerChopTap` for why that
//  path was replaced rather than kept alongside this one.
//
//  Two numbers from the brief didn't match their source images and were
//  adjusted rather than forced — see the comments on `backButtonFrame` and
//  `cuttingBoardFrame` below.
//

import SwiftUI

struct ChoppingStationView: View {
    let station: StationID
    @ObservedObject var session: KitchenSession
    @ObservedObject var inventory: PlayerInventory
    var onClose: () -> Void

    @State private var alert: String?
    /// Shown once, briefly, the moment this screen appears.
    @State private var showTutorial = true

    /// True while the tap-to-chop minigame is running, right here on the
    /// board — there's no separate scene to switch to for this station
    /// anymore. Buttons hide, the whole screen becomes the tap target, and
    /// the progress bar reflects real taps instead of the earlier placeholder.
    @State private var isChopping = false
    @State private var chopTaps: Double = 0
    /// Same difficulty as the old SpriteKit minigame — see
    /// `ChopOverlay.setUpStation` (`amountNeeded = 7.0`) — so retiring that
    /// overlay for this station doesn't quietly change the game's balance.
    private let chopTapsNeeded: Double = 7
    /// Toggled (not tracked as a value) on every tap purely to retrigger the
    /// bounce animation on the board — the spring runs off the change, not
    /// off whatever this boolean happens to equal.
    @State private var chopBounce = false

    /// Every (x, y, w, h) below is measured against the shared station
    /// artboard — see `StationCanvas` for what that box is and why its origin
    /// isn't (0, 0).

    // MARK: Snapshot-derived state — same rules as StationPopupView

    private var completed: Set<Int> { Set(session.snapshot.completed) }
    // Read through the session's own host-aware accessors, not
    // `session.snapshot` directly: the snapshot only refreshes on the 10Hz
    // tick that `startCooking()` starts, which needs two connected players.
    // A solo/preview session never starts that tick, so a direct snapshot
    // read would show a deposit as never having happened at all — not late,
    // just permanently invisible. These two go straight to the host's own
    // live table instead, and still fall back to the snapshot for a guest.
    private var deposited: Set<String> { Set(session.depositedFoods(at: station)) }
    private var output: String? { session.outputFood(at: station) }

    /// Chopping only ever offers the one action, but reading it this way
    /// (rather than hardcoding action id 1) means this keeps working if the
    /// recipe ever adds a second chopping-station action.
    private var action: CookAction? {
        Recipe.actions.first {
            $0.id != GatingBridge.trashActionID
            && GameState.sharesActions(station, $0.station)
            && (!completed.contains($0.id) || $0.isRepeatable)
        }
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

    /// The board has something on it once either a raw deposit or a finished
    /// prep is sitting there.
    private var boardFood: String? { output ?? deposited.first }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StationGround(geo: geo)
                cuttingBoardLayer(geo)
                boardFoodLayer(geo)
                StationHands(inventory: inventory, geo: geo, pawAsset: session.localPawAsset)
                StationHeaderBar(title: action?.name ?? station.displayName,
                                 progress: chopProgress,
                                 badgeArt: "bucket-strawberries", geo: geo)

                // Underneath the corner buttons in z-order on purpose: back
                // and help stay reachable mid-chop (backing out, or
                // re-reading the tutorial), and only taps that miss both of
                // them fall through to this and count as a chop.
                if isChopping {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width, height: geo.size.height)
                        .onTapGesture(perform: registerChopTap)
                }

                StationBackButton(geo: geo, action: onClose)
                StationHelpButton(geo: geo, action: flashTutorial)
                controls(geo)

                if let alert {
                    PrepHeldAlert(message: alert) { self.alert = nil }
                }

                if showTutorial {
                    tutorialOverlay(geo)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { flashTutorial() }
    }

    // MARK: The board and what's on it

    /// Figma said (215, 319) — a portrait box. The source PNG is landscape
    /// (957x645, ratio 1.48), and 319x215 matches that ratio almost exactly,
    /// so this reads as the width/height having been swapped in the brief.
    private static let cuttingBoardFrame = (x: 277.0, y: 106.0, w: 319.0, h: 215.0)

    private func cuttingBoardLayer(_ geo: GeometryProxy) -> some View {
        Group {
            if let art = namedImage("cutting-board") {
                Image(uiImage: art).resizable().scaledToFit()
            }
        }
        .figmaPlaced(Self.cuttingBoardFrame.x, Self.cuttingBoardFrame.y,
                    Self.cuttingBoardFrame.w, Self.cuttingBoardFrame.h, in: geo)
    }

    /// Whatever's sitting on the board — looked up by whatever food id is
    /// actually there, not assumed. `depositable`/"Drop" will happily set
    /// the chopped result right back down here (a chef can pick it up and
    /// put it back), so the deposited slot cannot be hardcoded to always be
    /// raw strawberries the way it used to be — that showed the wrong art
    /// the moment anything else landed on the board.
    private func boardFoodLayer(_ geo: GeometryProxy) -> some View {
        Group {
            if let food = output, let art = namedImage(food) {
                Image(uiImage: art).resizable().scaledToFit()
                    .figmaPlaced(325, 159, 224, 119, in: geo)
            } else if let food = boardFood, let art = namedImage(food) {
                Image(uiImage: art).resizable().scaledToFit()
                    .figmaPlaced(332, 132, 210, 164, in: geo)
                    // A little kick per tap so chopping reads as an impact,
                    // not just a bar filling up somewhere else on screen.
                    .scaleEffect(chopBounce ? 0.94 : 1.0)
                    .animation(.interpolatingSpring(stiffness: 500, damping: 12), value: chopBounce)
            }
        }
    }

    // MARK: What the shared header bar fills with

    /// Empty before anything's on the board, live tap-by-tap while chopping,
    /// full once the chopped result exists — a real number now, not the
    /// placeholder this used to show before the minigame moved onto this page.
    private var chopProgress: CGFloat {
        if output != nil { return 1 }
        if isChopping { return CGFloat(chopTaps / chopTapsNeeded) }
        return 0
    }

    // MARK: Controls — drop/pick-up, then the single start button

    /// Hidden entirely while chopping — the board itself is the interaction
    /// once the minigame starts, and there's nothing here to drop, pick up,
    /// or start twice until it either finishes or the chef leaves.
    private func controls(_ geo: GeometryProxy) -> some View {
        // Centred on the board itself, so the buttons sit where the chef is
        // already looking.
        let board = StationCanvas.rect(Self.cuttingBoardFrame.x, Self.cuttingBoardFrame.y,
                                       Self.cuttingBoardFrame.w, Self.cuttingBoardFrame.h, in: geo)
        return Group {
            if !isChopping {
                VStack(spacing: 10) {
                    if output != nil {
                        // The chopped result is sitting on the board. Leave it
                        // there for someone else, or take it — either way,
                        // there's nothing left to do at this counter.
                        HStack(spacing: 10) {
                            controlButton("Leave", action: onClose)
                            controlButton("Pick up") {
                                if let blocked = handBlockMessage { alert = blocked; return }
                                if let taken = session.pickUpOutput(at: station) {
                                    inventory.pickUp(HeldIngredient(id: taken,
                                                                    name: GatingBridge.displayName(taken),
                                                                    isPrep: true))
                                }
                                // Stays open, like "Drop" does — closing here
                                // would hide the one thing this button is
                                // supposed to show: the hand now holding it.
                            }
                        }
                    } else if let food = deposited.first {
                        controlButton("Pick up \(GatingBridge.displayName(food))") {
                            if let blocked = handBlockMessage { alert = blocked; return }
                            if session.takeDeposit(food, at: station) {
                                inventory.pickUp(HeldIngredient(id: food, name: GatingBridge.displayName(food)))
                            }
                        }
                    } else if let drop = depositable {
                        controlButton("Drop \(drop.name)") {
                            session.deposit(drop.id, at: station)
                            inventory.dropIngredient()
                            // Stays open — the snapshot updates and the board/hand
                            // art swap on their own.
                        }
                    }

                    if let action, output == nil {
                        controlButton(startLabel(for: action), enabled: canDo(action)) {
                            isChopping = true
                            chopTaps = 0
                        }
                    }
                }
                .frame(width: board.width * 0.92)
                .position(x: board.midX, y: board.midY)
            }
        }
    }

    /// One tap = one chop. Finishes the action itself once enough land,
    /// rather than handing off to `onDoAction`/`KitchenScene.beginAction` —
    /// that path opened a separate SpriteKit scene (`ChopOverlay`), which is
    /// exactly what moving the minigame onto this page replaces. Everything
    /// `beginAction` would have re-checked (ingredients deposited, right
    /// utensil in hand) is already true by construction: `canDo` gated the
    /// button that got us into `isChopping` in the first place.
    private func registerChopTap() {
        guard isChopping, let action else { return }
        chopTaps = min(chopTapsNeeded, chopTaps + 1)
        chopBounce.toggle()
        if chopTaps >= chopTapsNeeded {
            isChopping = false
            session.reportCompletion(actionID: action.id)
            // `output` picks up the chopped result once the host processes
            // that (immediately, for the host) — boardFoodLayer and controls
            // above already show it and offer "Pick up" with no further
            // wiring needed here.
        }
    }

    private func startLabel(for action: CookAction) -> String {
        switch action.motion {
        case .chop: return "Start chopping"
        default:    return "Start"
        }
    }

    private func controlButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
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

    // MARK: Tutorial — a flash, not a screen

    /// Figma: hand-icon-tapnhold at (327, 99), 201x199. Text matches the
    /// minigame's own hint ("Tap to chop" — see ChopOverlay.setUpStation).
    private func tutorialOverlay(_ geo: GeometryProxy) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 4) {
                if let art = namedImage("hand-icon-tapnhold") {
                    Image(uiImage: art).resizable().scaledToFit()
                }
                Text("Tap")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .figmaPlaced(327, 99, 201, 199, in: geo)
        }
        .transition(.opacity)
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showTutorial = false } }
    }

    /// Shows the tutorial and hides it again after a beat — used both on
    /// first arrival and whenever the help button is tapped.
    private func flashTutorial() {
        withAnimation(.easeInOut(duration: 0.15)) { showTutorial = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) { showTutorial = false }
        }
    }

    // MARK: Art lookup

    private func namedImage(_ name: String) -> UIImage? { FoodArt.art(name) }
}

#Preview("Nothing dropped") {
    ChoppingStationView(station: .chopping,
                        session: KitchenSession(role: .host),
                        inventory: PlayerInventory(ingredient: HeldIngredient(id: "strawberries", name: "Strawberries"),
                                                   utensil: HeldUtensil(id: "knife", name: "Knife")),
                        onClose: {})
}

#Preview("Strawberries on the board") {
    let session = KitchenSession(role: .host)
    return ChoppingStationView(station: .chopping,
                               session: session,
                               inventory: PlayerInventory(utensil: HeldUtensil(id: "knife", name: "Knife")),
                               onClose: {})
}
