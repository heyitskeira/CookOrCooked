//
//  SettingsView.swift
//  Cooked
//
//  What the signpost on the start screen opens.
//
//  Music and sound effects are two separate sliders on purpose. Plenty of
//  people turn the music off and keep the effects — being told "audio: off" as
//  a single choice is the thing that makes them turn the lot off instead.
//
//  Laid out against `Asset-Final/Screens/13-settings/screen-13-settings.png`.
//  Every position below is a fraction of the screen, measured off that file at
//  3496 × 1608, so the screen holds its composition at any size instead of
//  being pinned to one device. The numbers are in `Layout` and nowhere else.
//
//  The forest plate and the slab are drawn at the proportions the artwork was
//  composed at rather than at their exported pixel size — the export came in
//  at half the mockup's resolution, and matching pixels would have shrunk the
//  whole scene.
//

import SwiftUI

/// `@MainActor` because the helpers below touch `Music.shared` and
/// `SoundFX.shared`, both of which are main-actor isolated. `body` is isolated
/// for free; the private methods are not.
@MainActor
struct SettingsView: View {

    @ObservedObject private var music = Music.shared
    @ObservedObject private var effects = SoundFX.shared
    @Environment(\.dismiss) private var dismiss

    // MARK: Composition
    //
    // Fractions of screen width (w) or height (h), read off the reference.

    private enum Layout {
        /// The visible rock, not the file.
        ///
        /// Fitted by compositing the slab over the reference at a range of
        /// scales and taking the least-difference one, rather than measured off
        /// the mossy rim — the moss stops short of the stone's actual edge, and
        /// measuring it undersized the slab by about 4% of the screen.
        static let slabWidth: CGFloat = 0.6794
        static let slabCentre: (x: CGFloat, y: CGFloat) = (0.5070, 0.5356)

        /// The exported slab is 1364 × 754 with transparent padding around it;
        /// the stone itself only occupies x 68…1297, y 59…701. SwiftUI frames
        /// the whole file, padding included, so the frame has to be scaled up
        /// by the inverse of these or the rock lands ~11% too small.
        static let slabArtWidth: CGFloat = 1229.0 / 1364.0
        /// The stone also sits a hair low in the file. Small, but free to fix.
        static let slabArtCentreY: CGFloat = ((59.0 + 701.0) / 2) / 754.0

        static let titleCentre: (x: CGFloat, y: CGFloat) = (0.504, 0.351)
        /// Cap height, not point size — the point size is derived from it in
        /// `GameFont.Display.size(forCapHeight:)` so the heading measures the
        /// same whichever face is loaded.
        static let titleCapHeight: CGFloat = 0.0951
        /// Word width in the reference, used to set letter spacing.
        static let titleWidth: CGFloat = 0.2094
        /// The lettering is arched. Fitting a parabola to the baseline gives a
        /// rise of 17.6px at the ends over a 1608px-tall reference — the ends
        /// sit this much lower than the middle.
        static let titleArcRise: CGFloat = 0.0109
        /// Outline thickness as a fraction of point size.
        static let titleOutlineWeight: CGFloat = 0.019

        static let backLeft: CGFloat = 0.0575
        static let backWidth: CGFloat = 0.0563
        /// Bottom of the plaque. The post above it runs off the top of the
        /// screen, exactly as it does in the reference.
        static let backPlaqueBottom: CGFloat = 0.19
        /// Where the plaque sits inside the asset, top and bottom as a
        /// fraction of the asset's own height.
        static let backPlaqueSpan: (top: CGFloat, bottom: CGFloat) = (0.619, 0.993)

        static let labelLeft: CGFloat = 0.2795
        static let labelCapHeight: CGFloat = 0.030

        static let minusCentreX: CGFloat = 0.392
        static let plusCentreX: CGFloat = 0.693
        static let glyphWidth: CGFloat = 0.016

        static let trackStartX: CGFloat = 0.4245
        static let trackEndX: CGFloat = 0.6605
        static let trackHeight: CGFloat = 0.015

        static let knob: (w: CGFloat, h: CGFloat) = (0.0429, 0.0591)

        static let musicRowY: CGFloat = 0.502
        static let soundRowY: CGFloat = 0.649
    }

