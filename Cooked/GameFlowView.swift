//
//  GameFlowView.swift
//  Cooked
//
//  One screen for everything after the lobby: the recipe book, then the
//  kitchen.
//
//  Why one view instead of two presentations: swapping the item of a live
//  `fullScreenCover` is where SwiftUI gets unreliable, and a cover presented
//  from inside another cover is worse. The lobby presents this once, and the
//  session's phase decides what is on screen — so a guest joining halfway
//  through lands in the right place with no transition logic anywhere else.
//

import SwiftUI

struct GameFlowView: View {

    @ObservedObject var session: KitchenSession

    var body: some View {
        ZStack {
            // Tested against .playing rather than .briefing on purpose. Backing
            // out of the book sets the phase to .idle, and this view is still
            // on screen for the frame or two before the cover closes — asking
            // "is it briefing?" would build the whole kitchen scene during a
            // dismissal nobody asked for.
            if session.phase == .playing {
                KitchenGameView(session: session)
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else {
                RecipeBookView(session: session)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
    }
}
