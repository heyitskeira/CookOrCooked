//
//  KitchenGameView.swift
//  Cooked
//
//  Hosts the SpriteKit kitchen and hands it the session, which is what turns
//  a single-player scene into a shared one. The scene is built exactly once —
//  rebuilding it on a SwiftUI redraw would reset every chef to the middle of
//  the room.
//

import SwiftUI
import SpriteKit

struct KitchenGameView: View {

    @ObservedObject var session: KitchenSession

    @State private var scene: KitchenScene?

    // This device's hands (local, not networked — each player owns their own).
    @StateObject private var inventory = PlayerInventory()
    // Utensil stock. Local for now; host-owned in multiplayer (see netcode spec).
    @StateObject private var pantry = StoragePantry()
    // Drawer shelves. Local fallback only; host-owned once a game is running.
    @StateObject private var drawerBox = DrawerBox()
    @State private var showStorage = false
    @State private var showDrawer = false
    /// True while a station screen is up inside the scene. SwiftUI chrome is
    /// drawn above the SpriteView, so the scene has to tell us to get out of
    /// the way — the station screen has its own hands.
    @State private var headsDown = false
    // The station whose popup is open (drop/pick-up vs do-action), if any.
    @State private var activeStation: StationID?
    // The prep just produced, awaiting the "hands vs station" choice.
    @State private var finishedPrep: PrepResult?
    @State private var showRecipe = false
    // The recipe step whose page is open inside that overlay, if any. Held
    // here rather than in the spread so closing the overlay can't strand a
    // step's page open behind it.
    @State private var openRecipeStep: BookStep?
    // Raised when a chef carrying rot taps anywhere but the bin.
    @State private var showRottenAlert = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let scene {
                    SpriteView(scene: scene)
                        .ignoresSafeArea()
                } else {
                    AppTheme.background
                }

                // The inventory bar used to live here, bottom-centre. It is
                // gone on purpose: the chef's hands inside the scene show the
                // same two slots, and the bar's 260x125 footprint sat directly
                // on top of the oven station once the kitchen became a ring.
                // Moving it doesn't help — top-centre covers three more
                // stations. Rotten ingredients are marked on the hand instead.

