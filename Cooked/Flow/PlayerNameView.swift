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

    private enum Layout {
        static let fieldCentre = CGPoint(x: 0.4875, y: 0.5125)
        static let fieldSize = CGSize(width: 0.335, height: 0.145)
        static let fieldTextSize = 30.0 / 874
        static let badgeCentre = CGPoint(x: 0.681, y: 0.5125)
        static let badgeDiameter = 0.043
        static let badgeTextSize = 13.0 / 874
    }

    // MARK: - Body

    var body: some View {
        ForestRockScreen(
            title: "PLAYER NAME",
            subtitle: "This will be shown to other chefs!",
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
            .background(Capsule().fill(.white))
            .overlay(Capsule().stroke(AppTheme.stone.opacity(0.55), lineWidth: fieldH * 0.055))
            .position(x: w * Layout.fieldCentre.x, y: h * Layout.fieldCentre.y)
    }

    private func counter(w: CGFloat, h: CGFloat) -> some View {
        let size = w * Layout.badgeDiameter

        return Text("\(chefName.count)/\(Self.maxLength)")
            .font(.system(size: w * Layout.badgeTextSize, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.bark)
            .frame(width: size, height: size)
            .background(Circle().fill(.white))
            .overlay(Circle().stroke(AppTheme.stone.opacity(0.55), lineWidth: size * 0.05))
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
