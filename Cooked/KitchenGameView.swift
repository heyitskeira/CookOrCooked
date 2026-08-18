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
    @State private var showStorage = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let scene {
                    SpriteView(scene: scene)
                        .ignoresSafeArea()
                } else {
                    AppTheme.background
                }

                // Inventory indicator, pinned bottom-centre over the kitchen.
                VStack {
                    Spacer()
                    InventoryBar(inventory: inventory)
                        .padding(.bottom, 20)
                }

                if showStorage {
                    StorageView(inventory: inventory, onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) { showStorage = false }
                    })
                    .transition(.opacity)
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
