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
                    RecipeSpreadView(session: session)
                        .padding(20)
                        .transition(.opacity)
                        .zIndex(3)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { showRecipe = false }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(AppTheme.cream)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(AppTheme.ink.opacity(0.85)))
                            }
                            .padding(18)
                        }
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
                    .zIndex(2)
                }

                if session.phase == .hostLeft {
                    hostLeftBanner
                } else if let player = session.localPlayer, !player.isConnected {
                    reconnectingBanner
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
        }
    }

    private func build(size: CGSize) {
        guard scene == nil else { return }
        let made = KitchenScene(size: size)
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
        made.onActionFinished = { station, foodID in
            withAnimation(.easeInOut(duration: 0.15)) {
                finishedPrep = PrepResult(station: station, foodID: foodID)
            }
        }
        scene = made
    }

    private var hostLeftBanner: some View {
        banner("The host left — this kitchen is closed")
    }

    private var reconnectingBanner: some View {
        banner("Reconnecting…")
    }

    private func banner(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.cream)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(AppTheme.ink.opacity(0.85)))
                .padding(.bottom, 28)
        }
    }
}

#Preview {
    KitchenGameView(session: KitchenSession(role: .host, kitchenName: "Preview Kitchen"))
}
