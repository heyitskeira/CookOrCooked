//
//  RecipeBookView.swift
//  Cooked
//
//  Today's Order — the screen between the lobby and the kitchen.
//
//  Two screens live in this one file on purpose, because they are the same
//  book seen from two sides of the table:
//
//    • The head chef gets the written order and the START signpost. Only they
//      can open the kitchen, and only they can read a step's instructions.
//    • Everyone else gets a closed book: "waiting for head chef reading the
//      order's recipe". That asymmetry is the point — the head chef has to
//      talk, and the kitchen has to listen.
//
//  Nothing here is on a clock. `KitchenSession.beginCooking()` is what starts
//  the timer, and it is wired to the signpost.
//
//  All artwork is placeholder. `ArtIcon` (RecipeBook.swift) picks up a real
//  imageset the moment one is named after the ingredient id, and the two
//  backdrops below do the same via `namedImage`.
//

import SwiftUI

struct RecipeBookView: View {

    @ObservedObject var session: KitchenSession

    /// Previews and on-device testing only — forces the head chef or guest
    /// side of the screen without needing a second device in the room.
    var headChefOverride: Bool?

    /// Leaving kills the kitchen for everyone, so it asks first.
    @State private var confirmLeave = false

    private var isHeadChef: Bool { headChefOverride ?? session.isHeadChef }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 420

