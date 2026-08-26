//
//  RecipeBookView.swift
//  Cooked
//
//  Today's Order — the screen between the lobby and the kitchen.
//
//  Three screens live in this one file on purpose, because they are the same
//  book seen from different sides of the table:
//
//    • The head chef gets the written order and the START signpost. Only they
//      can open the kitchen, and only they can read a step's instructions.
//    • Everyone else gets a closed book: "waiting for head chef reading the
//      order's recipe". That asymmetry is the point — the head chef has to
//      talk, and the kitchen has to listen.
//    • Tapping a step turns the page to `StepDetailView`, which is the same
//      book showing one step's card and what it needs.
//
//  Nothing here is on a clock. `KitchenSession.beginCooking()` is what starts
//  the timer, and it is wired to the signpost.
//
//  The artwork and every measurement that places it live in `RecipeArt.swift`.
//  Nothing in this file knows a pixel size; it asks `BookLayout` where things
//  go, so the same code draws the book correctly on any screen.
//

import SwiftUI

struct RecipeBookView: View {

    @ObservedObject var session: KitchenSession

    /// Previews and on-device testing only — forces the head chef or guest
    /// side of the screen without needing a second device in the room.
    var headChefOverride: Bool?

    /// Leaving kills the kitchen for everyone, so it asks first.
    @State private var confirmLeave = false

    /// The step whose page is open, if any. Held here rather than inside the
    /// spread because the banner and the START signpost have to get out of the
    /// way while a step is being read.
    @State private var openStep: BookStep?

    private var isHeadChef: Bool { headChefOverride ?? session.isHeadChef }

    // MARK: Body

