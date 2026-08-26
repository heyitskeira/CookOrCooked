//
//  HeadChefAssignmentView.swift
//  Cooked
//
//  Who is reading the recipe. One screen, two readings: the chef who was drawn
//  sees that it is them, everybody else sees who it was.
//
//  Built on the lobby's picture on purpose — same rock, same cards, same faces
//  in the same seats — so the moment reads as something happening *to* the room
//  you were just standing in, rather than a new screen arriving.
//
//  NOT YET PRESENTED ANYWHERE. `KitchenSession.headChefID` is still
//  `players.first(where: \.isHost)?.id`, so there is no drawing to show and no
//  `.selectingHeadChef` phase to hang this off. It is built against the
//  existing `isHeadChef` API so it lights up when the randomiser lands, without
//  needing rework. See the note at the foot of this file.
//
//  There is no Figma frame read for this yet — the design's two frames
//  (838:709, 850:802) were behind a rate limit — so the numbers below are the
//  lobby's, adjusted. Everything worth nudging is in `Layout`.
//

import SwiftUI

struct HeadChefAssignmentView: View {

    @ObservedObject var session: KitchenSession

    /// Lets a preview show either reading without a live room. Matches the
    /// `headChefOverride` that `RecipeBookView` already takes.
    var headChefOverride: String?

    /// Runs when the ceremony has finished and the room should move on.
    var onDone: () -> Void = {}

    @State private var spotlight: Int?
    @State private var settled = false

    private var headChefID: String? { headChefOverride ?? session.headChefID }

    // MARK: - Layout

    private enum Layout {
        /// How long the highlight travels before it settles, and how fast it
        /// steps between cards.
        static let cycleStep = 0.14
        static let cycleDuration = 1.8
        /// How long the answer sits on screen before the room moves on.
        static let linger = 3.0
    }

    // MARK: - Body

    var body: some View {
        HeadChefStage(players: session.players,
                      seats: max(session.maxPlayers, session.players.count),
                      localPlayerID: session.localPlayerID,
                      roomCode: session.roomCode.digits,
                      headChefID: headChefID,
                      settled: settled,
                      spotlight: spotlight)
            .task { await runCeremony() }
    }

    // MARK: - The draw

    /// Runs the highlight around the room, stops on the chef who was drawn, and
    /// lets the answer sit before moving on.
    ///
    /// The result is already decided before this runs — the highlight is only
    /// how it is announced. Deciding it here would mean each phone drawing its
    /// own head chef, which is exactly the bug the host-authoritative rule
    /// exists to prevent.
    private func runCeremony() async {
        let seats = session.players.count
        guard seats > 1 else {
            settled = true
            return
        }

        let steps = Int(Layout.cycleDuration / Layout.cycleStep)
        for step in 0..<steps {
            spotlight = step % seats
            try? await Task.sleep(for: .seconds(Layout.cycleStep))
            if Task.isCancelled { return }
        }

        spotlight = nil
        withAnimation { settled = true }

        try? await Task.sleep(for: .seconds(Layout.linger))
        if Task.isCancelled { return }
        onDone()
    }
}

// MARK: - The picture
//
// Split from the ceremony so it can be previewed with a room full of chefs:
// `KitchenSession.players` is private(set), which is right, so the only way to
// see four cards in the canvas is to hand them in.

private struct HeadChefStage: View {
    let players: [Player]
    let seats: Int
    let localPlayerID: String
    let roomCode: String
    let headChefID: String?
    let settled: Bool
    let spotlight: Int?

    private var headChef: Player? {
        guard let headChefID else { return nil }
        return players.first { $0.id == headChefID }
    }

    var body: some View {
        ForestRockScreen(
            title: "HEAD CHEF",
            subtitle: subtitle,
            rockAsset: WaitingRoomLayout.rockAsset,
            rockLeft: WaitingRoomLayout.rockLeft,
            rockWidth: WaitingRoomLayout.rockWidth,
            rockAspect: WaitingRoomLayout.rockAspect,
            rockTop: WaitingRoomLayout.rockTop,
            titleTop: 94.0 / 402,
            subtitleTop: 330.0 / 402,
            subtitleColor: AppTheme.parchment,
            showNext: false,
            onBack: {},
            onNext: {}
        ) { w, h in
            ChefCardsRow(players: players,
                         seats: seats,
                         localPlayerID: localPlayerID,
                         roomCode: roomCode,
                         // Nothing is marked until the highlight stops moving,
                         // or the answer would be on screen before the ceremony
                         // that is supposed to reveal it.
                         headChefID: settled ? headChefID : nil,
                         spotlight: spotlight,
                         w: w, h: h)
        }
    }

    private var subtitle: String {
        guard settled else { return "Drawing lots…" }
        guard let headChef else { return "Waiting for the kitchen…" }
        return headChef.id == localPlayerID
            ? "You're reading the recipe. Call the steps out loud!"
            : "\(headChef.name) is reading the recipe. Listen for the steps!"
    }
}

// MARK: - What this still needs
//
// The randomiser lives on `agung/head-chef-randomizer` and is a small port onto
// main's briefing flow, not a rival design: main already has `headChefID`,
// `isHeadChef`, and a `RecipeBookView` that renders head-chef and closed-book
// states. Only the drawing itself is missing.
//
// Three things have to be true before this screen can be hung off a phase, and
// all three live in `KitchenSession.swift`, which is Brio's:
//
//  1. `headChefID` becomes a published id the host draws and broadcasts,
//     instead of `players.first(where: \.isHost)?.id`. The property is already
//     written as one computed value specifically so its body can be replaced.
//
//  2. **Only chefs who were in the room when the draw happened are eligible.**
//     Somebody admitted mid-briefing joins as an ordinary chef and cannot be
//     picked — the draw has already happened, and re-running it would move the
//     recipe out from under whoever is reading it.
//
//  3. The late-joiner catch-up switch needs a `.selectingHeadChef` case, or a
//     guest admitted during the ceremony hangs in the lobby; and
//     `beginCooking()` guards `isHost`, so a guest head chef's START would
//     silently do nothing.

private let previewChefs = [
    Player(id: "me", name: "Chef 83", isHost: true, isConnected: true, colorIndex: 0),
    Player(id: "b", name: "Bambi", isHost: false, isConnected: true, colorIndex: 1),
    Player(id: "r", name: "RANIA!!!", isHost: false, isConnected: true, colorIndex: 2),
    Player(id: "k", name: "Keirararara", isHost: false, isConnected: true, colorIndex: 3)
]

#Preview("Drawing lots", traits: .landscapeLeft) {
    HeadChefStage(players: previewChefs, seats: 4, localPlayerID: "me",
                  roomCode: "6348", headChefID: "b", settled: false, spotlight: 2)
}

#Preview("You are the head chef", traits: .landscapeLeft) {
    HeadChefStage(players: previewChefs, seats: 4, localPlayerID: "me",
                  roomCode: "6348", headChefID: "me", settled: true, spotlight: nil)
}

#Preview("Someone else is", traits: .landscapeLeft) {
    HeadChefStage(players: previewChefs, seats: 4, localPlayerID: "me",
                  roomCode: "6348", headChefID: "b", settled: true, spotlight: nil)
}