            ZStack {
                backdrop

                VStack(spacing: compact ? 8 : 14) {
                    banner(compact: compact)
                    RecipeSpreadView(session: session, headChefOverride: headChefOverride, compact: compact)
                }
                .padding(.horizontal, compact ? 76 : 96)
                .padding(.vertical, compact ? 10 : 18)

                corners

                // The host can vanish while the book is open — and this is the
                // longest pre-game pause there is, so it will happen. Without
                // this the screen just says "head chef is reading…" forever.
                if session.phase == .hostLeft {
                    statusBanner("The host left — this kitchen is closed")
                } else if let player = session.localPlayer, !player.isConnected {
                    statusBanner("Reconnecting…")
                }
            }
            // Note: only the backdrop ignores the safe area. The phone is
            // landscape-only, so a full-bleed ZStack would put the back button
            // under the sensor housing and START under the home indicator.
        }
        .confirmationDialog("Leave this kitchen?",
                            isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave kitchen", role: .destructive) { session.leave() }
            Button("Keep cooking", role: .cancel) { }
        } message: {
            Text(session.isHeadChef
                 ? "You're the head chef — leaving closes the kitchen for everyone."
                 : "You'll drop out of this order.")
        }
        .onAppear {
            #if DEBUG
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

    private var backdrop: some View {
        ZStack {
            if let art = namedImage("woods-clearing-art") {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.24, green: 0.32, blue: 0.26),
                                        Color(red: 0.14, green: 0.20, blue: 0.16)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Banner

    private func banner(compact: Bool) -> some View {
        Text("TODAY'S ORDER")
            .font(.system(size: compact ? 26 : 34, weight: .heavy, design: .rounded))
            .foregroundStyle(AppTheme.cream)
            .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 3)
            .padding(.horizontal, 44)
            .padding(.vertical, compact ? 8 : 12)
            .background(plank)
    }

    private var plank: some View {
        ZStack {
            if let art = namedImage("trunk-planks") {
                Image(uiImage: art).resizable().scaledToFill()
            } else {
                Color(red: 0.45, green: 0.31, blue: 0.19)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(red: 0.28, green: 0.18, blue: 0.10), lineWidth: 4)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 5)
    }

    // MARK: Back button and signpost

    private var corners: some View {
        VStack {
            HStack {
                backButton
                Spacer()
            }
            Spacer()
            HStack {
                Spacer()
                startControl
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var backButton: some View {
        // Only `session.leave()` — no `dismiss()`. The waiting room is watching
        // for `.idle` and closes this cover itself; doing both would tear down
        // two stacked covers in the same update and wedge the presentation.
        Button {
            confirmLeave = true
        } label: {
            ZStack {
                if let art = namedImage("back-button") {
                    Image(uiImage: art).resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.45, green: 0.31, blue: 0.19))
                        .overlay(
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(AppTheme.cream)
                        )
                }
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Leave kitchen")
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

    // MARK: Art lookup

    /// Real artwork if the imageset exists, nil to fall back to a drawn stand-in.
    private func namedImage(_ name: String) -> UIImage? { FoodArt.art(name) }
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
    var compact: Bool = false

    /// The step whose instruction card is open, if any.
    @State private var openStep: BookStep?

    private var isHeadChef: Bool { headChefOverride ?? session.isHeadChef }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                page {
                    if isHeadChef { headChefPage(RecipeBook.leftPage, compact: compact) }
                    else { waitingPage }
                }

                // The spine. A seam of shadow does more for "this is a book" than
                // any amount of page curl.
                LinearGradient(colors: [.clear, AppTheme.ink.opacity(0.35), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 22)

                page {
                    if isHeadChef { headChefPage(RecipeBook.rightPage, compact: compact) }
                    else { dottedLines(count: 8) }
                }
            }
            .padding(compact ? 12 : 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.45, green: 0.31, blue: 0.19))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 0.28, green: 0.18, blue: 0.10), lineWidth: 5)
            )
            .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 8)

            if let step = openStep {
                InstructionCard(step: step) {
                    withAnimation(.easeOut(duration: 0.15)) { openStep = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
    }

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.96, green: 0.91, blue: 0.80))
            )
    }

    // MARK: Head chef's page

    private func headChefPage(_ steps: [BookStep], compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            // The recipe's name sits over the left-hand page, as in the mockup.
            if steps.first?.number == 1 {
                Text(RecipeBook.orderTitle.uppercased())
                    .font(.system(size: compact ? 17 : 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.tomato)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, 2)
            }

            ForEach(steps) { step in
                stepRow(step, compact: compact)
            }

            Spacer(minLength: 0)
        }
    }

    private func stepRow(_ step: BookStep, compact: Bool) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { openStep = step }
        } label: {
            HStack(spacing: 8) {
                Text("\(step.number)")
                    .font(.system(size: compact ? 22 : 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.tomato)
                    .frame(width: compact ? 26 : 32, alignment: .leading)

                ArtIcon(id: step.output, size: compact ? 20 : 24)

                Text(step.title)
                    .font(.system(size: compact ? 13 : 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 3 : 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.93, green: 0.87, blue: 0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.ink.opacity(0.18), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Everyone else's page

    private var waitingPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Waiting for head chef reading the order's recipe")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            dottedLines(count: 6)
        }
    }

    private func dottedLines(count: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                DottedRule()
                    .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 9]))
                    .foregroundStyle(AppTheme.ink.opacity(0.35))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - The instruction card (image + image = image)

/// One step, spelled out the way the kitchen actually works: everything that
/// goes in, the tool you must be holding, and the one thing that comes out.
private struct InstructionCard: View {

    let step: BookStep
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 14) {
                header
                equation
                footnotes
                Text("Tap anywhere to close")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.4))
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.96, green: 0.91, blue: 0.80))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(red: 0.45, green: 0.31, blue: 0.19), lineWidth: 5)
            )
            .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 10)
            .padding(.horizontal, 40)
            .onTapGesture(perform: onClose)
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("STEP \(step.number) OF \(RecipeBook.steps.count)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(AppTheme.ink.opacity(0.45))

            Text(step.title)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.tomato)
        }
    }

    /// The whole point of the page: ingredient + ingredient = result.
    private var equation: some View {
        HStack(alignment: .center, spacing: 8) {
            if step.inputs.isEmpty {
                // Pre-heating takes nothing in — say so rather than showing an
                // empty left side that reads like a bug.
                Text("nothing")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.45))
                    .frame(width: 64)
            } else {
                ForEach(Array(step.inputs.enumerated()), id: \.offset) { index, id in
                    if index > 0 { symbol("+") }
                    tile(id)
                }
            }

            symbol("=")

            tile(step.output, highlight: true)
        }
    }

    private func tile(_ id: String, highlight: Bool = false) -> some View {
        VStack(spacing: 5) {
            ArtIcon(id: id, size: highlight ? 56 : 46)
            Text(FoodArt.name(id))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 66)
        }
    }

    private func symbol(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(AppTheme.ink.opacity(0.55))
            .padding(.bottom, 20)
    }

    private var footnotes: some View {
        HStack(spacing: 10) {
            if let utensil = step.utensil {
                badge {
                    ArtIcon(id: utensil, size: 22)
                    Text("Hold the \(FoodArt.name(utensil).lowercased())")
                }
            }
            badge {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.ink.opacity(0.6))
                Text(step.stationLabel)
            }
        }
    }

    private func badge<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 7) {
            content()
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundStyle(AppTheme.ink.opacity(0.75))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color(red: 0.93, green: 0.87, blue: 0.74)))
        .overlay(Capsule().stroke(AppTheme.ink.opacity(0.2), lineWidth: 1.5))
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
