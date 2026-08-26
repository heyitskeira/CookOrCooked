//
//  StationChrome.swift
//  Cooked
//
//  The furniture every illustrated station page wears: the header bar across
//  the top, the back signpost, and the help block. Same art and the same
//  Figma-measured positions on all of them, so they live here rather than
//  being retyped per station — the chopping page had the only copy until the
//  bowl station needed the identical three.
//
//  Positions are in the shared artboard space (see `StationCanvas`).
//

import SwiftUI

// MARK: - Header bar

/// The bar across the top: what this station is doing right now, filling from
/// the left as the action progresses.
///
/// No top-level rect for the bar itself came with the art (only the badge
/// embedded in it, given as an offset relative to the bar's own corner:
/// (-12, -12), 61x54). The bar's own box is inferred from the gap between the
/// back button and the timer in the reference screenshots.
struct StationHeaderBar: View {

    let title: String
    /// 0...1. Stations with nothing in flight (a bowl waiting to be chosen at)
    /// simply leave this at 0 and the bar reads as a plain label.
    var progress: CGFloat = 0
    /// The little picture tucked into the bar's top-left corner, or nil for a
    /// bar with no badge.
    ///
    /// Used to be hardcoded to the strawberry bucket, back when the chopping
    /// page was the only caller — which meant the bowl station wore a punnet of
    /// strawberries no matter what was actually in the bowl.
    var badgeArt: String? = nil
    let geo: GeometryProxy

    static let frame = CGRect(x: 170, y: -56, width: 560, height: 52)

    var body: some View {
        ZStack {
            Capsule().fill(StationPalette.cream)

            GeometryReader { barGeo in
                let fill = barGeo.size.width * progress

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(StationPalette.ink)
                        .frame(width: fill)
                        .animation(.easeOut(duration: 0.15), value: progress)

                    label(StationPalette.ink)

                    // The same words again in cream, shown only where the fill
                    // has swept past them. Without this the title is ink on
                    // ink wherever the bar has reached — a station that fills
                    // right up (a finished chop) lost its title completely.
                    label(StationPalette.cream)
                        .mask(alignment: .leading) { Rectangle().frame(width: fill) }
                        .animation(.easeOut(duration: 0.15), value: progress)
                }
                .frame(width: barGeo.size.width, height: barGeo.size.height)
            }
        }
        .overlay(Capsule().stroke(StationPalette.ink.opacity(0.4), lineWidth: 1.5))
        .figmaPlaced(Self.frame, in: geo)
        .overlay(alignment: .topLeading) {
            if let badgeArt, let art = FoodArt.art(badgeArt) {
                Image(uiImage: art).resizable().scaledToFit()
                    .figmaPlaced(Self.frame.minX - 12, Self.frame.minY - 12, 61, 54, in: geo)
            }
        }
    }

    private func label(_ colour: Color) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(colour)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Corner buttons

/// The signpost that leaves the station.
///
/// The art brief said (132, 52) for this, which matched neither the source
/// image's aspect ratio nor what actually needed showing. The source PNG
/// (156x234) is a square arrow-plank with a wooden post rising above it for
/// hanging — fitting the *whole* image (post included) into any small box
/// leaves the plank, the only part with the arrow on it, occupying the bottom
/// third. This scales to width, then crops to a square anchored at the bottom,
/// keeping the plank and dropping the post. `help.png` needs no such
/// treatment: it has no post to begin with.
struct StationBackButton: View {

    let geo: GeometryProxy
    var action: () -> Void

    private static let side: CGFloat = 52