    var body: some View {
        ZStack {
            backdrop

            if let step = openStep {
                StepDetailView(step: step)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94)),
                        removal:   .opacity.combined(with: .scale(scale: 0.98))))
            } else {
                spreadPage
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal:   .opacity.combined(with: .scale(scale: 0.94))))
            }

            corners

            // The host can vanish while the book is open — and this is the
            // longest pre-game pause there is, so it will happen. Without
            // this the screen just says "head chef is reading…" forever.
            //
            // The clock has not started yet, so nothing is being lost while
            // we wait; the freeze still matters because the head chef is
            // the host, and without them nobody can press START.
            // Closed before frozen, for the same reason as in the kitchen:
            // only one of the two has a way out on it.
            if let closed = closedReason {
                KitchenClosedOverlay(reason: closed, onDone: leaveKitchen)
            } else if session.isFrozen {
                PausedOverlay(session: session, onLeave: leaveKitchen)
            } else if let player = session.localPlayer, !player.isConnected {
                statusBanner("Reconnecting…")
            }
        }
        // Note: only the backdrop ignores the safe area. The phone is
        // landscape-only, so a full-bleed ZStack would put the back button
        // under the sensor housing and START under the home indicator.
        .confirmationDialog("Leave this kitchen?",
                            isPresented: $confirmLeave, titleVisibility: .visible) {
            // The host says goodbye properly. Without it the guests can't tell
            // "walked out" from "phone died" and sit through the full ninety
            // second freeze waiting for someone who is already on the menu.
            Button("Leave kitchen", role: .destructive) {
                if session.isHost { session.closeKitchen() } else { session.leave() }
            }
            Button("Keep cooking", role: .cancel) { }
        } message: {
            Text(session.isHeadChef
                 ? "You're the head chef — leaving closes the kitchen for everyone."
                 : "You'll drop out of this order.")
        }
        .onAppear(perform: auditBook)
        // Only the head chef can read a step. If that moves — host migration,
        // or a changed override in a preview — a guest would otherwise be left
        // stranded on a page they are no longer allowed to be on, with the
        // spread behind it showing the waiting message.
        .onChange(of: isHeadChef) { _, chef in
            if !chef { openStep = nil }
        }
    }

    /// The pre-start page: "TODAY'S ORDER" on its plank, with the open book
    /// below it.
    ///
    /// Stacked rather than overlaid. The banner is a solid wooden sign across
    /// nearly its whole height, so hanging it over the book would bury the top
    /// third of "STRAWBERRY SHORTCAKE". The mockup gives the sign its own band
    /// and lets the book take what's left, which is why the book reads smaller
    /// here than it does as the mid-match overlay.
    private var spreadPage: some View {
        GeometryReader { geo in
            let bannerWidth = geo.size.width * BookArt.bannerWidthFraction

            VStack(spacing: 6) {
                Image(BookArt.banner)
                    .resizable()
                    .scaledToFit()
                    .frame(width: bannerWidth,
                           height: bannerWidth / BookArt.bannerAspect)
                    .accessibilityLabel("Today's order")

                RecipeSpreadView(session: session,
                                 headChefOverride: headChefOverride,
                                 openStep: $openStep)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func closeStep() {
        withAnimation(.easeInOut(duration: 0.28)) { openStep = nil }
    }

    /// Out of the book and all the way back to the start screen. Mirrors
    /// `KitchenGameView.leaveKitchen` — the host says goodbye explicitly so
    /// nobody freezes waiting for a chef who has already left.
    private func leaveKitchen() {
        if session.isHost { session.closeKitchen() } else { session.leave() }
        NotificationCenter.default.post(name: .returnToStart, object: nil)
    }

    /// Why the kitchen closed, or nil while it is still open. Mirrors the same
    /// property on `KitchenGameView` — the book is the other place a player can
    /// be standing when the room goes away, and it needs the same way out.
    private var closedReason: String? {
        switch session.phase {
        case .hostLeft:
            return session.players.contains(where: { $0.isHost && !$0.isConnected })
                ? "The host didn't come back in time."
                : "The host closed this kitchen."
        case .rejected(let reason):
            return reason.message
        default:
            return nil
        }
    }

    private func statusBanner(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.cream)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(AppTheme.ink.opacity(0.85)))
                .padding(.bottom, 24)
        }
    }

    // MARK: Backdrop

    /// Framed and clipped rather than a bare `.scaledToFill()`. Fill mode can
    /// report a layout size larger than it was offered, which would grow the
    /// enclosing stack — invisible on a phone, where the art's proportions
    /// almost exactly match the screen, but a large overflow on an iPad.
    private var backdrop: some View {
        GeometryReader { geo in
            Image("woods-clearing-art")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }

    // MARK: Back button and signpost

    private var corners: some View {
        ZStack(alignment: .topLeading) {
            backButton

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    // While a step's page is open the only move is back to the
                    // list, so START is put away rather than left live
                    // underneath.
                    if openStep == nil { startControl }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    /// The hanging back sign, positioned by where its plaque should land.
    ///
    /// The artwork is a plaque on a trunk, and the trunk is drawn running up
    /// out of the frame — so the image is hung above the top of the container
    /// and clipped there, exactly as the mockups show it. Only the plaque is
    /// tappable; the trunk is scenery.
    private var backButton: some View {
        GeometryReader { geo in
            let height = geo.size.height * BookArt.backSignHeight
            let width  = height * BookArt.backSignAspect

            Button {
                // From a step's page, back means "close the step". From the
                // list it means leaving, which takes the whole kitchen with
                // it — so only that one asks first.
                if openStep != nil { closeStep() } else { confirmLeave = true }
            } label: {
                Image(BookArt.backSign)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
                    .contentShape(BackSignPlaque())
            }
            .buttonStyle(.plain)
            .offset(x: BookArt.backSignLeadingInset,
                    y: geo.size.height * BookArt.backSignPlaqueTop
                        - height * BookArt.backSignPlaqueStart)
            .accessibilityLabel(openStep == nil ? "Leave kitchen"
                                                : "Back to the recipe")
        }
    }

    @ViewBuilder
    private var startControl: some View {
        if isHeadChef {
            Button {
                session.beginCooking()
            } label: {
                Text("START")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.cream)
                    .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 2)
                    .padding(.leading, 22)
                    .padding(.trailing, 30)
                    .padding(.vertical, 12)
                    .background(Signpost().fill(Color(red: 0.45, green: 0.31, blue: 0.19)))
                    .overlay(Signpost().stroke(Color(red: 0.28, green: 0.18, blue: 0.10),
                                               lineWidth: 4))
                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 10) {
                ProgressView().tint(AppTheme.cream)
                Text("Head chef is reading…")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.cream)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(.black.opacity(0.45)))
        }
    }

    // MARK: Debug audits

    private func auditBook() {
        #if DEBUG
        // The artwork half: imagesets that don't exist, or that were
        // re-exported at a size the layout wasn't measured against.
        BookArt.auditArtwork()

        // The book is the promise; the rules engine is the delivery. If a
        // step has no action behind it, players will hunt the map for
        // something that cannot happen — on a two-minute clock.
        let orphans = RecipeBook.stepsWithNoAction
        if !orphans.isEmpty {
            print("⚠️ RecipeBook: no action behind step(s) " +
                  orphans.map { "#\($0.number) \($0.title)" }.joined(separator: ", "))
        }
        // Same failure, one step further in: the action exists, but not at
        // the counter the page names. The chef walks to the wrong station
        // and finds the step isn't offered there.
        let misplaced = RecipeBook.stepsAtWrongStation
        if !misplaced.isEmpty {
            print("⚠️ RecipeBook: wrong station on " +
                  misplaced.map { "#\($0.step.number) \($0.step.title) " +
                                  "(book: \($0.step.station.displayName), " +
                                  "kitchen: \($0.actual.displayName))" }
                          .joined(separator: ", "))
        }
        // And the third copy of the same facts: the rules engine's own
        // table of recipes. All three have to name the same counter.
        let drifted = RecipeBook.recipesAtWrongStation
        if !drifted.isEmpty {
            print("⚠️ RecipeBook: rules engine has " +
                  drifted.map { "\($0.recipe.name) at \($0.recipe.station.displayName) " +
                                "(kitchen: \($0.actual.displayName))" }
                         .joined(separator: ", "))
        }
        #endif
    }
}

