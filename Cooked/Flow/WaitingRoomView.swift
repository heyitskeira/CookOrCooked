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

    private enum Layout {
        // The lobby's rock is its own drawing: wider than the setup screens'
        // slab, with vines down both sides. Exported whole as Frame 40.
        static let rockLeft = 88.0 / 874
        static let rockTop = 14.0 / 402
        static let rockWidth = 698.0 / 874
        static let rockAspect = 374.0 / 698

        static let titleTop = 94.0 / 402

        // One chef card: a portrait box with a name plate hung under it.
        static let cardsTop = 149.0 / 402
        static let cardWidth = 92.0 / 874
        static let cardGap = 15.0 / 874
        static let portraitHeight = 116.0 / 402
        static let plateTop = 119.0 / 402      // from the card's own top
        static let plateHeight = 25.0 / 402
        static let cardStroke = 1.0 / 402
        static let nameSize = 12.0 / 874
        static let animalWidth = 66.0 / 874

        /// The leaf marking which chef is you, and the word sitting on it.
        /// Centred where the design puts it, near the foot of the portrait.
        static let leafWidth = 46.0 / 874
        static let leafCentre = CGPoint(x: 18.6 / 92, y: 99.8 / 116)

        static let countLeft = 661.0 / 874
        static let countTop = 360.0 / 402
        static let countSize = 16.0 / 874
    }

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
            chefCards(w: w, h: h)
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

    // MARK: - The chefs

    private func chefCards(w: CGFloat, h: CGFloat) -> some View {
        let cardW = w * Layout.cardWidth
        let gap = w * Layout.cardGap
        // Centred rather than pinned where the two-player comp happens to put
        // them, so three and four chefs stay balanced on the rock.
        let total = cardW * CGFloat(maxPlayers) + gap * CGFloat(max(maxPlayers - 1, 0))

        return HStack(spacing: gap) {
            ForEach(0..<maxPlayers, id: \.self) { index in
                if index < session.players.count {
                    card(session.players[index], w: w, h: h)
                } else {
                    emptyCard(w: w, h: h)
                }
            }
        }
        .frame(width: total, alignment: .leading)
        .position(x: w * 0.5, y: h * (Layout.cardsTop + Layout.portraitHeight / 2)
                  + h * Layout.plateTop / 2)
    }

    private func card(_ player: Player, w: CGFloat, h: CGFloat) -> some View {
        let cardW = w * Layout.cardWidth
        let isYou = player.id == session.localPlayerID

        return VStack(spacing: h * (Layout.plateTop - Layout.portraitHeight)) {
            portrait(player, isYou: isYou, w: w, h: h)

            Text(player.name)
                .font(.system(size: w * Layout.nameSize, weight: .medium).width(.condensed))
                .foregroundStyle(AppTheme.barkDeep)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, cardW * 0.06)
                .frame(width: cardW, height: h * Layout.plateHeight)
                .background(plate)
        }
        .opacity(player.isConnected ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isYou ? "\(player.name), you" : player.name)
    }

    private func portrait(_ player: Player, isYou: Bool, w: CGFloat, h: CGFloat) -> some View {
        let cardW = w * Layout.cardWidth
        let cardH = h * Layout.portraitHeight

        return ZStack {
            // One drawing per seat, picked by the colour index the host hands
            // out on join — so everybody sees the same chef in the same seat.
            RockArt.image("ui-chef-\(player.colorIndex + 1)",
                          width: w * Layout.animalWidth,
                          aspect: 86.0 / 66)

            if isYou {
                let leafW = w * Layout.leafWidth
                ZStack {
                    RockArt.image("ui-you-leaf", width: leafW, aspect: 1)
                    Text("You")
                        .font(.system(size: w * Layout.nameSize, weight: .medium).width(.condensed))
                        .foregroundStyle(.white)
                }
                .position(x: cardW * Layout.leafCentre.x,
                          y: cardH * Layout.leafCentre.y)
            }
        }
        .frame(width: cardW, height: cardH)
        .background(plate)
    }

    private func emptyCard(w: CGFloat, h: CGFloat) -> some View {
        let cardW = w * Layout.cardWidth

        return VStack(spacing: h * (Layout.plateTop - Layout.portraitHeight)) {
            Color.clear
                .frame(width: cardW, height: h * Layout.portraitHeight)
                .background(plate)
            Color.clear
                .frame(width: cardW, height: h * Layout.plateHeight)
                .background(plate)
        }
        .opacity(0.45)
        .accessibilityLabel("Empty seat")
    }

    /// The parchment panel every card part is drawn on.
    private var plate: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(AppTheme.parchment)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppTheme.barkDeep, lineWidth: 1)
            )
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
                .background(plate)
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
            .background(plate)
            .position(x: w * 0.20, y: h * Layout.countTop)
            .accessibilityLabel("Room code \(session.roomCode.characters.joined(separator: " "))")
    }
}

#Preview("Waiting room", traits: .landscapeLeft) {
    WaitingRoomView(session: KitchenSession(role: .host))
}
