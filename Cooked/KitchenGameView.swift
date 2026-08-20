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
                    .zIndex(2)
                }

                if session.phase == .hostLeft {
                    hostLeftBanner
                } else if let player = session.localPlayer, !player.isConnected {
                    reconnectingBanner
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
