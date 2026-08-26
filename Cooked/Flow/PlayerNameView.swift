//
//  PlayerNameView.swift
//  Cooked
//
//  "Enter chef name" — every player names themselves before joining, so the
//  waiting room can list real chefs instead of the "Chef 47" the identity
//  store falls back to.
//
//  The forest, rock, title, helper line, and the two signposts all come from
//  `ForestRockScreen`. Only the name field and its counter are this screen's,
//  and the layout numbers for those are in `Layout` below.
//

import SwiftUI

struct PlayerNameView: View {

    /// Runs once the chef has a name and taps NEXT. The caller decides where
    /// that goes — this screen deliberately knows nothing about the flow.
    var onNext: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var chefName: String
    @FocusState private var nameFocused: Bool

    /// The field starts on whatever name this device last saved, so a returning
    /// chef only has to tap NEXT. `startingName` overrides that for previews,
    /// which is the only way to see the empty state in the canvas — a real
    /// launch always has a stored name, even if it is the "Chef 47" fallback.
    init(startingName: String? = nil, onNext: @escaping () -> Void = {}) {
        self.onNext = onNext
        _chefName = State(initialValue: startingName ?? PlayerIdentityStore.current.name)
    }

    /// The design counts to 12. `PlayerIdentityStore.rename` clips at 16, so
    /// this is the stricter of the two and the store never has to trim.
    private static let maxLength = 12

    private var trimmed: String {
        chefName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool { !trimmed.isEmpty }

    // MARK: - Layout

    // Straight off the Figma frame (874 x 402), which reports each layer's
    // rendered box — no converting for rotation needed.
    private enum Layout {
        static let rockTop = -29.0 / 402
        static let titleTop = 110.0 / 402
        static let subtitleTop = 229.0 / 402

        // Rectangle 49: x 258.4, y 157.3, 296.8 x 60.8, 3pt stroke.
        static let fieldCentre = CGPoint(x: (258.4 + 296.8 / 2) / 874,
                                         y: (157.3 + 60.8 / 2) / 402)
        static let fieldSize = CGSize(width: 296.8 / 874, height: 60.8 / 402)
        static let fieldStrokeWidth = 2.99 / 402
        static let fieldTextSize = 43.82 / 874

        // Rectangle 50: x 567.1, y 165.3, 45.8 square, same 3pt stroke.
        static let badgeCentre = CGPoint(x: (567.1 + 45.8 / 2) / 874,
                                         y: (165.3 + 45.8 / 2) / 402)
        static let badgeDiameter = 45.8 / 874
        static let badgeTextSize = 13.94 / 874
    }

    // MARK: - Body

    var body: some View {
        ForestRockScreen(
            title: "PLAYER NAME",
            subtitle: "This will be shown to other chefs!",
            rockTop: Layout.rockTop,
            titleTop: Layout.titleTop,
            subtitleTop: Layout.subtitleTop,
            subtitleColor: AppTheme.barkDeep,
            nextEnabled: canContinue,
            onBack: { dismiss() },
            onNext: {
                PlayerIdentityStore.rename(to: trimmed)
                nameFocused = false
                onNext()
            }
        ) { w, h in
            nameField(w: w, h: h)
            counter(w: w, h: h)
        }
        .contentShape(Rectangle())
        .onTapGesture { nameFocused = false }
    }

    // MARK: - Pieces

    private func nameField(w: CGFloat, h: CGFloat) -> some View {
        let fieldW = w * Layout.fieldSize.width
        let fieldH = h * Layout.fieldSize.height
        let textSize = w * Layout.fieldTextSize
        let glyphFont = UIFont.systemFont(ofSize: textSize, weight: .heavy, width: .condensed)

        // SwiftUI gives editable text one flat colour and no stroke, so the
        // field itself is made invisible and the lettering is drawn on top of
        // it. The real TextField is still there underneath doing the editing,
        // the keyboard, and the caret — only its glyphs are hidden.
        return TextField("", text: $chefName)
            .textFieldStyle(.plain)
            .font(Font(glyphFont))
            .foregroundStyle(.clear)
            .tint(AppTheme.barkDeep)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($nameFocused)
            .onSubmit { nameFocused = false }
            // Clipping on every change rather than rejecting the keystroke
            // keeps paste working — a pasted 40-character name lands as its
            // first 12 instead of being dropped whole.
            .onChange(of: chefName) { _, new in
                if new.count > Self.maxLength {
                    chefName = String(new.prefix(Self.maxLength))
                }
            }
            .padding(.horizontal, fieldW * 0.06)
            .frame(width: fieldW, height: fieldH)
            .overlay {
                Group {
                    if chefName.isEmpty {
                        Text("Your name")
                            .font(Font(glyphFont))
                            .foregroundStyle(AppTheme.bark.opacity(0.40))
                    } else {
                        ArcText(chefName,
                                font: glyphFont,
                                fill: AppTheme.bark,
                                stroke: AppTheme.barkDeep,
                                strokeWidth: textSize * RockLayout.strokeRatio,
                                bend: .zero,
                                shadowOpacity: 0)
                    }
                }
                // On the drawn glyphs only. Put this outside the overlay and it
                // deadens the whole field, keyboard and all.
                .allowsHitTesting(false)
            }
            .background(Capsule().fill(AppTheme.paper))
            .overlay(Capsule().stroke(AppTheme.barkDeep, lineWidth: h * Layout.fieldStrokeWidth))
            .position(x: w * Layout.fieldCentre.x, y: h * Layout.fieldCentre.y)
    }

    private func counter(w: CGFloat, h: CGFloat) -> some View {
        let size = w * Layout.badgeDiameter

        return Text("\(chefName.count)/\(Self.maxLength)")
            .font(.system(size: w * Layout.badgeTextSize, weight: .medium).width(.condensed))
            .foregroundStyle(AppTheme.barkDeep)
            .frame(width: size, height: size)
            .background(Circle().fill(AppTheme.paper))
            .overlay(Circle().stroke(AppTheme.barkDeep, lineWidth: h * Layout.fieldStrokeWidth))
            .position(x: w * Layout.badgeCentre.x, y: h * Layout.badgeCentre.y)
    }
}

#Preview("Named — NEXT live", traits: .landscapeLeft) {
    PlayerNameView(startingName: "Team Cookedd")
}

#Preview("Empty — NEXT dimmed", traits: .landscapeLeft) {
    PlayerNameView(startingName: "")
}

#Preview("Longest name — 12/12", traits: .landscapeLeft) {
    PlayerNameView(startingName: "Wolfgangaaaa")
}
