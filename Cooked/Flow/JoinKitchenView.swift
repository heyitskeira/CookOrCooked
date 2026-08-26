//
//  JoinKitchenView.swift
//  Cooked
//
//  "Active kitchens" — browse the local Wi-Fi for hosted kitchens, pick one,
//  then prove you're in the room by typing the code off the host's screen.
//
//  The list shows every kitchen the radio can find. It deliberately does NOT
//  filter by distance: ranging each advertiser before drawing its row would
//  need one UWB session per kitchen, and only one can run at a time. The
//  distance check happens after you tap JOIN.
//
//  The forest, rock, title and signposts come from `ForestRockScreen`; only the
//  list in the middle is this screen's. Layout numbers below are read straight
//  off the Figma frame (874 x 402) — see Tools/figma.py.
//

import SwiftUI

struct JoinKitchenView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var session = KitchenSession(role: .guest)
    @State private var selected: DiscoveredKitchen?
    @State private var pendingKitchen: DiscoveredKitchen?
    @State private var showLobby = false

    // MARK: - Layout

    private enum Layout {
        static let titleTop = 107.0 / 402

        // "Frame 12" — the window the rows scroll inside. The design draws five
        // rows in a box only tall enough for four and a bit, which is what
        // makes it read as a list rather than a fixed set of buttons.
        static let listLeft = 306.0 / 874
        static let listTop = 144.0 / 402
        static let listWidth = 258.0 / 874
        static let listHeight = 175.0 / 402

        // Rows sit 41 apart and stand 31.9 tall, so 9.1 of that is the gap.
        static let rowWidth = 250.7 / 874
        static let rowAspect = 31.9 / 250.7
        static let rowGap = 9.1 / 402
        static let rowTextSize = 18.23 / 874
        static let rowTextInset = 12.8 / 874
    }

    // MARK: - Body

    var body: some View {
        ForestRockScreen(
            title: "ACTIVE KITCHENS",
            titleTop: Layout.titleTop,
            nextAsset: "ui-join-button",
            nextLabel: "Join",
            // The JOIN signpost exports whole, post and all, unlike the trimmed
            // NEXT one — it runs off the bottom of the screen by design.
            nextAspect: 201.0 / 160.0,
            nextEnabled: selected != nil,
            onBack: {
                session.leave()
                dismiss()
            },
            onNext: {
                guard let selected else { return }
                pendingKitchen = selected
            }
        ) { w, h in
            listWindow(w: w, h: h)
        }
        .onAppear { session.startBrowsing() }
        // This screen owns the session, so it also owns shutting it down. On
        // the game-over path the cover stack collapses from the outside — the
        // waiting room dismisses, which restarts the browser below, and then
        // this whole view disappears a frame later. Without this the fresh
        // NWBrowser would keep running for the rest of the launch.
        .onDisappear { session.leave() }
        .fullScreenCover(item: $pendingKitchen) { kitchen in
            KitchenCodeView(kitchenName: kitchen.name) { code in
                pendingKitchen = nil
                session.join(kitchen: kitchen, code: code)
            }
        }
        .onChange(of: session.phase) { _, phase in
            // Only ever raise the cover from here. A constant binding would
            // present fine but leave the lobby's back button unable to close.
            // .briefing and .playing both mean "admitted to a kitchen that has
            // already left the lobby" — the waiting room passes them straight
            // through to the recipe book or the game.
            if phase == .lobby || phase == .briefing || phase == .playing { showLobby = true }
        }
        .fullScreenCover(isPresented: $showLobby) {
            WaitingRoomView(session: session)
        }
        // `onAppear` fires once, so backing out of a kitchen used to leave this
        // screen showing a list of rooms whose endpoints the transport had
        // already thrown away — every one of them untappable, with nothing to
        // refresh them. Coming back from the lobby starts the search again.
        .onChange(of: showLobby) { _, isShowing in
            if !isShowing {
                selected = nil
                session.startBrowsing()
            }
        }
        // A kitchen that goes off the air while highlighted would otherwise
        // leave JOIN live against a room that is no longer there.
        .onChange(of: session.discovered) { _, kitchens in
            if let selected, !kitchens.contains(where: { $0.id == selected.id }) {
                self.selected = nil
            }
        }
    }

    // MARK: - The list, and what stands in for it

    private func listWindow(w: CGFloat, h: CGFloat) -> some View {
        Group {
            switch session.phase {
            case .verifying(let status):
                message(status, w: w)
            case .rejected(let reason):
                message(reason.message, w: w, retry: true)
            case .hostLeft:
                message("That kitchen has closed", w: w, retry: true)
            default:
                if session.discovered.isEmpty {
                    message("Looking for kitchens on your Wi-Fi…", w: w)
                } else {
                    rows(w: w, h: h)
                }
            }
        }
        .frame(width: w * Layout.listWidth, height: h * Layout.listHeight)
        .position(x: w * (Layout.listLeft + Layout.listWidth / 2),
                  y: h * (Layout.listTop + Layout.listHeight / 2))
    }

    private func rows(w: CGFloat, h: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: h * Layout.rowGap) {
                ForEach(session.discovered) { kitchen in
                    row(kitchen, w: w)
                }
            }
        }
        // The rows are wider than the window's inner edge by a couple of
        // points in the design, so the window does not clip them.
        .scrollClipDisabled(false)
    }

    private func row(_ kitchen: DiscoveredKitchen, w: CGFloat) -> some View {
        let isSelected = selected?.id == kitchen.id
        let rowW = w * Layout.rowWidth

        return Button {
            selected = kitchen
        } label: {
            RockArt.image(isSelected ? "ui-kitchen-list-choosen"
                                     : "ui-kitchen-list-unchoosen",
                          width: rowW,
                          aspect: Layout.rowAspect)
                .overlay(alignment: .leading) {
                    // The chosen row is the dark one, so its name flips to the
                    // light lettering to stay readable on it.
                    Text(kitchen.name)
                        .font(.system(size: w * Layout.rowTextSize, weight: .medium).width(.condensed))
                        .foregroundStyle(isSelected ? AppTheme.parchment : AppTheme.barkDeep)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, w * Layout.rowTextInset)
                        .padding(.trailing, w * Layout.rowTextInset * 0.5)
                        .allowsHitTesting(false)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kitchen.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Searching, verifying, and the failure states all read as one line of
    /// lettering in the same window the rows use.
    private func message(_ text: String, w: CGFloat, retry: Bool = false) -> some View {
        VStack(spacing: w * 0.012) {
            Text(text)
                .font(.system(size: w * Layout.rowTextSize, weight: .medium).width(.condensed))
                .foregroundStyle(AppTheme.barkDeep)
                .multilineTextAlignment(.center)

            if retry {
                Button("Try again") { session.startBrowsing() }
                    .font(.system(size: w * Layout.rowTextSize, weight: .heavy).width(.condensed))
                    .foregroundStyle(AppTheme.bark)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

#Preview("Active kitchens", traits: .landscapeLeft) {
    JoinKitchenView()
}
