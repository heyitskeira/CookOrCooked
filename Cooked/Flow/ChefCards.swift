//
//  ChefCards.swift
//  Cooked
//
//  The row of chef cards, and the parchment panel everything on the rock is
//  drawn on. Shared by the lobby and the head-chef ceremony, which are the same
//  picture with a different thing being announced over it.
//
//  Layout read off Figma frame 838:549 (874 x 402) — see Tools/figma.py.
//

import SwiftUI

/// The parchment panel everything on the rock is drawn on — card portraits,
/// name plates, the Ready control, the room code.
struct RockPlate: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(AppTheme.parchment)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppTheme.barkDeep, lineWidth: 1)
            )
    }
}

/// Shared by the screen and the card row it draws — one copy of the design's
/// numbers, read off Figma frame 838:549 (874 x 402).
enum WaitingRoomLayout {
        static let titleTop = 94.0 / 402

        // One chef card: a portrait box with a name plate hung under it.
        static let cardsTop = 149.0 / 402
        static let cardWidth = 92.0 / 874
        static let cardGap = 15.0 / 874
        static let cardHeight = 144.0 / 402
        static let portraitHeight = 116.0 / 402
        static let plateHeight = 25.0 / 402
        /// 144 total, less the 116 portrait and the 25 plate.
        static let cardSpacing = 3.0 / 402
        static let nameSize = 12.0 / 874
        // The drawing's own box inside the plate. Each animal is fitted to
        // this and stood on its bottom edge, whatever its own proportions.
        static let animalWidth = 66.0 / 874
        static let animalHeight = 86.0 / 402

        /// The leaf marking which chef is you, and the word sitting on it.
        /// Centred where the design puts it, near the foot of the portrait.
        static let leafWidth = 46.0 / 874
        static let leafCentre = CGPoint(x: 18.6 / 92, y: 99.8 / 116)

        // The lobby's rock: slab and vines in one drawing, 685 x 394pt.
        // Figma's Frame 40 sits centred on the screen, so this does too, which
        // keeps the cards and lettering above it where the design puts them.
        static let rockAsset = "ui-rock-slab"
        static let rockWidth = 685.0 / 874
        static let rockAspect = 394.0 / 685
        static let rockLeft = ((874.0 - 685.0) / 2) / 874
        static let rockTop = ((402.0 - 394.0) / 2) / 402

        static let countLeft = 661.0 / 874
        static let countTop = 360.0 / 402
        static let countSize = 16.0 / 874
    }

// MARK: - The chefs
//
// Split out of the screen so it can be previewed with a room full of chefs.
// `KitchenSession.players` is private(set), which is right — nothing outside
// the session should be able to invent a roster — but it does mean the only
// way to see four cards in the canvas is to hand them in directly.

struct ChefCardsRow: View {
    let players: [Player]
    let seats: Int
    let localPlayerID: String
    /// Seeds which animal each seat wears — see `ChefCast`.
    let roomCode: String
    /// Marks one card with the head-chef badge. Nil in the lobby, where nobody
    /// has been picked yet.
    var headChefID: String? = nil
    /// The seat the ceremony is currently lighting up as it cycles. Nil once it
    /// has settled, or when there is no ceremony.
    var spotlight: Int? = nil
    let w: CGFloat
    let h: CGFloat

    private typealias Layout = WaitingRoomLayout

    var body: some View {
        let cardH = h * Layout.cardHeight
        let gap = w * Layout.cardGap
        let count = max(seats, players.count, 1)

        // `.top` matters. Left to centre itself, a row of cards whose contents
        // differ in height staggers, which is exactly what a mix of real
        // drawings and empty seats produces.
        return HStack(alignment: .top, spacing: gap) {
            ForEach(0..<count, id: \.self) { index in
                if index < players.count {
                    card(players[index], seat: index)
                } else {
                    emptyCard
                }
            }
        }
        .frame(height: cardH, alignment: .top)
        // `.position` centres the row on this point and takes the whole screen
        // to do it, so nothing else may size the row after this line.
        .position(x: w * 0.5, y: h * Layout.cardsTop + cardH / 2)
    }