    // MARK: Palette
    //
    // Sampled from the reference rather than reused from `AppTheme`: this
    // screen sits on painted forest art, and the menu palette was mixed
    // against a flat cream background.

    private enum Ink {
        static let title = Color(red: 0.96, green: 0.91, blue: 0.80)
        static let titleOutline = Color(red: 0.24, green: 0.18, blue: 0.13)
        static let label = Color(red: 0.20, green: 0.17, blue: 0.14)
        static let trackFilled = Color(red: 0.13, green: 0.12, blue: 0.11)
        static let trackRest = Color.black.opacity(0.17)
        static let glyph = Color.black.opacity(0.32)
        static let knob = Color.white
    }

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

                // The reference is this plate under a flat 40% black — matched
                // by sampling it, and it lands within 2/255 across the frame.
                // It is not the `bg-woods-clearing-dim` export, which is a
                // separately painted, much darker plate for the station
                // screens. The scrim is what lets the slab read as lit.
                Color.black.opacity(0.40)
                    .frame(width: w, height: h)

                slab(w: w, h: h)

                title(w: w, h: h)

                slider(value: $music.volume, label: "Music",
                       rowY: Layout.musicRowY, w: w, h: h)

                slider(value: $effects.volume, label: "Sound",
                       rowY: Layout.soundRowY, w: w, h: h)

