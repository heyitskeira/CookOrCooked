//
//  ForestRockScreen.swift
//  Cooked
//
//  The setup screens — chef name, number of players — are the same picture with
//  a different middle: dimmed forest, mossy rock, an arced title across the top
//  of it, a line of helper text under it, a back signpost hanging off the top
//  left and a NEXT signpost running off the bottom right.
//
//  Only the bit in the middle of the rock changes, so that is the only bit each
//  screen supplies. Everything else lives here once.
//
//  Laid out from the Figma frame, which is 874 x 402 (a 402 x 874 portrait
//  frame rotated 90°). Every position is that frame's number divided by 874 or
//  402, so the screens keep their proportions on any iPhone rather than only on
//  the one they were drawn for.
//
//  Reading the Figma panel: for a layer with rotation 90°, the W and H it
//  reports are *pre-rotation* — the NEXT signpost reads "W 201, H 160" and
//  draws 160 wide by 201 tall. The numbers below are already converted.
//

import SwiftUI

// MARK: - Shared layout

enum RockLayout {

    /// How far the forest is pushed back behind the rock. This is a black veil
    /// laid *over* the art, not the art's own opacity — turning that down
    /// blends the image toward the white window behind it, which washes the
    /// forest out instead of darkening it.
    static let backdropDim = 0.35

    // Rock, anchored top-left, straight off the Figma frame: x 100, w 684.7.
    // Its vertical origin differs per screen — the chef-name rock is pushed up
    // so the vine overhang runs off the top — so `rockTop` is passed in.
    static let rockLeft = 100.0 / 874
    static let rockWidth = 684.7 / 874
    static let rockAspect = 1125.0 / 2055

    static let titleSize = 45.31 / 874
    static let titleTracking = 2.27 / 874

    /// How hard the title arcs: the total sweep from its first letter to its
    /// last, so 0° is dead flat and bigger numbers bend it further over the
    /// rock. **This is the dial to turn** — nothing else needs touching.
    static let titleBend = Angle.degrees(25)

    /// Figma draws the lettering with a 1pt outside stroke at a 45pt size, so
    /// the outline scales with the type rather than sitting at a fixed
    /// thickness that would go fat on a small phone.
    static let strokeRatio = 1.0 / 45.31

    static let subtitleSize = 16.0 / 874

    // NEXT signpost — Figma X 703, Y 308, W/H swapped for the 90° rotation, so
    // 160 wide. It runs off the bottom of the frame in the design; the post is
    // simply cut off by the screen edge.
    static let nextLeft = 703.0 / 874
    static let nextTop = 308.0 / 402
    static let nextWidth = 160.0 / 874
    static let nextAspect = 282.0 / 480

    // Back signpost — Figma x 49, and 134 tall from y -56, of which the 78pt
    // below the screen edge is what the export contains. So the drawing starts
    // at y 0 and the post it hangs from is simply off-screen above.
    static let backLeft = 49.0 / 874
    static let backHeight = 78.0 / 402
}

/// One drawing making up part of a rock, placed by its own box in the design.
///
/// The lobby's rock is a slab with three separate falls of ivy over it, and
/// they cannot be flattened into one export: the group that holds them in Figma
/// also holds the screen's title and its chef cards, so exporting the group
/// bakes a mock kitchen's name and chefs into the background.
struct RockLayer {
    let asset: String
    let left: CGFloat
    let top: CGFloat
    let width: CGFloat
    let aspect: CGFloat
}

// MARK: - The screen

struct ForestRockScreen<Content: View>: View {

    let title: String

    /// Empty on screens the design gives no helper line, such as the kitchen
    /// list — the rows are their own explanation.
    var subtitle: String = ""

    /// The rock itself. The setup screens share one slab; the waiting room is
    /// drawn on a wider one with vines down both sides.
    var rockAsset: String = "ui-name-rock"
    var rockLeft: CGFloat = RockLayout.rockLeft
    var rockWidth: CGFloat = RockLayout.rockWidth
    var rockAspect: CGFloat = RockLayout.rockAspect

    /// Drawn instead of `rockAsset` when its pieces are in the catalog. Falls
    /// back to the single image while they are not, so a half-finished export
    /// never leaves the screen with nothing behind it.
    var rockLayers: [RockLayer] = []

    /// Where the rock's top edge sits. Negative pushes it off the top of the
    /// screen, which is what the chef-name screen does.
    var rockTop: CGFloat = 0

    /// Top of the title's text box, and of the helper line. Both differ per
    /// screen in the design, so neither can be a shared constant.
    var titleTop: CGFloat
    var subtitleTop: CGFloat = 0

    /// The helper line's colour. The two screens letter it differently.
    var subtitleColor: Color = AppTheme.stone