// MARK: - The book's pages, on their own
//
// Pulled out of RecipeBookView so it can be shown by itself — KitchenGameView
// wants the open pages as a reviewable mid-match overlay, without the
// backdrop, back button, or START signpost that only make sense on the
// pre-game screen. RecipeBookView uses this struct for its own book too, so
// there's exactly one place the pages are drawn, not two copies to keep in
// sync.
struct RecipeSpreadView: View {

    @ObservedObject var session: KitchenSession

    /// Previews and on-device testing only — see the same property on
    /// `RecipeBookView`.
    var headChefOverride: Bool?

    /// The step whose page is open. Owned by whoever presents the spread,
    /// because opening a step changes what else belongs on their screen.
    @Binding var openStep: BookStep?

    private var isHeadChef: Bool { headChefOverride ?? session.isHeadChef }

    var body: some View {
        BookCanvas { layout in
            if isHeadChef {
                Image(BookArt.title)
                    .resizable()
                    .scaledToFit()
                    .placed(BookArt.titleRect, in: layout)
                    .accessibilityLabel(RecipeBook.orderTitle)

                ForEach(RecipeBook.steps) { step in
                    stepRow(step, layout: layout)
                }

                hint(layout: layout)
            } else {
                waitingPage(layout: layout)
            }
        }
    }

    // MARK: A step

    /// One tappable line. The whole row is a single piece of artwork, so the
    /// button's job is only to place it, grow it under a finger, and hand the
    /// step back up.
    private func stepRow(_ step: BookStep, layout: BookLayout) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.28)) { openStep = step }
        } label: {
            Image(BookArt.row(step.number))
                .resizable()
                .scaledToFit()
        }
        .buttonStyle(StepRowButtonStyle())
        .placed(BookArt.rowRect(step.number), in: layout)
        .accessibilityLabel("Step \(step.number), \(step.title)")
        .accessibilityHint("Opens this step's instructions")
    }

    /// "☝ a step for more instructions" — the only text on the spread that
    /// isn't part of the artwork, because it belongs to the interaction rather
    /// than the recipe.
    private func hint(layout: BookLayout) -> some View {
        HStack(spacing: layout.height(0.012)) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: layout.height(0.038), weight: .semibold))
            Text("a step for more instructions")
                .font(.system(size: layout.height(0.036), weight: .semibold,
                              design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(AppTheme.ink.opacity(0.62))
        .placed(BookArt.hintRect, in: layout)
        .accessibilityHidden(true)
    }

    // MARK: Everyone else's page

    /// A blank spread: the message on the first two lines of the left page,
    /// and ruled lines everywhere the recipe would be. The rules are on one
    /// grid across both pages, so the message reads as written *on* the page
    /// rather than floating over it.
    @ViewBuilder
    private func waitingPage(layout: BookLayout) -> some View {
        Text("Wait for the head chef\nto explain the recipe")
            // The mockup's lettering is condensed; SF Rounded is not, so the
            // size is set to match the *width* the artist gave the line rather
            // than its cap height, which would overrun the page.
            .font(.system(size: layout.height(0.046), weight: .bold,
                          design: .rounded))
            .foregroundStyle(AppTheme.ink.opacity(0.82))
            .multilineTextAlignment(.leading)
            .lineSpacing(layout.height(0.018))
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .placed(BookArt.guestMessageRect, in: layout)

        // The left page gives its first lines to the message; the right page
        // is ruled all the way down.
        ForEach(BookArt.ruleLeftFirstIndex..<BookArt.ruleCount, id: \.self) { row in
            rule(row: row, onLeft: true, layout: layout)
        }
        ForEach(0..<BookArt.ruleCount, id: \.self) { row in
            rule(row: row, onLeft: false, layout: layout)
        }
    }

    private func rule(row: Int, onLeft: Bool, layout: BookLayout) -> some View {
        let dot = layout.height(BookArt.ruleDotSize)

        return DottedRule()
            .stroke(style: StrokeStyle(lineWidth: dot, lineCap: .round,
                                       dash: [0.01, layout.rect.width
                                                    * BookArt.ruleDotPitch]))
            .foregroundStyle(AppTheme.ink.opacity(0.55))
            .placed(BookRect(x: onLeft ? BookArt.ruleX.left : BookArt.ruleX.right,
                             y: BookArt.ruleY(row) - BookArt.ruleDotSize / 2,
                             w: onLeft ? BookArt.ruleWidth.left
                                       : BookArt.ruleWidth.right,
                             h: BookArt.ruleDotSize),
                    in: layout)
            .accessibilityHidden(true)
    }
}

