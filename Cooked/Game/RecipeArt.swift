//
//  RecipeArt.swift
//  Cooked
//
//  Where the recipe book's real artwork meets the layout that positions it.
//
//  The book is one big illustration (`book-recipe-open`, 1341×804) with the
//  step rows, the title and the instruction panels drawn as separate pieces
//  that sit *on* it. Nothing here uses absolute point sizes, because the art
//  was authored at one size and ships to phones of many. Instead every piece
//  is described as a fraction of the book image, and `BookCanvas` scales the
//  whole arrangement together. Move the book, and the rows move with it.
//
//  The fractions below were measured off the shipped mockups
//  (Asset-Final/Screens/07-recipe and /12-recipe-step-details) rather than
//  eyeballed, so the built screen matches what the artist drew. `#if DEBUG`
//  checks at the bottom shout if the artwork is re-exported at a size that no
//  longer agrees with the numbers.
//
//  Memory note: every image here is referenced by *name* and drawn with
//  SwiftUI's `Image(_:)`. That hands decoding and eviction to the asset
//  catalog, which can purge under pressure. Loading these through
//  `UIImage(named:)` into a dictionary would pin ~30 full-size bitmaps in
//  memory for the life of the process — see `FoodArt.art` for the one place
//  that still needs UIKit, and what it caches instead.
//

import SwiftUI

// MARK: - A rectangle in "book space"

