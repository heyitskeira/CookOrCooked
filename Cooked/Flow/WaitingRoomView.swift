//
//  WaitingRoomView.swift
//  Cooked
//
//  Created by Agung Ananda on 12/08/26.
//
//  The lobby: everybody who has joined, shown as a row of chef cards on the
//  wide vine-draped rock, with your own card marked by a leaf.
//
//  The host's screen shows the room code. That is not decoration — it is the
//  same-room check. To type those four digits a guest has to be able to see
//  this screen, which no radio can prove.
//
//  Layout read off Figma frame 838:549 (874 x 402) — see Tools/figma.py.
//

import SwiftUI

struct WaitingRoomView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var session: KitchenSession
    /// Covers the whole game: recipe book first, then the kitchen.
    @State private var showGame = false
    /// Guards the dismiss-on-idle rule below. Without it the view would tear
    /// itself down the instant it appears, because `.idle` is where every
    /// session starts.
    @State private var didLeaveLobby = false

    private var maxPlayers: Int { max(session.maxPlayers, session.players.count) }

    // MARK: - Layout

    private typealias Layout = WaitingRoomLayout

    // MARK: - Body

    var body: some View {
        ForestRockScreen(
            title: session.kitchenName.uppercased(),
            rockAsset: "ui-waiting-rock",
            rockLeft: Layout.rockLeft,
            rockWidth: Layout.rockWidth,
            rockAspect: Layout.rockAspect,
            rockTop: Layout.rockTop,
            titleTop: Layout.titleTop,
            // No signpost here. Every chef presses Ready — the host does not
            // start the room — and there is no READY sign drawn in the design,
            // so the control is a lettered plate like the room code beside it
            // rather than the NEXT sign wearing the wrong word.
            showNext: false,
            onBack: {
                // The host leaving is the end of the kitchen, and the guests are
                // told so explicitly — otherwise they freeze and wait ninety
                // seconds for a host who is already back on the menu.
                if session.isHost { session.closeKitchen() } else { session.leave() }
                dismiss()
            },
            onNext: {}
        ) { w, h in
            ChefCardsRow(players: session.players,
                         seats: maxPlayers,
                         localPlayerID: session.localPlayerID,
                         roomCode: session.roomCode.digits,
                         w: w, h: h)
            statusLine(w: w, h: h)
            readyPlate(w: w, h: h)
            if session.isHost {
                roomCode(w: w, h: h)
            }
        }
        .onAppear {
            if session.isHost { session.startHosting() }
        }
        // `initial: true` matters: a guest admitted to a briefing or a game
        // already in progress is caught up during admission, so the phase has
        // already moved on before this view appears and a change-only handler
        // would strand them in the lobby forever.
        .onChange(of: session.phase, initial: true) { _, phase in
            switch phase {
            case .briefing, .playing:
                didLeaveLobby = true
                showGame = true
            case .idle where didLeaveLobby:
                // Backing out of the recipe book leaves the kitchen entirely,
                // so the lobby underneath must not linger.
                showGame = false
                dismiss()
            case .hostLeft where !didLeaveLobby:
                // The kitchen closed while we were still in the lobby. There is
                // no game cover to show the closed screen, so bow out here.
                session.leave()
                dismiss()
            default:
                break
            }
        }
        .fullScreenCover(isPresented: $showGame) {
            GameFlowView(session: session)
                .ignoresSafeArea()
        }
    }

    // MARK: - The lines along the bottom

    private func statusLine(w: CGFloat, h: CGFloat) -> some View {
        Text(status)
            .font(.system(size: w * Layout.countSize, weight: .medium).width(.condensed))
            .foregroundStyle(AppTheme.parchment)
            .lineLimit(1)
            .position(x: w * Layout.countLeft, y: h * Layout.countTop)
    }

    /// Says what the room is actually waiting on, which is nearly always more
    /// useful than a bare headcount.
    private var status: String {
        if let seconds = session.startSecondsLeft {
            return "Starting in \(seconds)…"
        }
        if session.connectedCount < 2 {
            return "Waiting for at least one more chef"
        }
        let notReady = session.players.filter { $0.isConnected && !$0.isReady }
        if notReady.isEmpty { return "Everyone's ready" }
        if notReady.count == 1, let only = notReady.first {
            return only.id == session.localPlayerID
                ? "Everyone else is ready"
                : "Waiting on \(only.name)"
        }
        return "\(session.connectedCount) out of \(maxPlayers) chefs have joined!"
    }

    /// Every chef says when they are ready and the room starts itself once it
    /// is unanimous, so this is the only control in the lobby.
    ///
    /// It stays on screen through the countdown on purpose: three seconds
    /// exists so somebody can change their mind, and hiding the one control
    /// that would let them makes it a decorative delay instead of a real one.
    private func readyPlate(w: CGFloat, h: CGFloat) -> some View {
        let enabled = session.connectedCount >= 2

        return Button {
            session.setReady(!session.isReady)
        } label: {
            Text(session.isReady ? "WAITING" : "READY")
                .font(.system(size: w * Layout.countSize * 1.4, weight: .heavy).width(.condensed))
                .foregroundStyle(session.isReady ? AppTheme.bark : AppTheme.barkDeep)
                .padding(.horizontal, w * 0.018)
                .padding(.vertical, h * 0.014)
                .background(RockPlate())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.5)
        .disabled(!enabled)
        .position(x: w * 0.82, y: h * 0.78)
        .accessibilityLabel(session.isReady ? "Ready. Tap to wait" : "I am ready")
    }

    /// The four digits a guest has to read off this screen to get in.
    private func roomCode(w: CGFloat, h: CGFloat) -> some View {
        Text(session.roomCode.characters.joined(separator: " "))
            .font(.system(size: w * Layout.countSize * 1.4, weight: .heavy).width(.condensed))
            .foregroundStyle(AppTheme.barkDeep)
            .padding(.horizontal, w * 0.012)
            .padding(.vertical, h * 0.012)
            .background(RockPlate())
            .position(x: w * 0.20, y: h * Layout.countTop)
            .accessibilityLabel("Room code \(session.roomCode.characters.joined(separator: " "))")
    }
}

#Preview("Waiting room — empty session", traits: .landscapeLeft) {
    WaitingRoomView(session: KitchenSession(role: .host))
}