// MARK: - One step, on its own page

/// The step-detail screen: the same open book, showing what this step is on
/// the left and what it takes on the right.
///
/// Both halves are single pieces of artwork, so this view is almost entirely
/// placement. Leaving is the presenter's job — on the pre-game screen the
/// corner sign already knows to close the step rather than leave the kitchen,
/// and mid-match the overlay's own button does it.
///
/// Deliberately *not* tap-to-dismiss. This is a page to be read, often while
/// the head chef reads it aloud, so a stray finger anywhere on it used to
/// throw the reader back to the list mid-sentence. Taps are swallowed rather
/// than ignored, so they don't reach whatever is behind the page either.
struct StepDetailView: View {

    let step: BookStep

    var body: some View {
        BookCanvas { layout in
            Image(BookArt.card(step.number))
                .resizable()
                .scaledToFit()
                .placed(BookArt.cardRect(step.number), in: layout)
                .accessibilityLabel("Step \(step.number): \(step.title)")

            Image(BookArt.instructions(step.number))
                .resizable()
                .scaledToFit()
                .placed(BookArt.instructionsRect(step.number), in: layout)
                .accessibilityLabel(requirementsDescription)
        }
        .contentShape(Rectangle())
        .onTapGesture { /* swallowed — only the back button leaves */ }
    }

    /// What the artwork says, for anyone who can't see it.
    private var requirementsDescription: String {
        // `FoodArt.name` capitalises each id on its own, which reads as
        // "requires Raw dough and Hot oven" mid-sentence. Only the first stays
        // capitalised.
        let inputs = step.inputs.enumerated().map { index, id in
            index == 0 ? FoodArt.name(id) : FoodArt.name(id).lowercased()
        }
        let needs = inputs.isEmpty ? "nothing" : inputs.joined(separator: " and ")
        let tool = step.utensil.map { ", using the \(FoodArt.name($0).lowercased())" } ?? ""
        return "This step requires \(needs)\(tool). "
             + "It must be completed at the \(step.stationLabel)."
    }
}

// MARK: - Press and hover feedback

/// Grows a step row when a finger is on it, and — on iPad with a pointer, or
/// the Mac — when one hovers over it.
///
/// The amounts are deliberately small. Rows sit about 14% of their own height
/// apart, so anything past roughly 1.12 makes a pressed row collide with its
/// neighbours instead of reading as lifted.
struct StepRowButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    /// A nested view because a `ButtonStyle` is a value type and cannot hold
    /// `@State` of its own, and hover is state. Named `RowBody` rather than
    /// `Body` so it can't be mistaken for `ButtonStyle`'s own associated type.
    private struct RowBody: View {

        let configuration: ButtonStyleConfiguration

        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(scale)
                .shadow(color: .black.opacity(lifted ? 0.28 : 0),
                        radius: lifted ? 10 : 0, x: 0, y: lifted ? 5 : 0)
                .animation(motion, value: scale)
                .onHover { hovering = $0 }
        }

        private var lifted: Bool { hovering || configuration.isPressed }

        private var scale: CGFloat {
            if configuration.isPressed { return 1.10 }
            return hovering ? 1.05 : 1.0
        }

        /// A spring reads as "picked up"; reduce-motion users get the size
        /// change without the bounce rather than no feedback at all.
        private var motion: Animation {
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.26, dampingFraction: 0.62)
        }
    }
}

// MARK: - Small shapes

/// A single ruled line, drawn dashed by the caller's stroke style.
private nonisolated struct DottedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// The tappable part of the hanging back sign: the plaque, not the trunk
/// above it. Without this the whole trunk — most of the artwork, and mostly
/// off-screen — would answer to a tap.
private nonisolated struct BackSignPlaque: Shape {
    func path(in rect: CGRect) -> Path {
        let top = rect.minY + rect.height * BookArt.backSignPlaqueStart
        return Path(CGRect(x: rect.minX, y: top,
                           width: rect.width, height: max(0, rect.maxY - top)))
    }
}

/// A wooden signpost: a rectangle with an arrowhead pointing right.
private nonisolated struct Signpost: Shape {
    func path(in rect: CGRect) -> Path {
        let point = min(rect.width * 0.18, rect.height * 0.6)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - point, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - point, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview("Head chef") {
    RecipeBookView(session: KitchenSession(role: .host), headChefOverride: true)
}

#Preview("Other chefs") {
    RecipeBookView(session: KitchenSession(role: .guest), headChefOverride: false)
}

#Preview("Step detail") {
    ZStack {
        GeometryReader { geo in
            Image("woods-clearing-art")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()

        StepDetailView(step: RecipeBook.steps[0])
    }
}
