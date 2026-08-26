//
//  NumberOfPlayersView.swift
//  Cooked
//
//  Created by Agung Ananda on 12/08/26.
//
//  The host picks how many chefs are cooking. Same forest and rock as the chef
//  name screen — see `ForestRockScreen` — with three tiles in the middle
//  instead of a text field.
//

import SwiftUI

struct NumberOfPlayersView: View {
    @Environment(\.dismiss) private var dismiss

    // Owned here so it survives the transition into the waiting room. The
    // session is inert until `startHosting()` — creating it advertises nothing.
    @StateObject private var session = KitchenSession(role: .host)

    @State private var selected: Int?
    @State private var showWaitingRoom = false

    private let options = [2, 3, 4]

    /// Lets a preview show the chosen state without tapping anything.
    init(preselected: Int? = nil) {
        _selected = State(initialValue: preselected)
    }

    // MARK: - Layout

    // Straight off the Figma frame (874 x 402). The three tiles sit at x 277,
    // 387 and 496.8, each 96.2 x 95, so the gap between them is 13.7.
    private enum Layout {
        static let titleTop = 127.0 / 402
        static let subtitleTop = 276.0 / 402

        static let tileWidth = 96.2 / 874
        static let tileAspect = 95.0 / 96.2
        static let tileGap = 13.7 / 874
        static let rowCentre = CGPoint(x: (277.0 + 316.0 / 2) / 874,
                                       y: (167.0 + 95.0 / 2) / 402)

        /// The counts are lettered far larger than anything else on the rock.
        static let numberSize = 78.96 / 874
        static let numberStroke = 1.72 / 78.96
    }

    // MARK: - Body

    var body: some View {
        ForestRockScreen(
            title: "NO. OF PLAYERS",
            subtitle: "How many people will be playing the game?",
            titleTop: Layout.titleTop,
            subtitleTop: Layout.subtitleTop,
            nextEnabled: selected != nil,
            onBack: { dismiss() },
            onNext: start
        ) { w, h in
            tileRow(w: w, h: h)
        }
        .fullScreenCover(isPresented: $showWaitingRoom) {
            WaitingRoomView(session: session)
        }
    }

    private func tileRow(w: CGFloat, h: CGFloat) -> some View {
        HStack(spacing: w * Layout.tileGap) {
            ForEach(options, id: \.self) { count in
                tile(count: count, w: w)
            }
        }
        .position(x: w * Layout.rowCentre.x, y: h * Layout.rowCentre.y)
    }

    private func tile(count: Int, w: CGFloat) -> some View {
        let tileW = w * Layout.tileWidth
        let isSelected = selected == count
        let numberSize = w * Layout.numberSize
        let numberFont = UIFont.systemFont(ofSize: numberSize, weight: .heavy, width: .condensed)

        return Button {
            selected = count
        } label: {
            RockArt.image(isSelected ? "ui-number-of-players-active"
                                     : "ui-number-of-players-inactive",
                          width: tileW,
                          aspect: Layout.tileAspect)
                .overlay {
                    // The chosen tile is cream, so its number is the dark brown
                    // that reads on it; the others invert that.
                    ArcText("\(count)",
                            font: numberFont,
                            fill: isSelected ? AppTheme.bark : AppTheme.parchment,
                            stroke: AppTheme.barkDeep,
                            strokeWidth: numberSize * Layout.numberStroke,
                            bend: .zero,
                            shadowOpacity: 0)
                        .allowsHitTesting(false)
                }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .accessibilityLabel("\(count) players")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Actions

    private func start() {
        guard let selected else { return }
        // The kitchen takes the host's own chef name — see `KitchenTitle`.
        session.configure(kitchenName: PlayerIdentityStore.current.name,
                          maxPlayers: selected)
        showWaitingRoom = true
    }
}

#Preview("Nothing picked — NEXT dimmed", traits: .landscapeLeft) {
    NumberOfPlayersView()
}

#Preview("Two chefs picked", traits: .landscapeLeft) {
    NumberOfPlayersView(preselected: 2)
}

#Preview("Four chefs picked", traits: .landscapeLeft) {
    NumberOfPlayersView(preselected: 4)
}
