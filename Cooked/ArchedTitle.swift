//
//  ArchedTitle.swift
//  Cooked
//
//  The game's heading treatment: heavy caps arched along a shallow curve, with
//  a dark outline and a soft drop shadow.
//
//  Measured off `Asset-Final/Screens/13-settings/screen-13-settings.png`. The
//  baseline there fits a parabola rising 17.6px at each end over a 733px word,
//  while the cap height stays constant across the word — so it is an arc warp,
//  letters shifted down and rotated, not letters scaled.
//
//  The letterforms come from `GameFont.Display` (SF Pro Black, condensed); the
//  arc, the outline and the shadow are all drawn here.
//
//  Reusable on purpose: the same treatment appears on `TODAY'S ORDER` and the
//  station plaques, and none of them should re-derive this.
//

import SwiftUI

struct ArchedTitle: View {

    let text: String
    /// Height of the capitals. The point size is derived from this so the
    /// heading measures the same whichever face is loaded.
    let capHeight: CGFloat
    /// Target width for the whole word. The word is squeezed horizontally to
    /// meet it — SF Pro's `.condensed` width gets close but not exact, and the
    /// remainder is made up here so the heading always spans the same fraction
    /// of the slab.
    let width: CGFloat
    /// How much lower the last letter sits than the middle one.
    let arcRise: CGFloat
    /// Outline thickness, as a fraction of point size.
    var outlineWeight: CGFloat = 0.019
    let fill: Color
    let outline: Color

    /// Natural width of the word before squeezing, measured at runtime.
    @State private var naturalWidth: CGFloat = 0

    private var pointSize: CGFloat { GameFont.Display.size(forCapHeight: capHeight) }
    private var stroke: CGFloat { pointSize * outlineWeight }

    private var characters: [(offset: Int, element: Character)] {
        Array(text.enumerated()).map { (offset: $0.offset, element: $0.element) }
    }

    var body: some View {
        ZStack {
            // Twelve copies ringed behind the fill. SwiftUI has no text-stroke
            // modifier, and this is the standard way to get one. Twelve rather
            // than eight because at this weight the gaps between eight copies
            // show as scallops on the round letters.
            ForEach(0..<12, id: \.self) { i in
                let angle = Double(i) / 12 * 2 * .pi
                word(colour: outline)
                    .offset(x: stroke * CGFloat(cos(angle)),
                            y: stroke * CGFloat(sin(angle)))
            }
            word(colour: fill)
        }
        .shadow(color: outline.opacity(0.35),
                radius: pointSize * 0.035, x: 0, y: pointSize * 0.045)
        .frame(width: width, height: capHeight + arcRise + stroke * 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    // MARK: One pass of the word

    private func word(colour: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(characters, id: \.offset) { item in
                // Position across the word, -1 at the first letter to +1 at
                // the last. Taken from the index rather than from real letter
                // advances: over eight characters and a rise this shallow the
                // difference is under a pixel, and measuring every glyph to
                // get it would cost a layout pass per frame.
                let u = characters.count > 1
                    ? (2 * (CGFloat(item.offset) + 0.5) / CGFloat(characters.count)) - 1
                    : 0
                Text(String(item.element))
                    .font(GameFont.Display.font(size: pointSize))
                    .foregroundStyle(colour)
                    .offset(y: arcRise * u * u)
                    .rotationEffect(.radians(atan(4 * arcRise * u / max(width, 1))))
            }
        }
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { naturalWidth = $0 }
        // Squeeze to the reference proportions. Measured rather than held as a
        // per-face constant, so dropping in a display face with different
        // proportions still lands the heading at the right width instead of
        // silently overflowing the slab.
        .scaleEffect(x: naturalWidth > 0 ? min(width / naturalWidth, 1.4) : 1,
                     y: 1, anchor: .center)
    }
}

#Preview {
    ZStack {
        Color(red: 0.63, green: 0.58, blue: 0.49)
        ArchedTitle(text: "SETTINGS",
                    capHeight: 76,
                    width: 366,
                    arcRise: 9,
                    fill: Color(red: 0.96, green: 0.91, blue: 0.80),
                    outline: Color(red: 0.24, green: 0.18, blue: 0.13))
    }
    .frame(width: 700, height: 300)
}