    private func card(_ player: Player, seat: Int) -> some View {
        let isYou = player.id == localPlayerID
        let isHeadChef = player.id == headChefID
        let isLit = spotlight == seat

        return VStack(spacing: h * Layout.cardSpacing) {
            portrait(player, isYou: isYou)
            namePlate(player.name)
        }
        .frame(width: w * Layout.cardWidth, height: h * Layout.cardHeight, alignment: .top)
        .opacity(player.isConnected ? 1 : 0.45)
        // The chosen card lifts; the cards the ceremony is passing over only
        // brighten, so the moment it settles reads as an arrival rather than
        // one more flicker.
        .scaleEffect(isHeadChef ? 1.12 : (isLit ? 1.05 : 1))
        .overlay(alignment: .top) {
            if isHeadChef { headChefBadge }
        }
        .shadow(color: AppTheme.stone.opacity(isHeadChef ? 0.45 : 0),
                radius: h * 0.02, x: 0, y: h * 0.012)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHeadChef)
        .animation(.easeOut(duration: 0.12), value: isLit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label(for: player, isYou: isYou, isHeadChef: isHeadChef))
    }

    private func label(for player: Player, isYou: Bool, isHeadChef: Bool) -> String {
        switch (isYou, isHeadChef) {
        case (true, true):   return "\(player.name), you, head chef"
        case (true, false):  return "\(player.name), you"
        case (false, true):  return "\(player.name), head chef"
        case (false, false): return player.name
        }
    }

    private var headChefBadge: some View {
        Text("HEAD CHEF")
            .font(.system(size: w * Layout.nameSize * 0.85, weight: .heavy).width(.condensed))
            .foregroundStyle(AppTheme.parchment)
            .padding(.horizontal, w * 0.008)
            .padding(.vertical, h * 0.006)
            .background(
                Capsule().fill(AppTheme.barkDeep)
            )
            .offset(y: -h * 0.035)
            .transition(.scale.combined(with: .opacity))
    }

    private func portrait(_ player: Player, isYou: Bool) -> some View {
        let cardW = w * Layout.cardWidth
        let cardH = h * Layout.portraitHeight

        return RockArt.fitted(ChefCast.asset(seat: player.colorIndex, roomCode: roomCode),
                              width: w * Layout.animalWidth,
                              height: h * Layout.animalHeight)
            // Sized first, then centred in the plate, so the drawing's own
            // proportions cannot push the plate around.
            .frame(width: cardW, height: cardH)
            .background(RockPlate())
            .overlay {
                if isYou { youLeaf(cardW: cardW, cardH: cardH) }
            }
    }

    /// The leaf marking your own chef. In an overlay of the finished plate, so
    /// it is positioned against the card's real size rather than against
    /// whatever the drawing inside happens to measure.
    private func youLeaf(cardW: CGFloat, cardH: CGFloat) -> some View {
        let leafW = w * Layout.leafWidth

        return ZStack {
            RockArt.image("ui-you-leaf", width: leafW, aspect: 1)
            Text("You")
                .font(.system(size: w * Layout.nameSize, weight: .heavy).width(.condensed))
                .foregroundStyle(.white)
        }
        .frame(width: leafW, height: leafW)
        .position(x: cardW * Layout.leafCentre.x, y: cardH * Layout.leafCentre.y)
    }

    private func namePlate(_ name: String) -> some View {
        let cardW = w * Layout.cardWidth

        return Text(name)
            .font(.system(size: w * Layout.nameSize, weight: .medium).width(.condensed))
            .foregroundStyle(AppTheme.barkDeep)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, cardW * 0.06)
            .frame(width: cardW, height: h * Layout.plateHeight)
            .background(RockPlate())
    }

    private var emptyCard: some View {
        let cardW = w * Layout.cardWidth

        return VStack(spacing: h * Layout.cardSpacing) {
            Color.clear
                .frame(width: cardW, height: h * Layout.portraitHeight)
                .background(RockPlate())
            Color.clear
                .frame(width: cardW, height: h * Layout.plateHeight)
                .background(RockPlate())
        }
        .frame(width: cardW, height: h * Layout.cardHeight, alignment: .top)
        .opacity(0.4)
        .accessibilityLabel("Empty seat")
    }

}


#Preview("Chef cards — 2 of 4", traits: .landscapeLeft) {
    ChefCardsPreview(players: [
        Player(id: "me", name: "Chef 83", isHost: true, isConnected: true, colorIndex: 0),
        Player(id: "b", name: "Bambi", isHost: false, isConnected: true, colorIndex: 1)
    ], seats: 4)
}

#Preview("Chef cards — 4 of 4", traits: .landscapeLeft) {
    ChefCardsPreview(players: [
        Player(id: "me", name: "Chef 83", isHost: true, isConnected: true, colorIndex: 0),
        Player(id: "b", name: "Bambi", isHost: false, isConnected: true, colorIndex: 1),
        Player(id: "r", name: "RANIA!!!", isHost: false, isConnected: true, colorIndex: 2),
        Player(id: "k", name: "Keirararara", isHost: false, isConnected: false, colorIndex: 3)
    ], seats: 4)
}

/// Draws the row over the real backdrop so spacing can be judged against the
/// rock rather than against a blank canvas.
private struct ChefCardsPreview: View {
    let players: [Player]
    let seats: Int
    var roomCode = "6348"

    /// Derived, not typed — the same way the real screen gets it, so the
    /// preview cannot drift from the thing it is previewing.
    private var banner: String {
        KitchenTitle.banner(players.first(where: \.isHost)?.name ?? "")
    }

    var body: some View {
        ForestRockScreen(
            title: banner,
            rockAsset: WaitingRoomLayout.rockAsset,
            rockLeft: WaitingRoomLayout.rockLeft,
            rockWidth: WaitingRoomLayout.rockWidth,
            rockAspect: WaitingRoomLayout.rockAspect,
            rockTop: WaitingRoomLayout.rockTop,
            titleTop: WaitingRoomLayout.titleTop,
            showNext: false,
            onBack: {},
            onNext: {}
        ) { w, h in
            ChefCardsRow(players: players, seats: seats,
                         localPlayerID: "me", roomCode: roomCode,
                         w: w, h: h)
        }
    }
}
