//
//  PlayerNameView.swift
//  Cooked
//
//  "Enter chef name" — every player names themselves before joining, so the
//  waiting room can list real chefs instead of the "Chef 47" the identity
//  store falls back to.
//
//  Laid out from the Figma frame, which is 874 x 402 (a 402 x 874 portrait
//  frame rotated 90°). Every position below is that frame's number divided by
//  874 or 402, so the screen keeps its proportions on any iPhone rather than
//  only on the one it was drawn for.
//
//  Note on reading the Figma panel: for a layer with rotation 90°, the W and H
//  it reports are *pre-rotation* — the NEXT signpost reads "W 201, H 160" and
//  draws 160 wide by 201 tall. The numbers in `Layout` below are already
//  converted, so they are what you actually see.
//

import SwiftUI

struct PlayerNameView: View {

    /// Runs once the chef has a name and taps NEXT. The caller decides where
    /// that goes — this screen deliberately knows nothing about the flow.
    var onNext: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var chefName = PlayerIdentityStore.current.name
    @FocusState private var nameFocused: Bool

    /// The design counts to 12. `PlayerIdentityStore.rename` clips at 16, so
    /// this is the stricter of the two and the store never has to trim.
    private static let maxLength = 12

    private var trimmed: String {
        chefName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool { !trimmed.isEmpty }

    // MARK: - Layout
    //
    // Fractions of the 874 x 402 design frame. Everything that needs nudging
    // once the real art lands is in this one block.

    private enum Layout {
        // Rock, anchored top-left. The Figma frame's own origin puts the top
        // of the drawing above the screen edge, because that frame is sized
        // around the ivy overhang rather than the rock — so the placement here
        // is matched to the comp instead, which keeps the whole rock on screen
        // with the margin the design shows.
        static let rockLeft = 0.170
        static let rockTop = 0.090
        static let rockWidth = 0.660
        static let rockAspect = 1125.0 / 2055

        // "PLAYER NAME" — Figma X 39, Y 139, in a text box wide enough to
        // centre in, so only the top edge and the centre line matter here.
        static let titleTop = 139.0 / 402
        static let titleSize = 45.31 / 874
        static let titleTracking = 2.27 / 874

        // The name field and its counter, measured off the comp.
        static let fieldCentre = CGPoint(x: 0.4875, y: 0.5125)
        static let fieldSize = CGSize(width: 0.335, height: 0.145)
        static let fieldTextSize = 30.0 / 874
        static let badgeCentre = CGPoint(x: 0.681, y: 0.5125)
        static let badgeDiameter = 0.043
        static let badgeTextSize = 13.0 / 874

        // "This will be shown to other chefs!" — Figma X 323.11, Y 258,
        // W 214, H 22. Rotation 0°, so these needed no converting.
        static let subtitleTop = 258.0 / 402
        static let subtitleSize = 15.0 / 874

        // NEXT signpost — Figma X 703, Y 308, and W/H swapped for the 90°
        // rotation, so 160 wide. It runs off the bottom of the frame in the
        // design; the post is simply cut off by the screen edge.
        static let nextLeft = 703.0 / 874
        static let nextTop = 308.0 / 402
        static let nextWidth = 160.0 / 874
        /// Height over width. The signpost exports 160 x 94pt, which drops its
        /// bottom edge exactly on the bottom of the screen.
        static let nextAspect = 282.0 / 480
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .topLeading) {
                Image("woods-clearing-art")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                rock(w: w, h: h)
                title(w: w, h: h)
                nameField(w: w, h: h)
                counter(w: w, h: h)
                subtitle(w: w, h: h)
                nextButton(w: w, h: h)
                backButton(w: w, h: h)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .onTapGesture { nameFocused = false }
        }
        .ignoresSafeArea()
    }

    // MARK: - Pieces

    private func rock(w: CGFloat, h: CGFloat) -> some View {
        artwork("ui-name-rock", width: w * Layout.rockWidth, aspect: Layout.rockAspect)
            .offset(x: w * Layout.rockLeft, y: h * Layout.rockTop)
    }

    private func title(w: CGFloat, h: CGFloat) -> some View {
        StrokedText(
            "PLAYER NAME",
            font: .system(size: w * Layout.titleSize, weight: .heavy).width(.condensed),
            fill: AppTheme.sand,
            stroke: AppTheme.ink,
            width: w * 0.0035
        )
        .tracking(w * Layout.titleTracking)
        .frame(width: w)
        .position(x: w * 0.5, y: h * Layout.titleTop + w * Layout.titleSize * 0.5)
    }