    /// The signpost bottom right, and what it is called out loud. Most screens
    /// carry NEXT; the kitchen list carries JOIN.
    var nextAsset: String = "ui-next-button"
    var nextLabel: String = "Next"
    var nextAspect: CGFloat = RockLayout.nextAspect

    /// The sign dims and stops responding when this is false, and is not drawn
    /// at all when `showNext` is false — a guest in the lobby has nothing to
    /// press, the host starts the game.
    var nextEnabled: Bool = true
    var showNext: Bool = true

    var onBack: () -> Void
    var onNext: () -> Void

    /// The middle of the rock. Handed the screen's width and height so it can
    /// position its own pieces in the same fractions everything else uses.
    @ViewBuilder var content: (CGFloat, CGFloat) -> Content

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

                // Between the forest and the rock, so the rock and its
                // lettering stay at full brightness while everything behind
                // them drops back.
                Color.black.opacity(RockLayout.backdropDim)
                    .frame(width: w, height: h)

                rockArt(w: w, h: h)
                titleText(w: w, h: h)
                content(w, h)
                if !subtitle.isEmpty {
                    subtitleText(w: w, h: h)
                }
                if showNext {
                    nextButton(w: w, h: h)
                }
                backButton(w: w, h: h)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }

    // MARK: - Pieces

    @ViewBuilder
    private func rockArt(w: CGFloat, h: CGFloat) -> some View {
        if rockLayers.isEmpty || !rockLayers.allSatisfy({ UIImage(named: $0.asset) != nil }) {
            RockArt.image(rockAsset, width: w * rockWidth, aspect: rockAspect)
                .offset(x: w * rockLeft, y: h * rockTop)
        } else {
            ForEach(Array(rockLayers.enumerated()), id: \.offset) { _, layer in
                RockArt.image(layer.asset, width: w * layer.width, aspect: layer.aspect)
                    .offset(x: w * layer.left, y: h * layer.top)
            }
        }
    }

    private func titleText(w: CGFloat, h: CGFloat) -> some View {
        let size = w * RockLayout.titleSize

        return ArcText(
            title,
            font: .systemFont(ofSize: size, weight: .heavy, width: .condensed),
            fill: AppTheme.sand,
            stroke: AppTheme.stone,
            strokeWidth: size * RockLayout.strokeRatio,
            bend: RockLayout.titleBend,
            tracking: w * RockLayout.titleTracking
        )
        .position(x: w * 0.5, y: h * titleTop + size * 0.5)
    }

    private func subtitleText(w: CGFloat, h: CGFloat) -> some View {
        Text(subtitle)
            .font(.system(size: w * RockLayout.subtitleSize, weight: .medium).width(.condensed))
            .foregroundStyle(subtitleColor)
            .frame(width: w)
            .position(x: w * 0.5, y: h * subtitleTop + w * RockLayout.subtitleSize * 0.5)
    }

    private func nextButton(w: CGFloat, h: CGFloat) -> some View {
        let buttonW = w * RockLayout.nextWidth

        return Button(action: onNext) {
            RockArt.image(nextAsset, width: buttonW, aspect: nextAspect)
        }
        .buttonStyle(.plain)
        .opacity(nextEnabled ? 1 : 0.5)
        .disabled(!nextEnabled)
        .accessibilityLabel(nextLabel)
        // Anchored top-left, the way Figma reports it. Offsetting rather than
        // centring keeps the placement right whatever height the drawing is.
        .offset(x: w * RockLayout.nextLeft, y: h * RockLayout.nextTop)
    }

    private func backButton(w: CGFloat, h: CGFloat) -> some View {
        Button(action: onBack) {
            Image("ui-back-button")
                .resizable()
                .scaledToFit()
                .frame(height: h * RockLayout.backHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        // No vertical offset: the drawing already starts at the screen edge,
        // with the rest of its post above and out of frame.
        .offset(x: w * RockLayout.backLeft)
    }
}

// MARK: - Art, or a stand-in for it

enum RockArt {

    /// A drawing scaled to sit inside a box rather than to a width.
    ///
    /// Art exported per-character comes back at whatever proportions each
    /// drawing happens to have — the chef animals range from 0.82 to 1.59 tall
    /// over wide. Sizing those by width alone gives every one a different
    /// height, which is what pulls a row of cards out of line. Fitting them to
    /// a shared box and standing them on its bottom edge keeps the row level
    /// however different the drawings are.
    @ViewBuilder
    static func fitted(_ name: String,
                       width: CGFloat,
                       height: CGFloat,
                       alignment: Alignment = .bottom) -> some View {
        if let art = UIImage(named: name) {
            Image(uiImage: art)
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height, alignment: alignment)
        } else {
            placeholder(name, width: width, height: height)
        }
    }

    @ViewBuilder
    static func placeholder(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppTheme.ink.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            )
            .overlay(
                Text(name)
                    .font(.system(size: max(width * 0.09, 5), weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.ink.opacity(0.7))
                    .minimumScaleFactor(0.5)
                    .padding(3)
            )
            .frame(width: width, height: height)
    }

    /// The real drawing once it is in the catalog, and a labelled dashed box
    /// until then — so a layout can be built, tapped, and typed into before any
    /// art exists, and each drawing drops in without a code change.
    @ViewBuilder
    static func image(_ name: String, width: CGFloat, aspect: CGFloat) -> some View {
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

// MARK: - Arced display text

/// Display text bent along a circle, the way the signage on the rock is
/// lettered — the words follow the top of an ellipse rather than sitting on a
/// flat baseline.
///
/// Letters are placed by their own advance widths rather than spaced evenly, so
/// the wide "W" and the narrow "I" keep the rhythm the font intends. Each one is
/// set at the angle its position on the arc calls for, which is why the letters
/// at the ends lean outward instead of standing upright.
///
/// SwiftUI has no stroke on text, so the outline is the same glyph drawn eight
/// times around a small circle in the stroke colour with the fill on top. At a
/// one-point stroke this reads as a clean outline; pushed much thicker it starts
/// to look blobby at the corners, which is the limit of the trick.
struct ArcText: View {

    let string: String
    let font: UIFont
    let fill: Color
    let stroke: Color
    let strokeWidth: CGFloat
    /// Total sweep from the first letter to the last. `.zero` is a flat line.
    let bend: Angle
    let tracking: CGFloat
    /// 0 turns the drop shadow off — right for lettering that sits on paper
    /// rather than on stone.
    let shadowOpacity: Double

    init(_ string: String,
         font: UIFont,
         fill: Color,
         stroke: Color,
         strokeWidth: CGFloat,
         bend: Angle,
         tracking: CGFloat = 0,
         shadowOpacity: Double = 0.30) {
        self.string = string
        self.font = font
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.bend = bend
        self.tracking = tracking
        self.shadowOpacity = shadowOpacity
    }

    /// Each letter with the distance from the start of the word to its centre,
    /// measured in the real font so the spacing matches a normal line of type.
    private var placed: [(index: Int, character: String, centre: CGFloat)] {
        var running: CGFloat = 0
        var out: [(Int, String, CGFloat)] = []
        for (index, character) in string.enumerated() {
            let glyph = String(character)
            let width = (glyph as NSString).size(withAttributes: [.font: font]).width
            out.append((index, glyph, running + width / 2))
            running += width + tracking
        }
        return out
    }

    private var totalWidth: CGFloat {
        let widths = string.map {
            (String($0) as NSString).size(withAttributes: [.font: font]).width
        }
        return widths.reduce(0, +) + tracking * CGFloat(max(string.count - 1, 0))
    }

    /// Radius that spreads the word over exactly `bend` degrees. A flat line is
    /// the same thing with an infinite radius, which the maths below handles by
    /// leaving every angle at zero.
    private var radius: CGFloat {
        let sweep = abs(bend.radians)
        guard sweep > 0.0001 else { return .infinity }
        return totalWidth / sweep
    }

    /// How far the last letter drops below the first. Reserved in the frame so
    /// the arc is not clipped and stays centred on whatever positions it.
    private var sag: CGFloat {
        guard radius.isFinite else { return 0 }
        return radius * (1 - cos(bend.radians / 2))
    }

    var body: some View {
        ZStack {
            ForEach(placed, id: \.index) { item in
                let angle = radius.isFinite
                    ? (item.centre - totalWidth / 2) / radius
                    : 0
                let x = radius.isFinite ? radius * sin(angle) : item.centre - totalWidth / 2
                let y = radius.isFinite ? radius * (1 - cos(angle)) : 0

                glyph(item.character)
                    .rotationEffect(.radians(angle))
                    .offset(x: x, y: y - sag / 2)
            }
        }
        .frame(width: totalWidth, height: font.lineHeight + sag)
    }

    @ViewBuilder
    private func glyph(_ character: String) -> some View {
        ZStack {
            ForEach(Array(Self.ring.enumerated()), id: \.offset) { _, point in
                Text(character)
                    .foregroundStyle(stroke)
                    .offset(x: point.0 * strokeWidth, y: point.1 * strokeWidth)
            }
            Text(character).foregroundStyle(fill)
        }
        .font(Font(font))
        // Just enough to lift the letters off the stone. The design's shadow is
        // a hint of depth, not a glow.
        .shadow(color: stroke.opacity(shadowOpacity), radius: strokeWidth, x: 0, y: strokeWidth * 1.5)
    }

    private static let ring: [(CGFloat, CGFloat)] = [
        (-1, -1), (0, -1), (1, -1),
        (-1,  0),          (1,  0),
        (-1,  1), (0,  1), (1,  1)
    ]
}
