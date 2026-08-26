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

    let kitchenName: String

    // Owned here so it survives the transition into the waiting room. The
    // session is inert until `startHosting()` — creating it advertises nothing.
    @StateObject private var session = KitchenSession(role: .host)

    @State private var selected: Int?
    @State private var showWaitingRoom = false

    private let options = [2, 3, 4]

    /// Lets a preview show the chosen state without tapping anything.
    init(kitchenName: String, preselected: Int? = nil) {
        self.kitchenName = kitchenName
        _selected = State(initialValue: preselected)
    }

    // MARK: - Layout

    private enum Layout {
        /// The tiles export at 100 x 98pt, so they are placed at their drawn
        /// size rather than stretched to a guess.
        static let tileWidth = 100.0 / 874
        static let tileAspect = 294.0 / 299
        static let tileGap = 11.0 / 874
        static let rowCentre = CGPoint(x: 0.492, y: 0.520)
        static let numberSize = 38.0 / 874

        /// Lower than the name screen's, because the tiles are taller than the
        /// name field and would otherwise crowd the line.
        static let subtitleTop = 0.685
    }

    // MARK: - Body

    var body: some View {
        ForestRockScreen(
            title: "NO. OF PLAYERS",
            subtitle: "How many people will be playing the game?",
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
                            fill: isSelected ? AppTheme.bark : AppTheme.sand,
                            stroke: AppTheme.barkDeep,
                            strokeWidth: numberSize * RockLayout.strokeRatio,
                            bend: .zero,
                            shadowOpacity: 0.25)
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
        session.configure(kitchenName: kitchenName, maxPlayers: selected)
        showWaitingRoom = true
    }
}

#Preview("Nothing picked — NEXT dimmed", traits: .landscapeLeft) {
    NumberOfPlayersView(kitchenName: "Test Kitchen")
}

#Preview("Two chefs picked", traits: .landscapeLeft) {
    NumberOfPlayersView(kitchenName: "Test Kitchen", preselected: 2)
}

#Preview("Four chefs picked", traits: .landscapeLeft) {
    NumberOfPlayersView(kitchenName: "Test Kitchen", preselected: 4)
}
