//
//  KitchenCodeView.swift
//  Cooked
//
//  The four digits off the host's screen — the same-room check.
//
//  There is no frame for this in the design file, so it is built from the
//  setup screens' own parts: the same rock, the same arced title, the same
//  parchment plates, and the JOIN signpost the kitchen list uses. The digit
//  plates borrow the name field's box, divided four ways.
//
//  Typing works the way the name field does: one real text field, invisible,
//  doing the keyboard and the editing, with the digits drawn on top. Four
//  separate fields would fight each other over focus for no gain.
//
//  The fourth digit submits on its own. A room code is a known, fixed length,
//  so there is nothing for a JOIN tap to confirm — the code is either four
//  digits or it isn't, and the player has already said everything they have to
//  say. It also gets the number pad out of the way without being asked, which
//  in landscape is sitting over the plates the digits are drawn on.
//
//  The signpost stays for the player who reaches for it anyway, and both routes
//  go through `submit()` so neither can fire the join twice.
//

import SwiftUI

struct KitchenCodeView: View {
    @Environment(\.dismiss) private var dismiss

    let kitchenName: String
    let onJoin: (RoomCode) -> Void

    @State private var typed = ""
    @FocusState private var focused: Bool
    /// The join is a one-way door — it dismisses this screen and hands the code
    /// to the session. The fourth digit and the signpost can both reach it, and
    /// on a slow frame both could reach it for the same code.
    @State private var hasJoined = false

    private var code: RoomCode? { RoomCode(typed) }

    /// How long the finished code sits on screen before the join goes through.
    ///
    /// Not a stall: the fourth digit and the join land on the same frame
    /// otherwise, so the plate the player just filled is never actually seen
    /// filled. Long enough to read as "that's the code", short enough not to
    /// read as the app thinking about it.
    private static let settleBeat = 0.25

    // MARK: - Layout
    //
    // The name screen's field is 296.8 x 60.8 at (258.4, 157.3). Four plates
    // and three gaps divide that span, so this screen lines up with the one
    // before it rather than floating at its own height.

    private enum Layout {
        static let rockTop = -29.0 / 402
        static let titleTop = 110.0 / 402
        static let subtitleTop = 229.0 / 402

        static let rowCentre = CGPoint(x: (258.4 + 296.8 / 2) / 874,
                                       y: (157.3 + 60.8 / 2) / 402)
        static let plateWidth = 62.0 / 874
        static let plateHeight = 60.8 / 402
        static let plateGap = 16.0 / 874
        static let plateStroke = 2.99 / 402
        static let digitSize = 43.82 / 874
        static let digitStroke = 1.0 / 45.31
    }

    private static let length = 4

    // MARK: - Body

    var body: some View {
        ForestRockScreen(
            title: "KITCHEN CODE",
            subtitle: "Type the four digits shown on the host's screen",
            rockTop: Layout.rockTop,
            titleTop: Layout.titleTop,
            subtitleTop: Layout.subtitleTop,
            subtitleColor: AppTheme.barkDeep,
            nextAsset: "ui-join-button",
            nextLabel: "Join",
            nextAspect: 201.0 / 160.0,
            nextEnabled: code != nil,
            onBack: { dismiss() },
            onNext: submit
        ) { w, h in
            digits(w: w, h: h)
            field(w: w, h: h)
        }
        // The keyboard is the point of this screen, so it comes up on arrival
        // rather than after a tap nobody is told to make.
        .onAppear { focused = true }
    }

    // MARK: - Joining

    /// The fourth digit landed. Drop the number pad straight away — in
    /// landscape it covers the plates, and the player's first instinct on
    /// finishing is to look at what they typed — then join once they have had a
    /// moment to see it.
    private func codeIsComplete() {
        guard !hasJoined else { return }
        focused = false

        let entered = typed
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleBeat) {
            // The pad takes about this long to animate away, and keys pressed
            // while it is still on screen still land — so a player who spots a
            // wrong digit can just about get a backspace in. Their correction
            // wins, and the pad comes back, because it is already leaving and
            // they have no other way to type.
            guard typed == entered else {
                focused = true
                return
            }
            submit()
        }
    }

    /// The one way out of this screen with a code. Both the fourth digit and
    /// the signpost come through here, so a player who taps JOIN while the beat
    /// is still running cannot join the same kitchen twice.
    private func submit() {
        guard !hasJoined, let code else { return }
        hasJoined = true
        focused = false
        onJoin(code)
    }

    // MARK: - Pieces

    /// The real field, invisible and one point across. It exists to own the
    /// keyboard and the text; everything visible is drawn by `digits`.
    private func field(w: CGFloat, h: CGFloat) -> some View {
        TextField("", text: $typed)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($focused)
            .foregroundStyle(.clear)
            .tint(.clear)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .onChange(of: typed) { _, new in
                let cleaned = String(new.filter(\.isNumber).prefix(Self.length))
                // Writing the cleaned value back re-enters this closure with
                // it, so the completeness check below belongs to that pass —
                // doing it here as well would run it twice on every paste.
                if cleaned != new {
                    typed = cleaned
                    return
                }
                if cleaned.count == Self.length { codeIsComplete() }
            }
            .position(x: w * Layout.rowCentre.x, y: h * Layout.rowCentre.y)
    }

    private func digits(w: CGFloat, h: CGFloat) -> some View {
        let plateW = w * Layout.plateWidth
        let plateH = h * Layout.plateHeight
        let digitSize = w * Layout.digitSize
        let digitFont = UIFont.systemFont(ofSize: digitSize, weight: .heavy, width: .condensed)
        let characters = Array(typed)

        return HStack(spacing: w * Layout.plateGap) {
            ForEach(0..<Self.length, id: \.self) { index in
                let filled = index < characters.count
                // The plate waiting for the next digit is outlined heavier, so
                // there is somewhere obvious for the eye to sit while typing.
                let isNext = index == characters.count && focused

                RoundedRectangle(cornerRadius: plateH * 0.28, style: .continuous)
                    .fill(AppTheme.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: plateH * 0.28, style: .continuous)
                            .stroke(AppTheme.barkDeep,
                                    lineWidth: h * Layout.plateStroke * (isNext ? 1.8 : 1))
                    )
                    .overlay {
                        if filled {
                            ArcText(String(characters[index]),
                                    font: digitFont,
                                    fill: AppTheme.bark,
                                    stroke: AppTheme.barkDeep,
                                    strokeWidth: digitSize * Layout.digitStroke,
                                    bend: .zero,
                                    shadowOpacity: 0)
                        }
                    }
                    .frame(width: plateW, height: plateH)
            }
        }
        // The whole row is the tap target — hitting a 62-point plate to summon
        // a keyboard is fiddly, and there is only one field behind them anyway.
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .position(x: w * Layout.rowCentre.x, y: h * Layout.rowCentre.y)
        .accessibilityElement()
        .accessibilityLabel("Kitchen code for \(kitchenName)")
        .accessibilityValue(typed.isEmpty ? "Empty" : typed.map(String.init).joined(separator: " "))
    }
}

#Preview("Empty — JOIN dimmed", traits: .landscapeLeft) {
    KitchenCodeView(kitchenName: "Bambi's Kitchen") { _ in }
}
