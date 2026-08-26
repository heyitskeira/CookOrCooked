//
//  StationPage.swift
//  Cooked
//
//  Which stations have been rebuilt as a full-screen illustrated page, and
//  which page that is.
//
//  Both callers — the kitchen itself and the dev menu — used to name
//  `ChoppingStationView` directly, which meant the second station needed the
//  same `if` written twice in two files. They ask here instead: `exists(for:)`
//  decides whether a station gets a page at all (everything else still uses
//  `StationPopupView` over the map plus its SpriteKit overlay), and this view
//  is that page. Rebuilding the next station is a case in one switch.
//

import SwiftUI

struct StationPage: View {

    let station: StationID
    @ObservedObject var session: KitchenSession
    @ObservedObject var inventory: PlayerInventory
    var onClose: () -> Void

    /// Has this station been rebuilt against final art yet?
    ///
    /// `nonisolated` because it answers a question about the recipe, not about
    /// this view: the kitchen asks it from inside a `Binding`'s getter, which
    /// is a plain synchronous closure and would otherwise be reaching into
    /// main-actor state that `View` conformance implies.
    nonisolated static func exists(for station: StationID) -> Bool {
        switch station {
        case .chopping, .bowl1, .bowl2, .mixing, .ovenServe: return true
        default: return false
        }
    }

    var body: some View {
        page
            // Hold the counter this page is showing, for as long as it's open.
            //
            // Bowl 1 and bowl 2 run the same four actions, so "which bowl did
            // this prep get made in?" can only be answered by where the chef
            // is standing — `applyCompletion` reads `heldStation`, and the
            // host answers the same question for a guest by looking up the
            // claim in `occupancy`. With no claim it falls back to the station
            // the *recipe* declares, which is how sifting at bowl 2 quietly
            // left the sifted flour sitting at bowl 1, on a counter the chef
            // wasn't even looking at.
            //
            // In a real match `KitchenScene` has already claimed this station
            // before the page opens and `claimStation` returns immediately, so
            // this only does anything on a path that skipped it — the dev
            // menu's station previews. Nothing is released here for the same
            // reason: whoever claimed it first owns letting it go.
            .onAppear { session.claimStation(station) }
    }

    @ViewBuilder
    private var page: some View {
        switch station {
        case .chopping:
            ChoppingStationView(station: station, session: session,
                                inventory: inventory, onClose: onClose)
        // Mixing joins the bowls rather than getting a page of its own. The
        // mix-dough reference frames are drawn on the same wooden bowl on the
        // same slab — they are even captioned BOWL STATION — and the page is
        // written per-recipe, not per-station: it reads its cards, their
        // requirement icons and its drop button out of `Recipe`/`GatingBridge`.
        // Pointed at `.mixing` it shows the one action that counter has, with
        // its four ingredients on the card. A second file would have been the
        // same file with a different bowl.
        case .bowl1, .bowl2, .mixing:
            BowlStationView(station: station, session: session,
                            inventory: inventory, onClose: onClose)
        // Pre-heating and baking. Serving also nominally belongs to this
        // counter, but it is the ritual out on the map and is filtered out of
        // the page's action list — see `OvenStationView.action`.
        case .ovenServe:
            OvenStationView(station: station, session: session,
                            inventory: inventory, onClose: onClose)
        default:
            // Unreachable via `exists(for:)`, and harmless if a caller ever
            // skips that check: the station simply closes again rather than
            // presenting an empty screen with no way out.
            Color.clear.onAppear(perform: onClose)
        }
    }
}