/// A rectangle expressed as fractions of the open-book artwork, with the
/// origin at the book image's top-left and 1.0 meaning its full width/height.
///
/// Fractions rather than points so one set of numbers describes the layout on
/// every screen size — `BookLayout` turns them into real geometry once the
/// book's drawn size is known.
nonisolated struct BookRect: Sendable {

    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat

    /// Same rectangle, given by where its middle sits rather than its corner.
    /// The step-detail card is positioned this way because the cards are
    /// different heights and all of them hang from the same centre line.
    static func centred(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> BookRect {
        BookRect(x: x - w / 2, y: y - h / 2, w: w, h: h)
    }
}

// MARK: - Asset names and measurements

// Deliberately *not* `nonisolated`, unlike `BookRect` and `BookLayout` below.
// `rowRect` reads `RecipeBook.pageBreak` to decide which page a step sits on,
// and `RecipeBook` is main-actor isolated by the target's default. Everything
// that asks for these measurements is a view, so main-actor costs nothing.
enum BookArt {

    // MARK: Names
    //
    // These strings must match imageset folder names in Assets.xcassets. The
    // numbered ones are keyed on `BookStep.number`, so the book's data and its
    // artwork line up with no lookup table in between — step 7 draws
    // `step-row-07`, always.

    static let frame  = "book-recipe-open"
    static let title  = "book-title-strawberry-shortcake"
    static let banner = "header-todays-order"

    /// The tappable line on the recipe spread: number, icon and label, drawn
    /// as one piece.
    static func row(_ step: Int) -> String { String(format: "step-row-%02d", step) }

    /// The "STEP n: <title>" plaque on the left page of the detail screen.
    static func card(_ step: Int) -> String { String(format: "step-card-%02d", step) }

    /// The right page of the detail screen: what the step needs and where it
    /// has to happen.
    static func instructions(_ step: Int) -> String {
        String(format: "step-instructions-%02d", step)
    }

    // MARK: The book itself

    /// Native size of `book-recipe-open`. Everything else is a fraction of it.
    ///
    /// These two are `nonisolated` where the rest of `BookArt` is not, because
    /// `BookLayout` — which is a plain value type and has no business being
    /// tied to the main actor — needs the aspect ratio to do its arithmetic.
    /// Both are immutable and `Sendable`, so there is nothing to race on.
    nonisolated static let frameSize = CGSize(width: 1341, height: 804)

    nonisolated static var aspect: CGFloat { frameSize.width / frameSize.height }

    // MARK: Recipe spread (screen 07)

    /// One step row. Same size on both pages; only the column differs.
    static let rowSize = CGSize(width: 0.3275, height: 0.0743)

    /// Left edge of the two columns of rows.
    static let rowColumnX: (left: CGFloat, right: CGFloat) = (0.1452, 0.5367)

    /// Top edge of the first row in each column. The right page starts higher
    /// because the left page gives up its top to the recipe's name.
    static let rowFirstY: (left: CGFloat, right: CGFloat) = (0.2748, 0.1825)

    /// Centre-to-centre distance between consecutive rows.
    static let rowPitch: CGFloat = 0.08647

    /// Where "STRAWBERRY SHORTCAKE" sits on the left page.
    static let titleRect = BookRect(x: 0.1575, y: 0.1088, w: 0.2692, h: 0.1926)

    /// The "tap a step for more instructions" hint under the last row.
    static let hintRect = BookRect(x: 0.5367, y: 0.6450, w: 0.3275, h: 0.0620)

    /// The frame of the row for `step`, which must be 1...11.
    static func rowRect(_ step: Int) -> BookRect {
        let onLeft = step <= RecipeBook.pageBreak
        let index  = onLeft ? step - 1 : step - RecipeBook.pageBreak - 1
        return BookRect(x: onLeft ? rowColumnX.left  : rowColumnX.right,
                        y: (onLeft ? rowFirstY.left : rowFirstY.right)
                            + CGFloat(index) * rowPitch,
                        w: rowSize.width,
                        h: rowSize.height)
    }

    // MARK: Step detail (screen 12)

    /// Where the instruction panel sits for most steps: 438×467 of artwork on
    /// the right-hand page.
    static let instructionsRectDefault = BookRect(x: 0.5378, y: 0.1825,
                                                  w: 0.3266, h: 0.5808)

    /// The two steps whose panel is not the standard size, because they take
    /// more ingredients than the others and the artist drew a bigger panel:
    /// step 6 (flour + butter + egg + sugar) at 486×546, step 10 (base +
    /// cream + strawberries) at 482×466.
    ///
    /// They don't share the standard panel's centre *or* its edges, so each
    /// carries its own measured rectangle rather than being derived. Scaling
    /// the standard rect to fit them instead would inset step 6 by 5% and
    /// squash step 10 by 9% — both visibly off the printed page.
    private static let instructionsRectOverrides: [Int: BookRect] = [
        6:  BookRect(x: 0.5066, y: 0.1156, w: 0.3624, h: 0.6791),
        10: BookRect(x: 0.5066, y: 0.1825, w: 0.3594, h: 0.5796)
    ]

    /// Where the instruction panel for `step` belongs.
    static func instructionsRect(_ step: Int) -> BookRect {
        instructionsRectOverrides[step] ?? instructionsRectDefault
    }

    /// Native pixel size of each `step-instructions-NN`, checked against the
    /// rectangles above in debug builds.
    static let instructionsPixelSize: [Int: CGSize] = [
        6:  CGSize(width: 486, height: 546),
        10: CGSize(width: 482, height: 466)
    ]

    /// The step cards are all different heights — "Cut Strawberries" is two
    /// lines, "Sift Flour" is one — and the art hangs them from a shared
    /// centre rather than a shared top edge.
    static let cardCentre = CGPoint(x: 0.3010, y: 0.4775)

    /// Native pixel size of each `step-card-NN`, used to keep the card's own
    /// proportions when it is scaled onto the page. Kept as data rather than
    /// read back off the image so laying out the page never has to decode one.
    static let cardPixelSize: [Int: CGSize] = [
        1:  CGSize(width: 407, height: 241),
        2:  CGSize(width: 409, height: 314),
        3:  CGSize(width: 406, height: 188),
        4:  CGSize(width: 406, height: 188),
        5:  CGSize(width: 406, height: 188),
        6:  CGSize(width: 406, height: 265),
        7:  CGSize(width: 406, height: 188),
        8:  CGSize(width: 406, height: 188),
        9:  CGSize(width: 412, height: 253),
        10: CGSize(width: 407, height: 309),
        11: CGSize(width: 412, height: 253)
    ]

    /// The frame of the step card for `step`, centred on `cardCentre`.
    static func cardRect(_ step: Int) -> BookRect {
        let native = cardPixelSize[step] ?? CGSize(width: 406, height: 188)
        return .centred(x: cardCentre.x, y: cardCentre.y,
                        w: native.width  / frameSize.width,
                        h: native.height / frameSize.height)
    }

    // MARK: Screen furniture
    //
    // Anchored to the screen rather than the book, so they stay put no matter
    // how the book is scaled to fit.

    /// How much of the screen's width "TODAY'S ORDER" spans. It hangs from the
    /// top edge, centred, and its height follows from `bannerAspect`.
    static let bannerWidthFraction: CGFloat = 0.5641

    // MARK: The hanging back sign
    //
    // `btn-back` is a plaque on a tree trunk, and the trunk is meant to run up
    // out of frame — the sign hangs into the scene rather than sitting in the
    // corner. So the art is positioned by where its *plaque* should land, and
    // the trunk takes care of itself above that.
    //
    // Measured identically on all three mockups (recipe before start, recipe
    // in game, step detail), so the sign stays put while the book scales.

    static let backSign = "btn-back"

    /// Native proportions of `btn-back` (104×268).
    static let backSignAspect: CGFloat = 104.0 / 268.0

    /// The sign's height as a fraction of its container's height.
    ///
    /// Sized off the height, not the width, because the width fraction the
    /// mockup implies is only right at the mockup's own aspect ratio — on a
    /// wider or narrower screen it would grow or shrink for no reason. Height
    /// gives the same 50pt sign the artist drew, on any landscape device.
    static let backSignHeight: CGFloat = 0.3333

    /// Where the plaque's top edge belongs, as a fraction of container height.
    static let backSignPlaqueTop: CGFloat = 0.0672

    /// Distance from the leading edge, in points.
    ///
    /// A fixed inset rather than a fraction on purpose. The mockups are drawn
    /// full-bleed and put the sign 48pt from the screen's edge — which on a
    /// landscape iPhone is *underneath* the sensor housing, where a button
    /// cannot be tapped. So the sign hangs inside the safe area instead.
    ///
    /// Set by eye on a device: at 6pt the sign read as jammed against the
    /// edge, because the safe-area inset it sits behind is a rounded corner
    /// rather than a straight one, and the corner eats the visual margin.
    static let backSignLeadingInset: CGFloat = 22

    /// How far down the artwork the plaque starts. Everything above this is
    /// trunk, which is why the image is hung above the top of the screen.
    ///
    /// `nonisolated` because `BackSignPlaque` reads it, and `Shape.path(in:)`
    /// is a nonisolated requirement.
    nonisolated static let backSignPlaqueStart: CGFloat = 165.0 / 268.0

    // MARK: The guest's page
    //
    // Non-head-chefs get the book open at a blank spread: one line telling
    // them what they are waiting for, and ruled lines where the recipe would
    // be. Same grid of rules on both pages — the left page simply gives up its
    // first two lines to the message.

    /// The waiting message, on the left page.
    static let guestMessageRect = BookRect(x: 0.1597, y: 0.1830,
                                           w: 0.2998, h: 0.1550)

    /// Centre of the first ruled line, and the gap to the next.
    static let ruleFirstY: CGFloat = 0.2361
    static let rulePitch: CGFloat = 0.0717

    /// How many lines each page is ruled for. The left page starts lower
    /// because the message sits on the first two.
    static let ruleCount = 8
    static let ruleLeftFirstIndex = 2

    /// Left edge and width of the rules on each page.
    static let ruleX: (left: CGFloat, right: CGFloat) = (0.1597, 0.5535)
    static let ruleWidth: (left: CGFloat, right: CGFloat) = (0.2998, 0.2971)

    /// Dot size as a fraction of the book's height, and dot spacing as a
    /// fraction of its width, so the rules stay dotted rather than turning
    /// into solid lines on a small screen.
    static let ruleDotSize: CGFloat = 0.0045
    static let ruleDotPitch: CGFloat = 0.0081

    /// Centre line of ruled row `index`, counting from zero at the top.
    static func ruleY(_ index: Int) -> CGFloat {
        ruleFirstY + CGFloat(index) * rulePitch
    }

    /// Native proportions of `header-todays-order` (982×162).
    ///
    /// A `.resizable()` image has no size of its own, so giving the banner
    /// only a width would leave its height up to whatever the stack proposed —
    /// which in a `VStack` is "as much as is going", and the banner would eat
    /// the book. The ratio pins it.
    static let bannerAspect: CGFloat = 982.0 / 162.0
}

// MARK: - Turning fractions into geometry

/// Where the book image ended up on screen, and the arithmetic to place
/// anything else relative to it.
nonisolated struct BookLayout: Sendable, Equatable {

    /// The book image's frame in the container's coordinate space.
    let rect: CGRect

    /// The book drawn as large as it can be inside `available` without
    /// distorting it — the same result as `.scaledToFit()`, computed up front
    /// so the pieces on top can be positioned against it.
    init(fitting available: CGSize) {
        let w = min(available.width, available.height * BookArt.aspect)
        let h = w / BookArt.aspect
        rect = CGRect(x: (available.width  - w) / 2,
                      y: (available.height - h) / 2,
                      width: w, height: h)
    }

    /// Frame in container coordinates for a rectangle given in book space.
    func frame(_ r: BookRect) -> CGRect {
        CGRect(x: rect.minX + r.x * rect.width,
               y: rect.minY + r.y * rect.height,
               width:  r.w * rect.width,
               height: r.h * rect.height)
    }

    /// A length given as a fraction of the book's height, in points. For text
    /// drawn over the art, which has to shrink with it.
    func height(_ fraction: CGFloat) -> CGFloat { fraction * rect.height }
}

extension View {

    /// Place this view at a book-space rectangle.
    ///
    /// `.position` rather than an alignment guide because the pieces overlap
    /// the book freely and none of them should influence anyone else's layout.
    func placed(_ r: BookRect, in layout: BookLayout) -> some View {
        let f = layout.frame(r)
        return frame(width: f.width, height: f.height)
            .position(x: f.midX, y: f.midY)
    }
}

// MARK: - The book, and things drawn on it

/// The open book scaled to fit, with its contents laid out against it.
///
/// The closure is handed the finished `BookLayout`, so callers position their
/// pieces with `.placed(_:in:)` and never have to know the screen size.
struct BookCanvas<Content: View>: View {

    @ViewBuilder var content: (BookLayout) -> Content

    var body: some View {
        GeometryReader { geo in
            let layout = BookLayout(fitting: geo.size)

            ZStack(alignment: .topLeading) {
                Image(BookArt.frame)
                    .resizable()
                    .scaledToFit()
                    .frame(width: layout.rect.width, height: layout.rect.height)
                    .position(x: layout.rect.midX, y: layout.rect.midY)

                content(layout)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Debug checks
//
// The layout numbers are only right for the artwork they were measured
// against. If the book or the cards are re-exported at a different size the
// screen will drift quietly — everything still renders, just slightly wrong.
// These make it loud instead. Debug only: the point is to catch it in the
// simulator, not to spend a bundle lookup per launch in a shipping build.

#if DEBUG
extension BookArt {

    /// Every imageset the two recipe screens ask for by name.
    ///
    /// Driven off the steps themselves rather than a count, so an empty book
    /// asks for nothing instead of trapping on `1...0`.
    static var allNames: [String] {
        [frame, title, banner, backSign]
            + RecipeBook.steps.flatMap {
                [row($0.number), card($0.number), instructions($0.number)]
            }
    }

    /// Complains about missing imagesets and about artwork whose real size no
    /// longer matches the measurements above. Called from `RecipeBookView`.
    static func auditArtwork() {
        let missing = allNames.filter { UIImage(named: $0) == nil }
        if !missing.isEmpty {
            print("⚠️ BookArt: no imageset named " + missing.joined(separator: ", "))
        }

        if let book = UIImage(named: frame), book.size != frameSize {
            print("⚠️ BookArt: \(frame) is \(book.size) but the layout was "
                  + "measured against \(frameSize) — the rows will sit wrong.")
        }

        // `backSignAspect` and `backSignPlaqueStart` are both derived from
        // this exact size, so a re-export would hang the plaque in the wrong
        // place and move the tap target with it.
        let signSize = CGSize(width: 104, height: 268)
        if let sign = UIImage(named: backSign), sign.size != signSize {
            print("⚠️ BookArt: \(backSign) is \(sign.size), expected \(signSize) "
                  + "— backSignAspect and backSignPlaqueStart need remeasuring.")
        }

        for (step, expected) in cardPixelSize.sorted(by: { $0.key < $1.key }) {
            guard let art = UIImage(named: card(step)) else { continue }
            if art.size != expected {
                print("⚠️ BookArt: \(card(step)) is \(art.size), "
                      + "cardPixelSize says \(expected)")
            }
        }

        // The instruction panels are mostly one size with two exceptions, and
        // the exceptions are the whole reason `instructionsRect(_:)` exists.
        // If a re-export changes which steps are odd, this is where it shows.
        for step in RecipeBook.steps.map(\.number) {
            guard let art = UIImage(named: instructions(step)) else { continue }
            let expected = instructionsPixelSize[step]
                ?? CGSize(width: 438, height: 467)
            if art.size != expected {
                print("⚠️ BookArt: \(instructions(step)) is \(art.size), "
                      + "the layout expects \(expected) — "
                      + "add it to instructionsRectOverrides.")
            }
        }
    }
}
#endif