    private func nameField(w: CGFloat, h: CGFloat) -> some View {
        let fieldW = w * Layout.fieldSize.width
        let fieldH = h * Layout.fieldSize.height

        return TextField("", text: $chefName, prompt:
            Text("Your name").foregroundStyle(AppTheme.ink.opacity(0.35))
        )
        .textFieldStyle(.plain)
        .font(.system(size: w * Layout.fieldTextSize, weight: .heavy).width(.condensed))
        .foregroundStyle(AppTheme.ink)
        .multilineTextAlignment(.center)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .focused($nameFocused)
        .onSubmit { nameFocused = false }
        // Clipping on every change rather than rejecting the keystroke keeps
        // paste working — a pasted 40-character name lands as its first 12
        // instead of being dropped whole.
        .onChange(of: chefName) { _, new in
            if new.count > Self.maxLength {
                chefName = String(new.prefix(Self.maxLength))
            }
        }
        .padding(.horizontal, fieldW * 0.06)
        .frame(width: fieldW, height: fieldH)
        .background(Capsule().fill(.white))
        .overlay(Capsule().stroke(AppTheme.ink.opacity(0.55), lineWidth: fieldH * 0.055))
        .position(x: w * Layout.fieldCentre.x, y: h * Layout.fieldCentre.y)
    }

    private func counter(w: CGFloat, h: CGFloat) -> some View {
        let size = w * Layout.badgeDiameter

        return Text("\(chefName.count)/\(Self.maxLength)")
            .font(.system(size: w * Layout.badgeTextSize, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.ink.opacity(0.7))
            .frame(width: size, height: size)
            .background(Circle().fill(.white))
            .overlay(Circle().stroke(AppTheme.ink.opacity(0.55), lineWidth: size * 0.05))
            .position(x: w * Layout.badgeCentre.x, y: h * Layout.badgeCentre.y)
    }

    private func subtitle(w: CGFloat, h: CGFloat) -> some View {
        Text("This will be shown to other chefs!")
            .font(.system(size: w * Layout.subtitleSize, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.ink.opacity(0.75))
            .frame(width: w)
            .position(x: w * 0.5, y: h * Layout.subtitleTop + w * Layout.subtitleSize * 0.5)
    }

    private func nextButton(w: CGFloat, h: CGFloat) -> some View {
        let buttonW = w * Layout.nextWidth

        return Button {
            PlayerIdentityStore.rename(to: trimmed)
            nameFocused = false
            onNext()
        } label: {
            artwork("ui-next-button", width: buttonW, aspect: Layout.nextAspect)
        }
        .buttonStyle(.plain)
        .opacity(canContinue ? 1 : 0.5)
        .disabled(!canContinue)
        .accessibilityLabel("Next")
        // Anchored by its top-left, the way Figma reports it. Offsetting rather
        // than centring keeps the placement right whatever height the drawing
        // turns out to be.
        .offset(x: w * Layout.nextLeft, y: h * Layout.nextTop)
    }

    private func backButton(w: CGFloat, h: CGFloat) -> some View {
        Button { dismiss() } label: {
            Image("ui-back-button")
                .resizable()
                .scaledToFit()
                .frame(height: h * 0.20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        // No top padding: the signpost is drawn hanging from the top edge, so
        // its post is meant to run off the top of the screen.
        .padding(.leading, w * 0.03)
    }

    // MARK: - Art, or a stand-in for it

    /// The real drawing once it is in the catalog, and a labelled dashed box
    /// until then — so the layout can be built, tapped, and typed into before
    /// any art exists, and each drawing drops in without touching this file.
    @ViewBuilder
    private func artwork(_ name: String, width: CGFloat, aspect: CGFloat) -> some View {
        if let art = UIImage(named: name) {
            Image(uiImage: art)
                .resizable()
                .scaledToFit()
                .frame(width: width)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AppTheme.ink.opacity(0.5),
                                      style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                )
                .overlay(
                    Text(name)
                        .font(.system(size: width * 0.06, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.ink.opacity(0.7))
                        .padding(6)
                )
                .frame(width: width, height: width * aspect)
        }
    }
}

// MARK: - Outlined display text

/// Text with a hard outline, the way the signage in the woodland art is
/// lettered. SwiftUI has no stroke on text, so the glyphs are drawn eight
/// times in the outline colour, offset around a circle, with the fill on top.
private struct StrokedText: View {
    let string: String
    let font: Font
    let fill: Color
    let stroke: Color
    let width: CGFloat

    init(_ string: String, font: Font, fill: Color, stroke: Color, width: CGFloat) {
        self.string = string
        self.font = font
        self.fill = fill
        self.stroke = stroke
        self.width = width
    }

    private static let offsets: [(CGFloat, CGFloat)] = [
        (-1, -1), (0, -1), (1, -1),
        (-1,  0),          (1,  0),
        (-1,  1), (0,  1), (1,  1)
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.offsets.enumerated()), id: \.offset) { _, point in
                Text(string)
                    .foregroundStyle(stroke)
                    .offset(x: point.0 * width, y: point.1 * width)
            }
            Text(string).foregroundStyle(fill)
        }
        .font(font)
        .shadow(color: stroke.opacity(0.35), radius: width * 1.5, x: 0, y: width * 1.5)
    }
}

#Preview("Player name", traits: .landscapeLeft) {
    PlayerNameView()
}