                backButton(w: w, h: h)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }

    // MARK: Slab

    private func slab(w: CGFloat, h: CGFloat) -> some View {
        // Frame the file, then place it by where the rock inside it ends up.
        let frameW = w * Layout.slabWidth / Layout.slabArtWidth
        let frameH = frameW * (754.0 / 1364.0)
        let centreDrift = (Layout.slabArtCentreY - 0.5) * frameH

        return Image("stone-slab-plain")
            .resizable()
            .scaledToFit()
            .frame(width: frameW, height: frameH)
            .position(x: w * Layout.slabCentre.x,
                      y: h * Layout.slabCentre.y - centreDrift)
    }

    // MARK: Title

    private func title(w: CGFloat, h: CGFloat) -> some View {
        ArchedTitle(text: "SETTINGS",
                    capHeight: h * Layout.titleCapHeight,
                    width: w * Layout.titleWidth,
                    arcRise: h * Layout.titleArcRise,
                    outlineWeight: Layout.titleOutlineWeight,
                    fill: Ink.title,
                    outline: Ink.titleOutline)
            .position(x: w * Layout.titleCentre.x, y: h * Layout.titleCentre.y)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Back

    private func backButton(w: CGFloat, h: CGFloat) -> some View {
        let width = w * Layout.backWidth
        // 104 × 268 — the post-and-plaque signpost, not the round
        // `back-button` disc the other flow screens use.
        let height = width * (268.0 / 104.0)
        let plaqueHeight = height * (Layout.backPlaqueSpan.bottom - Layout.backPlaqueSpan.top)
        // How far the art hangs below the plaque box's own bottom edge.
        let tailBelow = height * (1 - Layout.backPlaqueSpan.bottom)

        return Button {
            SoundFX.shared.play(.tap)
            dismiss()
        } label: {
            // The button's frame is the plaque alone — the post is scenery and
            // runs off the top of the screen, so it must not be tappable. The
            // full signpost is drawn as an unclipped overlay hanging out of
            // that frame.
            Color.clear
                .frame(width: width, height: plaqueHeight)
                .overlay(alignment: .bottom) {
                    Image("back-signpost")
                        .resizable()
                        .scaledToFit()
                        .frame(width: width, height: height)
                        .offset(y: tailBelow)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(SignpostPress())
        .position(x: w * Layout.backLeft + width / 2,
                  y: h * Layout.backPlaqueBottom - plaqueHeight / 2)
        .accessibilityLabel("Back")
    }

    // MARK: One slider

    private func slider(value: Binding<Double>, label: String,
                        rowY: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        let y = h * rowY
        let trackStart = w * Layout.trackStartX
        let trackEnd = w * Layout.trackEndX
        let knobW = w * Layout.knob.w
        let knobH = h * Layout.knob.h

        // The thumb's centre travels between the track ends inset by its own
        // half-width, so the knob never overhangs the track.
        let travelStart = trackStart + knobW / 2
        let travelEnd = trackEnd - knobW / 2
        let travel = max(travelEnd - travelStart, 1)
        let knobX = travelStart + travel * CGFloat(value.wrappedValue)

        let filled = max(knobX - trackStart, 0)

        return ZStack(alignment: .topLeading) {
            Text(label)
                .font(GameFont.Label.font(
                    size: GameFont.Label.size(forCapHeight: h * Layout.labelCapHeight)))
                .foregroundStyle(Ink.label)
                .lineLimit(1)
                .frame(width: labelWidth(w), alignment: .leading)
                .position(x: w * Layout.labelLeft + labelWidth(w) / 2, y: y)

            stepGlyph(.minus, w: w, h: h)
                .position(x: w * Layout.minusCentreX, y: y)
                .onTapGesture { step(value, by: -0.1) }

            stepGlyph(.plus, w: w, h: h)
                .position(x: w * Layout.plusCentreX, y: y)
                .onTapGesture { step(value, by: 0.1) }

            Capsule()
                .fill(Ink.trackRest)
                .frame(width: trackEnd - trackStart, height: h * Layout.trackHeight)
                .position(x: (trackStart + trackEnd) / 2, y: y)

            Capsule()
                .fill(Ink.trackFilled)
                .frame(width: filled, height: h * Layout.trackHeight)
                .position(x: trackStart + filled / 2, y: y)

            Capsule()
                .fill(Ink.knob)
                .frame(width: knobW, height: knobH)
                .shadow(color: .black.opacity(0.28), radius: knobH * 0.12,
                        x: 0, y: knobH * 0.06)
                .position(x: knobX, y: y)

            // The drag target: the length of the track, and tall enough to
            // hit. Deliberately not the knob — a thumb covers a knob this
            // size, and a gesture scoped to it drops the drag the moment you
            // slide past its edge. Deliberately not the whole row either, or
            // it would swallow the − and + taps sitting on either side.
            Color.clear
                .frame(width: trackEnd - trackStart, height: max(knobH * 1.8, 44))
                .contentShape(Rectangle())
                // Read in the row's space, not the rectangle's, so the maths
                // below doesn't depend on where `.position` puts it.
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.rowSpace))
                        .onChanged { g in
                            let x = min(max(g.location.x, travelStart), travelEnd)
                            value.wrappedValue = Double((x - travelStart) / travel)
                        }
                )
                .position(x: (trackStart + trackEnd) / 2, y: y)
        }
        .coordinateSpace(.named(Self.rowSpace))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value.wrappedValue * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            step(value, by: direction == .increment ? 0.1 : -0.1)
        }
    }

    /// Wide enough for either label without measuring text.
    private func labelWidth(_ w: CGFloat) -> CGFloat { w * 0.09 }

    /// Each row is its own coordinate space, so a drag reads the same whether
    /// the row sits at the top of the slab or the bottom.
    private static let rowSpace = "settings.row"

    private func step(_ value: Binding<Double>, by delta: Double) {
        let next = min(max(value.wrappedValue + delta, 0), 1)
        guard next != value.wrappedValue else { return }
        withAnimation(.easeOut(duration: 0.15)) { value.wrappedValue = next }
        SoundFX.shared.play(.tap)
    }

    // MARK: − / +

    private enum Step { case minus, plus }

    private func stepGlyph(_ kind: Step, w: CGFloat, h: CGFloat) -> some View {
        let size = w * Layout.glyphWidth
        let bar = size * 0.14

        return ZStack {
            Capsule().fill(Ink.glyph).frame(width: size, height: bar)
            if kind == .plus {
                Capsule().fill(Ink.glyph).frame(width: bar, height: size)
            }
        }
        // A 1.6%-wide glyph is well under the 44pt minimum on its own.
        .frame(width: max(size * 2.4, 44), height: max(size * 2.4, 44))
        .contentShape(Rectangle())
    }
}

// MARK: - Press feedback

/// The signpost is painted art, so it can't recolour on press the way a filled
/// button does. It takes a small push instead.
private struct SignpostPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview(traits: .landscapeLeft) {
    SettingsView()
}