    var body: some View {
        Button(action: action) {
            Group {
                if let art = FoodArt.art("station-back-button") {
                    // The crop has to work off whatever size figmaPlaced
                    // actually allocates (device-scaled), not the raw
                    // design-space `side` — this GeometryReader is that size.
                    GeometryReader { box in
                        Image(uiImage: art)
                            .resizable()
                            .frame(width: box.size.width, height: box.size.width * (234.0 / 156.0))
                            .frame(width: box.size.width, height: box.size.height, alignment: .bottom)
                            .clipped()
                    }
                } else {
                    Image(systemName: "chevron.left").foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Leave the station")
        .figmaPlaced(49, -56, Self.side, Self.side, in: geo)
    }
}

/// The kitchen clock, mirrored into the station page.
///
/// The map's own HUD clock is hidden while a chef is heads-down at a counter,
/// so without this there is nothing telling them the round is running out while
/// they stand there holding a button.
///
/// Position measured off the reference screenshots by matching
/// `hud-timer-clock` into them: centred at (830, -8), mirroring the back button
/// across the artboard. The box keeps the art's own 246x270 proportions so the
/// bells aren't squashed, and stops well short of the header bar's right edge
/// at x = 730.
struct StationTimer: View {

    /// Seconds left. Reads `KitchenSession.secondsRemaining`, which is
    /// host-aware — a solo game's snapshot never ticks.
    let secondsRemaining: TimeInterval
    let geo: GeometryProxy

    static let frame = CGRect(x: 790, y: -51, width: 78, height: 86)

    /// The face is drawn empty and the time goes on top of it. It sits below
    /// the middle of the image because the bells take up the top third.
    private static let faceOffset: CGFloat = 9

    private var isUrgent: Bool { secondsRemaining < Recipe.timeLimit * 0.1 }

    private var clockText: String {
        let whole = max(0, Int(secondsRemaining))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }

    var body: some View {
        ZStack {
            if let art = FoodArt.art("hud-timer-clock") {
                Image(uiImage: art).resizable().scaledToFit()
                    .figmaPlaced(Self.frame, in: geo)
            }

            Text(clockText)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
                // The last tenth of the round goes red — the same threshold
                // `KitchenScene.refreshHUD` uses, so the two clocks can never
                // disagree about when to start worrying.
                .foregroundStyle(isUrgent ? Color(red: 0.72, green: 0.20, blue: 0.16)
                                          : StationPalette.ink)
                .figmaPlaced(Self.frame.minX,
                             Self.frame.minY + Self.faceOffset,
                             Self.frame.width, Self.frame.height, in: geo)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Time remaining \(clockText)")
    }
}

/// Re-shows whatever instruction this station last gave.
struct StationHelpButton: View {

    let geo: GeometryProxy
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let art = FoodArt.art("help") {
                    Image(uiImage: art).resizable().scaledToFit()
                } else {
                    Image(systemName: "questionmark").foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How this station works")
        .figmaPlaced(23, 329, 52.5, 52, in: geo)
    }
}

// MARK: - Shared colours

/// The two colours the station pages paint their own controls with, matched to
/// the artwork rather than to `AppTheme` (which is the menu/UI palette).
enum StationPalette {
    static let cream = Color(red: 0.98, green: 0.95, blue: 0.89)
    static let ink = Color(red: 0.36, green: 0.20, blue: 0.14)
}

// MARK: - Station background

/// Forest backdrop + the mossy stone counter both stations stand at.
struct StationGround: View {

    let geo: GeometryProxy

    var body: some View {
        ZStack {
            Group {
                if let art = FoodArt.art("forest-background") {
                    Image(uiImage: art).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(red: 0.24, green: 0.32, blue: 0.26),
                                            Color(red: 0.14, green: 0.20, blue: 0.16)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()

            if let art = FoodArt.art("stone-slab") {
                Image(uiImage: art).resizable().scaledToFit()
                    .figmaPlaced(96, 25, 682, 381, in: geo)
            }
        }
    }
}

// MARK: - The chef's own hands

/// The paws along the bottom-right, holding whatever this chef is carrying.
///
/// Both slots draw straight from the inventory by id, so a station never has
/// to know which ingredient or tool it might be looking at — the day an
/// imageset lands for a new one it just appears.
struct StationHands: View {

    @ObservedObject var inventory: PlayerInventory
    let geo: GeometryProxy
    /// Frames the art direction measured for particular items, where a station
    /// was given them. A pan hangs from a paw differently than a block of
    /// butter does, and a bowl of melted butter differently again. Anything
    /// not listed uses the shared slot below.
    var frames: [String: CGRect] = [:]
    /// Whose paws these are.
    ///
    /// Was the single `hands` drawing, which meant every chef in the room looked
    /// down at the same pair — you could be a fox on the lobby card and a
    /// stranger's paws at the counter. `KitchenSession.localPawAsset` resolves
    /// this through `ChefCast`, so it agrees with the card and with the map.
    ///
    /// Defaulted so the SwiftUI previews, which have no session, still draw
    /// something.
    var pawAsset: String = ChefCast.Animal.squirrel.paw

    private static let ingredientSlot = CGRect(x: 663, y: 290, width: 134, height: 104)
    private static let utensilSlot = CGRect(x: 773, y: 276, width: 104, height: 131)

    var body: some View {
        ZStack {
            // Falls back to the old shared pair if an animal's paws are missing
            // from the catalogue, rather than leaving the corner empty.
            if let art = FoodArt.art(pawAsset) ?? FoodArt.art("hands") {
                Image(uiImage: art).resizable().scaledToFit()
                    // y shifted +13 from the brief: that box stopped 13 units
                    // short of the artboard's true bottom edge, leaving a gap
                    // under the paws even with bottom-alignment. The whole
                    // cluster (this and the two below) moved by the same
                    // amount, so their positions relative to each other are
                    // untouched — only where the group sits as a whole.
                    .figmaPlaced(687, 312, 171, 120, alignment: .bottom, in: geo)
            }

            if let held = inventory.ingredient, let art = FoodArt.art(held.id) {
                Image(uiImage: art).resizable().scaledToFit()
                    .figmaPlaced(frames[held.id] ?? Self.ingredientSlot,
                                 alignment: .bottom, in: geo)
            }

            if let tool = inventory.utensil, let art = FoodArt.art(tool.id) {
                Image(uiImage: art).resizable().scaledToFit()
                    .figmaPlaced(frames[tool.id] ?? Self.utensilSlot,
                                 alignment: .bottom, in: geo)
            }
        }
    }
}

// MARK: - Instruction art

extension ActionMotion {
    /// The instruction overlay that teaches this motion.
    ///
    /// Keyed by motion, not by action: every sifting action gets the sifting
    /// instruction, including ones the recipe hasn't invented yet. Throwing
    /// away borrows the plain "hold" icon — the bin has its own aiming screen
    /// and never shows this.
    ///
    /// The art is the cut-out set (CH5 "instruction assets only"), not the
    /// full-screen compositions next to it: those carry an opaque pale
    /// backing, so laying one over a station covered the station. Two of them
    /// are named for an action rather than a gesture and are filed here by
    /// what they actually draw — "macerate strawberries" is a plain hold
    /// (the word is even lettered into it), and "crack eggs" is the
    /// flick-then-pull-apart strip.
    /// What to do, in words — the line that used to sit on a capsule over the
    /// station while the chef worked. It belongs with the instruction art
    /// instead: once an action is under way the animation says it's happening,
    /// and a permanent label just covers the food.
    ///
    /// Shaking and flicking are impossible without an accelerometer, so on a
    /// simulator this reads out the touch fallback the minigame actually
    /// listens for rather than an instruction nothing can follow.
    var instruction: String {
        switch self {
        case .chop:      return "Tap to chop"
        case .whisk:     return "Swipe in circles"
        case .sift:      return StationMinigame.hasMotionSensor ? "Shake to sift" : "Hold to sift"
        case .breakEgg:  return StationMinigame.hasMotionSensor ? "Flick down to crack" : "Tap to crack"
        case .mix:       return "Swipe in circles, anticlockwise"
        case .melt:      return "Blow"
        case .hold:      return "Hold to work"
        case .throwAway: return "Throw it away"
        }
    }

    /// Whether that glyph has to be flipped to point the right way round.
    ///
    /// The finger-circle art is drawn clockwise, which is the way whisking
    /// happens to be illustrated and the way mixing must *not* go. Mirroring it
    /// is the only way to show the required direction with the art that exists;
    /// a properly drawn anticlockwise glyph would be better, and this goes away
    /// the day one is exported.
    var instructionArtIsMirrored: Bool {
        self == .mix
    }

    var instructionArtName: String {
        switch self {
        case .chop:      return "overlay-chop"
        case .whisk:     return "overlay-whisk"
        // Mixing borrows whisking's glyph rather than using `overlay-mix`.
        // That one draws the *phone* being swirled round like a spoon — a
        // guess made before the station was built, and the mix-dough reference
        // frames settle it: they show a finger circling inside the bowl, the
        // same gesture whisking uses. `overlay-mix` is now art for a mechanic
        // that doesn't exist, so it is left unused rather than shown.
        case .mix:       return "overlay-whisk"
        case .sift:      return "overlay-sift"
        case .melt:      return "overlay-melt"
        case .breakEgg:  return "overlay-break-egg"
        case .hold:      return "overlay-hold"
        case .throwAway: return "overlay-hold"
        }
    }
}

/// How to do this action: the line art for the motion, over the dimmed
/// station.
///
/// Drawn as a template tinted to the station cream. The art is dark line work
/// on transparency, which would all but vanish into a dimmed forest at its own
/// colour — and because it really is cut out, tinting reaches the strokes and
/// nothing else. (The first version of this used the full-screen overlay art
/// instead, which is only transparent at the very edges: tinting that flooded
/// the whole screen cream.)
struct StationInstructionOverlay: View {

    let motion: ActionMotion
    var caption: String?
    var onTap: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.5)

                VStack(spacing: 14) {
                    instruction
                        // Capped rather than padded: these are tight cut-outs
                        // of wildly different shapes — the egg is a wide strip,
                        // the hold is portrait — and a box both fit inside
                        // keeps them the same visual weight.
                        .frame(maxWidth: geo.size.width * 0.5,
                               maxHeight: geo.size.height * 0.46)

                    VStack(spacing: 2) {
                        Text(motion.instruction)
                            .font(.system(size: 21, weight: .heavy, design: .rounded))
                            .foregroundStyle(StationPalette.cream)
                        if let caption {
                            Text(caption)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(StationPalette.cream.opacity(0.75))
                        }
                    }
                    .multilineTextAlignment(.center)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .transition(.opacity)
    }

    private var instruction: some View {
        Group {
            if let art = FoodArt.art(motion.instructionArtName) {
                Image(uiImage: art.withRenderingMode(.alwaysTemplate))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(StationPalette.cream)
                    // Flipped, not rotated: rotating a circular arrow moves
                    // where it starts without changing which way it goes.
                    .scaleEffect(x: motion.instructionArtIsMirrored ? -1 : 1, y: 1)
            } else {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(StationPalette.cream)
            }
        }
    }
}

// MARK: - Food out of its container

extension FoodArt {

    /// How a food looks tipped out of whatever carries it — sugar out of the
    /// sack, butter out of its wrapper, melted butter out of its bowl.
    ///
    /// A station page draws its own bowl and its own pan, so the carried
    /// artwork is wrong inside them: every prep's picture is *a bowl with the
    /// prep in it*, which would put a bowl inside the bowl. Falls back to the
    /// carried look, which is right for anything that has no separate loose
    /// version (a whole egg looks the same wherever it sits).
    ///
    /// Two ways in, because the art arrived in two vocabularies: the id-shaped
    /// name first (`meltedButter-loose`), then the catalogue's descriptive
    /// name. Nothing here is derivable — "sugar loose" being called
    /// `ingredient-sugar-pile` is a fact about the art, not a rule — so it is
    /// a table rather than a convention.
    static func looseArt(_ id: String) -> UIImage? {
        if let art = art("\(id)-loose") { return art }
        if let descriptive = looseNames[id], let art = art(descriptive) { return art }
        return art(id)
    }

    private static let looseNames: [String: String] = [
        "sugar":         "ingredient-sugar-pile",
        "flour":         "ingredient-flour-pile",
        "cream":         "prepared-cream-unwhipped",
        "butter":        "ingredient-butter-unwrapped",
        "crackedEgg":    "ingredient-egg-yolk",
        "siftedFlour":   "prepared-flour-sifted",
        "whippedCream":  "prepared-cream-whipped"
    ]
}
