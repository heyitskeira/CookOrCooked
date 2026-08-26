//
//  InstantPresentation.swift
//  Cooked
//
//  Screens that cut, rather than slide up from the bottom.
//
//  `fullScreenCover` is the only way to hand one screen the whole display, and
//  it always animates the same way: the new screen rises from the bottom edge.
//  That reads as a modal — something stacked on top of what you were doing,
//  that you will come back from. Almost nothing in this game is that. Walking
//  from the welcome screen to the name screen, or from the lobby into the
//  kitchen, is going *forward*; the slide made every one of those feel like
//  opening a sheet, and a whole flow of them feels like being nudged upstairs
//  one step at a time.
//
//  So the presentation is stripped of its animation and the screen simply
//  appears. Dismissal goes with it — a screen that cuts in and slides out would
//  be worse than either on its own.
//
//  ---
//
//  Why `transaction(_:body:)` and not plain `.transaction { }`:
//
//  The plain modifier applies to the view and everything under it, which means
//  it also flattens animations *inside* the screen being presented — the bar
//  filling at a station, the flash when the oven lights. The two-argument form
//  scopes the change to just the modifier built in `body`, so only the
//  presentation itself loses its animation and the screen behaves normally once
//  it is up.
//

import SwiftUI

extension View {

    /// `fullScreenCover(isPresented:)` with no slide-up.
    func instantFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        transaction { $0.disablesAnimations = true } body: {
            $0.fullScreenCover(isPresented: isPresented, content: content)
        }
    }

    /// `fullScreenCover(item:)` with no slide-up.
    func instantFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        transaction { $0.disablesAnimations = true } body: {
            $0.fullScreenCover(item: item, content: content)
        }
    }
}