                if showStorage {
                    StorageView(inventory: inventory, pantry: pantry, session: session, onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) { showStorage = false }
                    })
                    .transition(.opacity)
                }

                if showDrawer {
                    DrawerView(inventory: inventory, box: drawerBox, session: session, onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) { showDrawer = false }
                    })
                    .transition(.opacity)
                }

                if let station = activeStation {
                    StationPopupView(
                        station: station,
                        session: session,
                        inventory: inventory,
                        onDoAction: { action in scene?.beginAction(action) },
                        onClose: { withAnimation(.easeInOut(duration: 0.15)) { activeStation = nil } }
                    )
                    .transition(.opacity)
                }

                if let prep = finishedPrep {
                    ResultPopupView(
                        result: prep,
                        session: session,
                        inventory: inventory,
                        onDone: { withAnimation(.easeInOut(duration: 0.15)) { finishedPrep = nil } }
                    )
                    .transition(.opacity)
                }

                // The recipe pages, reopenable mid-match — just the pages
                // (RecipeSpreadView), not the whole RecipeBookView: no backdrop,
                // no back button that would ask to leave the kitchen, no START
                // signpost. Only the head chef gets the trigger button —
                // anyone else would just see the "waiting for head chef"
                // placeholder, which defeats the point of checking it.
                if showRecipe {
                    ZStack {
                        // The book is scaled to fit, so it leaves wide gutters
                        // either side. Without something in them, taps land on
                        // the SpriteKit scene underneath and the chef walks off
                        // while the recipe is up.
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { }

                        // Mid-match the book is a reference, so a step's page
                        // replaces the list in place rather than pushing the
                        // chef somewhere new.
                        if let step = openRecipeStep {
                            StepDetailView(step: step)
                                .padding(20)
                        } else {
                            RecipeSpreadView(session: session,
                                             openStep: $openRecipeStep)
                                .padding(20)
                        }
                    }
                    .transition(.opacity)
                    .zIndex(3)
                    .overlay(alignment: .topTrailing) {
                        // One button, two jobs, because the pages are a stack:
                        // from a step it goes back to the list, from the list
                        // it shuts the book. Reading a step no longer dismisses
                        // on a stray tap, so this is the only way back out of
                        // one — it can't just close everything.
                        let onStepPage = openRecipeStep != nil

                        Button {
                            withAnimation(.easeInOut(duration: onStepPage ? 0.28 : 0.15)) {
                                if onStepPage {
                                    openRecipeStep = nil
                                } else {
                                    showRecipe = false
                                }
                            }
                        } label: {
                            Image(systemName: onStepPage ? "chevron.left" : "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppTheme.cream)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(AppTheme.ink.opacity(0.85)))
                        }
                        .padding(18)
                        .accessibilityLabel(onStepPage ? "Back to the recipe"
                                                       : "Close the recipe")
                    }
                }

                if showRottenAlert {
                    PrepHeldAlert(message: Rotten.blockedMessage, emoji: Rotten.emoji) {
                        withAnimation(.easeInOut(duration: 0.15)) { showRottenAlert = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }

                // Win/lose result once the game ends. Reads the synced snapshot.
                if session.snapshot.isOver {
                    EndGameResultsView(
                        didWin: session.snapshot.didWin,
                        timeRemaining: session.snapshot.timeRemaining,
                        onBackToStart: {
                            session.leave()
                            NotificationCenter.default.post(name: .returnToStart, object: nil)
                        }
                    )
                    .transition(.opacity)
                    // Above the recipe book (3). The clock can run out while
                    // the head chef has the book open, and the results screen
                    // carries the only way back to the start — underneath the
                    // book it would be unreachable.
                    .zIndex(5)
                }

                // The kitchen is held still because the host stepped away. This
                // sits above everything except the end screen: it has to cover
                // the station popups, which are ordinary SwiftUI views and are
                // otherwise perfectly happy to be tapped mid-freeze.
                // "Closed" is tested first on purpose. A closed kitchen has a
                // way out and a frozen one does not, so if the session ever
                // manages to be both at once the player must get the screen
                // with the button on it.
                if let closed = closedReason {
                    KitchenClosedOverlay(reason: closed, onDone: leaveKitchen)
                        .zIndex(4)
                } else if session.isFrozen {
                    PausedOverlay(session: session, onLeave: leaveKitchen)
                        .zIndex(4)
                }

                // Trigger: top-left, head chef only, hidden while already open.
                if session.isHeadChef && !showRecipe {
                    VStack(alignment: .leading) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { showRecipe = true }
                        } label: {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(AppTheme.ink)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(AppTheme.cream))
                                .overlay(Circle().stroke(AppTheme.ink, lineWidth: 2))
                        }
                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .onAppear { build(size: geo.size) }
            // The scene has its own clock, and SwiftUI is the only thing that
            // sees the session change. `initial: true` covers the case that
            // matters most: a chef who reconnects into a kitchen that is
            // already frozen builds the scene *after* the pause began.
            .onChange(of: session.isFrozen, initial: true) { _, frozen in
                scene?.setFrozen(frozen)
            }
            // The clock can run out with the recipe book open. The results
            // screen sits above it either way, but leaving the book open
            // behind means it is still there if the player dismisses.
            .onChange(of: session.snapshot.isOver) { _, over in
                if over {
                    showRecipe = false
                    openRecipeStep = nil
                }
            }
        }
    }

    /// Out of the kitchen and all the way back to the start screen.
    ///
    /// The host says goodbye properly rather than just going quiet — otherwise
    /// every guest freezes and waits out the full ninety seconds for someone
    /// who is already looking at the menu.
    private func leaveKitchen() {
        if session.isHost { session.closeKitchen() } else { session.leave() }
        NotificationCenter.default.post(name: .returnToStart, object: nil)
    }

    /// Why the kitchen closed, or nil while it is still open.
    ///
    /// Three endings that feel completely different to a player, so they get
    /// three different sentences — and, importantly, all three get a way out.
    /// A rejected reconnection used to have none: the player was left staring
    /// at a still kitchen with a "Reconnecting…" banner that would never clear.
    private var closedReason: String? {
        switch session.phase {
        case .hostLeft:
            return session.players.contains(where: { $0.isHost && !$0.isConnected })
                ? "The host didn't come back in time."
                : "The host closed this kitchen."
        case .rejected(let reason):
            return reason.message
        default:
            return nil
        }
    }

    private func build(size: CGSize) {
        guard scene == nil else { return }
        let made = KitchenScene(size: size)
        // Set before anything else: a chef who reconnects into an
        // already-frozen kitchen builds the scene *after* the freeze began, and
        // `onChange` can't help with a scene that didn't exist when it fired.
        made.setFrozen(session.isFrozen)
        made.scaleMode = .resizeFill
        made.session = session
        made.inventory = inventory
        made.onOpenStorage = {
            withAnimation(.easeInOut(duration: 0.2)) { showStorage = true }
        }
        made.onOpenDrawer = {
            withAnimation(.easeInOut(duration: 0.2)) { showDrawer = true }
        }
        made.onHeadsDownChanged = { down in
            withAnimation(.easeInOut(duration: 0.15)) { headsDown = down }
        }
        made.onArriveStation = { station in
            withAnimation(.easeInOut(duration: 0.15)) { activeStation = station }
        }
        made.onRottenBlocked = {
            withAnimation(.easeInOut(duration: 0.15)) { showRottenAlert = true }
        }
        made.onActionFinished = { station, foodID in
            withAnimation(.easeInOut(duration: 0.15)) {
                finishedPrep = PrepResult(station: station, foodID: foodID)
            }
        }
        scene = made
    }

}

#Preview {
    KitchenGameView(session: KitchenSession(role: .host, kitchenName: "Preview Kitchen"))
}
