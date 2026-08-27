//
//  AssemblyStationView.swift
//  Cooked
//
//  The assembly table, rebuilt against final art (CH5 "a & d" flow). One page
//  carrying BOTH of the table's actions, back to back:
//
//      assemble          decorate
//      ────────          ────────
//      base on stand     creamed cake
//      swirl the cream   tap to set the fruit
//      creamed cake      finished cake
//
//  Two actions, one errand. The design draws them as a single screen and the
//  recipe agrees — actions 10 and 11 both live at `.table` — so walking away
//  between them would be a trip to nowhere and back.
//
//  THE ONE RULE THIS PAGE BENDS
//  Everywhere else, a finished prep sits on its station and blocks it until
//  someone takes it (`canDo` starts `guard output == nil`). Here that would
//  mean assembling, picking the cake up, putting it straight back down, and
//  only then decorating — two taps that undo each other. So decorating reads
//  the station's own output as its input instead. See `canDo`.
//
//  That bend lives here and nowhere else: `applyCompletion` on the host does
//  not re-check deposits (it trusts the reporting client and records the
//  result), so no rule in `GatingBridge`, `KitchenSession` or `Recipe` had to
//  move to make this work.
//
//  COORDINATES
//  Measured against the plain 874x402 screen — the Figma frame itself — so the
//  numbers here go through `StorageCanvas`/`storagePlaced`, not `StationCanvas`.
//  The other station pages use the stretched 919x513 artboard because their
//  forest backdrop bleeds off every edge; this frame's does not, and feeding
//  these numbers to `figmaPlaced` lands everything about half a percent out.
//  `StorageCanvas` is misnamed for this use — it is the plain-screen artboard,
//  not a storage-only one. Renaming it to something neutral is a tidy-up for
//  its own branch, not this one.
//

import SwiftUI
import CoreMotion
import Combine

struct AssemblyStationView: View {
    let station: StationID
    @ObservedObject var session: KitchenSession
    @ObservedObject var inventory: PlayerInventory
    var onClose: () -> Void

    @State private var alert: String?
    /// Shown once, briefly, when the page appears and again on the help button.
    @State private var showTutorial = true

    /// True while a minigame is running. The whole screen becomes the input
    /// surface, and the buttons get out of the way.
    @State private var isWorking = false
    /// 0...1 for the bar across the top.
    @State private var progress: Double = 0
    /// Flipped back and forth fast to shiver the piping bag while the cream
    /// goes on. Only meaningful while assembling.
    @State private var vibrate = false
    /// Last touch angle around the cake, for measuring how far a drag swept.
    @State private var lastTouchAngle: Double?
    /// The phone's own tilt-and-swirl, on hardware that has the sensor.
    @StateObject private var swirl = TiltSwirlReader()

    /// How much circling assembles the cake — two full turns.
    private let sweepNeeded: Double = 4 * .pi
    /// How many taps set the fruit. Matched to the chopping station's 7 so the
    /// two "tap a few times" minigames feel the same.
    private let tapsNeeded: Double = 7
    @State private var taps: Double = 0

    // MARK: Snapshot-derived state — same rules as the other station pages

    private var completed: Set<Int> { Set(session.snapshot.completed) }
    // Through the session's host-aware accessors, not `session.snapshot`: the
    // snapshot only refreshes on the 10Hz tick, which needs two connected
    // players, so a solo host would never see its own deposit land.
    private var deposited: Set<String> { Set(session.depositedFoods(at: station)) }
    private var output: String? { session.outputFood(at: station) }

    /// The table's two actions, found by what they produce rather than by
    /// hardcoded ids, so renumbering the recipe doesn't silently break this.
    private var assembleAction: CookAction? {
        Recipe.actions.first { $0.station == .table && $0.output == "assembledCake" }
    }
    private var decorateAction: CookAction? {
        Recipe.actions.first { $0.station == .table && $0.output == "finishedCake" }
    }

    /// Which half of the errand the chef is on.
    private var action: CookAction? {
        if let assemble = assembleAction, !completed.contains(assemble.id) { return assemble }
        if let decorate = decorateAction, !completed.contains(decorate.id) { return decorate }
        return nil
    }

    private var isDecorating: Bool { action?.output == "finishedCake" }

    // MARK: What is standing on the stand

    private enum CakeLook { case empty, base, creamed, finished }

    private var cakeLook: CakeLook {
        if output == "finishedCake" { return .finished }
        if output == "assembledCake" { return .creamed }
        if deposited.contains("bakedBase") { return .base }
        return .empty
    }

    // MARK: Gating

    private var handBlockMessage: String? {
        if inventory.isHoldingRotten { return Rotten.blockedMessage }
        return nil
    }

    private func canDo(_ action: CookAction) -> Bool {
        if action.output == "finishedCake" {
            // The bend described at the top of the file: the creamed cake is
            // already standing here as this station's output, so decorating
            // asks for exactly that rather than for a deposit that would mean
            // picking it up and setting it down again.
            return output == "assembledCake"
        }
        guard output == nil else { return false }
        return GatingBridge.requiredIngredients(for: action).isSubset(of: deposited)
    }

    /// The prep in hand that this counter will take, if any.
    private var depositable: (id: String, name: String)? {
        guard let held = inventory.ingredient, !held.isRotten else { return nil }
        guard let action, GatingBridge.requiredIngredients(for: action).contains(held.id) else { return nil }
        guard !deposited.contains(held.id) else { return nil }
        return (held.id, held.name)
    }

    /// What assembling still wants, in recipe order, for the "waiting on"
    /// line. Reads the requirement out of `GatingBridge` rather than repeating
    /// the three ids here.
    private var missing: [String] {
        guard let action, !isDecorating else { return [] }
        return GatingBridge.requiredIngredients(for: action)
            .subtracting(deposited)
            .sorted()
    }

    // MARK: Layout — plain 874x402 screen space

    private static let progressFrame = CGRect(x: 160, y: 17, width: 554, height: 24)
    /// The empty stand, sitting on the slab.
    private static let standFrame = CGRect(x: 322, y: 144, width: 229, height: 187)
    /// Stand and baked base together — the composite drawing, whose extra
    /// height above `standFrame` is exactly the cake.
    private static let standAndCakeFrame = CGRect(x: 322, y: 85, width: 229, height: 246)
    /// Creamed and finished, each as its own composite — stand included, the
    /// way `ui-stand-and-cake` ships.
    ///
    /// All three share a bottom edge at y=331, which is where the stand's foot
    /// meets the slab. That is the whole trick: the art keeps the cake and its
    /// plate in register, so nothing here has to know how tall a cake is or
    /// how much empty space a drawing carries under it. An earlier version
    /// layered loose cakes onto the bare stand and had to solve each rect
    /// backwards from measured transparent margins; these two assets made all
    /// of that go away.
    private static let creamedFrame = CGRect(x: 320, y: 85, width: 234, height: 246)
    private static let finishedFrame = CGRect(x: 322, y: 35, width: 229, height: 296)

    private static let backFrame = CGRect(x: 50, y: 26, width: 53, height: 53)
    private static let helpFrame = CGRect(x: 25, y: 334, width: 53, height: 47)
    private static let clockFrame = CGRect(x: 783, y: 32, width: 66, height: 72)

    // MARK: Piping bag — EDITABLE
    //
    // The bag holds one fixed spot: leaning in from the upper left with its
    // nozzle on the top of the cake, exactly as the "a & decorate, start B"
    // frame draws it. It does not travel — while the cream goes on it only
    // vibrates in place. Every number a chef would want nudged is here.
    //
    // All four are in the plain 874x402 artboard, same space as the frames
    // above, so a change reads straight off the Figma panel.

    /// Where the centre of the bag sits. Move this to slide the whole bag.
    private static let pipingCentre = CGPoint(x: 356, y: 96)
    /// How big it is drawn (before the tilt is applied).
    private static let pipingSize = CGSize(width: 74, height: 168)
    /// Its lean, in degrees. 0 is upright (the leaf on top, nozzle straight
    /// down). Negative swings the nozzle to the lower right, onto the cake,
    /// with the bag leaning in from the upper left — the "start B" pose.
    /// (Positive would lean it the other way, nozzle to the lower left.)
    private static let pipingTilt: Double = -65.43
    /// How far it shivers while piping, peak offset in artboard units. 0 stops
    /// the vibration entirely.
    private static let pipingVibration: CGFloat = 5

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ground(geo)
                stand(geo)
                pipingBag(geo)
                StorageHands(inventory: inventory, geo: geo)
                progressBar(geo)

                // Under the corner buttons on purpose: back and help stay
                // reachable mid-action, and only taps that miss both of them
                // count as work.
                // The touch surface is needed for decorating always (there is
                // no sensor version of "tap the cake") and for assembling only
                // where there's no sensor to swirl.
                if isWorking && (isDecorating || !TiltSwirlReader.isAvailable) {
                    workSurface(geo)
                }

                backButton(geo)
                helpButton(geo)
                if !isWorking { controls(geo) }

                if let alert {
                    PrepHeldAlert(message: alert) { self.alert = nil }
                }
                if showTutorial {
                    tutorialOverlay(geo)
                }

                clock(geo)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onAppear { flashTutorial() }
        // Never leave the sensor running behind us: backing out mid-swirl, or
        // the page being torn down by the round ending, both land here.
        .onDisappear { swirl.stop() }
        .onChange(of: swirl.swept) { _, swept in
            guard isWorking, !isDecorating else { return }
            progress = min(1, swept / sweepNeeded)
            if progress >= 1 { finish() }
        }
    }

    // MARK: Backdrop

    private func ground(_ geo: GeometryProxy) -> some View {
        ZStack {
            Group {
                if let art = UIImage(named: "forest-background") {
                    Image(uiImage: art).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(red: 0.24, green: 0.32, blue: 0.26),
                                            Color(red: 0.14, green: 0.20, blue: 0.16)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()

            // The plain slab, not `stone-slab` — this counter's frames are
            // drawn on the vine-free variant.
            if let art = UIImage(named: "ui-stone-no-vines") {
                Image(uiImage: art).resizable().scaledToFit()
                    .storagePlaced(127, 65, 636, 304, in: geo)
            }
        }
    }

    // MARK: The stand and what is on it

    @ViewBuilder
    private func stand(_ geo: GeometryProxy) -> some View {
        switch cakeLook {
        case .empty:
            art("ui-stand-cake").storagePlaced(Self.standFrame, in: geo)

        case .base:
            // One drawing for stand-plus-base, which is how the design ships
            // it — layering a loose base would only reproduce it less well.
            art("ui-stand-and-cake").storagePlaced(Self.standAndCakeFrame, in: geo)

        case .creamed, .finished:
            art(cakeLook == .finished ? "ui-finished-cake" : "ui-creamed-cake")
                .storagePlaced(cakeLook == .finished ? Self.finishedFrame : Self.creamedFrame,
                               in: geo)
        }
    }

    /// The piping bag, leaning in with its nozzle on the cake — the pose the
    /// "start B" frame draws. It holds that one spot; while the cream goes on
    /// it vibrates rather than travelling.
    ///
    /// It is drawn by the page rather than read out of the inventory on
    /// purpose. No action at this counter requires a utensil — `GatingBridge`
    /// asks for none, and nothing stocks a piping bag — so a chef never picks
    /// one up. The bag is scenery that belongs to the table, and treating it
    /// as held would put a tool in the hand that the rules say isn't there.
    @ViewBuilder
    private func pipingBag(_ geo: GeometryProxy) -> some View {
        // Only while there's a bare creamable cake to work on: the base is on
        // the stand, and the cream isn't on yet.
        if cakeLook == .base {
            // The shiver runs along the bag's own lean, so it reads as the
            // nozzle jittering against the cake rather than the whole bag
            // sliding sideways. Zero unless actually piping.
            let unit = StorageCanvas.scale(in: geo)
            let amp = (isWorking && !isDecorating) ? Self.pipingVibration : 0
            let phase = vibrate ? amp : -amp
            let rad = Self.pipingTilt * .pi / 180
            let dx = CGFloat(cos(rad)) * phase * unit
            let dy = CGFloat(sin(rad)) * phase * unit

            art("ui-piping")
                .rotationEffect(.degrees(Self.pipingTilt))
                .storagePlaced(Self.pipingCentre.x - Self.pipingSize.width / 2,
                               Self.pipingCentre.y - Self.pipingSize.height / 2,
                               Self.pipingSize.width, Self.pipingSize.height,
                               in: geo)
                .offset(x: dx, y: dy)
                .allowsHitTesting(false)
        }
    }

    private func art(_ name: String) -> some View {
        Group {
            if let image = UIImage(named: name) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
    }

    // MARK: The bar across the top

    /// Blank underneath, the filled drawing on top masked to how far the work
    /// has got. Both PNGs are the same size and both letter the title into the
    /// art, so the words flip from dark to cream exactly where the fill
    /// reaches — no second label to keep in sync.
    private func progressBar(_ geo: GeometryProxy) -> some View {
        let box = StorageCanvas.rect(Self.progressFrame, in: geo)
        return ZStack(alignment: .leading) {
            art("ui-assesmble-and-decorate-blank-progress-bar")
            art("ui-assesmble-and-decorate-progress-bar")
                .mask(alignment: .leading) {
                    Rectangle().frame(width: box.width * progress)
                }
                .animation(.easeOut(duration: 0.15), value: progress)
        }
        .storagePlaced(Self.progressFrame, in: geo)
        .allowsHitTesting(false)
        .accessibilityLabel("Assemble and decorate")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }

    private func clock(_ geo: GeometryProxy) -> some View {
        StorageClock(timeRemaining: session.secondsRemaining, geo: geo)
    }

    // MARK: Corner buttons

    private func backButton(_ geo: GeometryProxy) -> some View {
        Button(action: onClose) {
            Group {
                if let image = UIImage(named: "ui-back-button") {
                    // The PNG is a plank with a hanging post above it; only the
                    // plank carries the arrow, so scale to width and crop to
                    // the bottom — same treatment as everywhere else it's used.
                    GeometryReader { box in
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: box.size.width,
                                   height: box.size.width * (156.0 / 104.0))
                            .frame(width: box.size.width, height: box.size.height,
                                   alignment: .bottom)
                            .clipped()
                    }
                } else {
                    Image(systemName: "arrowshape.turn.up.backward.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(StationPalette.cream)
                }
            }
        }
        .buttonStyle(.plain)
        .storagePlaced(Self.backFrame, in: geo)
        .accessibilityLabel("Leave the table")
    }

    private func helpButton(_ geo: GeometryProxy) -> some View {
        Button(action: flashTutorial) {
            art("help")
        }
        .buttonStyle(.plain)
        .storagePlaced(Self.helpFrame, in: geo)
        .accessibilityLabel("How this station works")
    }

    // MARK: Controls

    private func controls(_ geo: GeometryProxy) -> some View {
        let stand = StorageCanvas.rect(Self.standFrame, in: geo)
        return VStack(spacing: 10) {
            if output == "finishedCake" {
                HStack(spacing: 10) {
                    controlButton("Leave", action: onClose)
                    controlButton("Pick up") {
                        if let blocked = handBlockMessage { alert = blocked; return }
                        if let taken = session.pickUpOutput(at: station) {
                            inventory.pickUp(HeldIngredient(id: taken,
                                                            name: GatingBridge.displayName(taken),
                                                            isPrep: true))
                        }
                    }
                }
            } else if let drop = depositable {
                controlButton("Drop \(drop.name)") {
                    session.deposit(drop.id, at: station)
                    inventory.dropIngredient()
                }
            } else if !missing.isEmpty {
                waitingLabel(geo)
            }

            if let action, canDo(action) {
                controlButton(isDecorating ? "Decorate" : "Assemble", enabled: true) {
                    isWorking = true
                    progress = 0
                    taps = 0
                    lastTouchAngle = nil
                    if !isDecorating {
                        swirl.reset(); swirl.start()
                        withAnimation(.easeInOut(duration: 0.05).repeatForever(autoreverses: true)) {
                            vibrate = true
                        }
                    }
                }
            }
        }
        .frame(width: stand.width * 1.4)
        // Below the stand rather than over it — the cake is the thing the chef
        // is looking at, and the design keeps it unobstructed.
        .position(x: stand.midX, y: stand.maxY + stand.height * 0.12)
    }

    /// What assembling is still short of. Named foods, not ids.
    private func waitingLabel(_ geo: GeometryProxy) -> some View {
        Text("Still needs: " + missing.map(GatingBridge.displayName).joined(separator: ", "))
            .font(.system(size: 13 * StorageCanvas.scale(in: geo),
                          weight: .bold, design: .rounded))
            .foregroundStyle(StationPalette.cream)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
    }

    private func controlButton(_ title: String, enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(StationPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().fill(StationPalette.cream.opacity(enabled ? 1 : 0.45)))
                .overlay(Capsule().stroke(StationPalette.ink.opacity(0.4), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: The two minigames

    /// The whole screen, while work is in flight.
    ///
    /// Assembling is a circling drag: the cream goes on as the bag is walked
    /// round the cake, so progress measures angle swept about the cake's
    /// centre rather than distance dragged. Dragging in a straight line gets
    /// you almost nowhere, which is the point — the gesture is the motion.
    ///
    /// Decorating is taps, the same count as the chopping board.
    private func workSurface(_ geo: GeometryProxy) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: geo.size.width, height: geo.size.height)
            .modifier(WorkInput(isDecorating: isDecorating,
                                onTap: registerTap,
                                onDrag: { point in registerSweep(point, geo: geo) },
                                onDragEnd: { lastTouchAngle = nil }))
    }

    private func registerTap() {
        guard isWorking, isDecorating else { return }
        taps = min(tapsNeeded, taps + 1)
        progress = taps / tapsNeeded
        if taps >= tapsNeeded { finish() }
    }

    private func registerSweep(_ point: CGPoint, geo: GeometryProxy) {
        guard isWorking, !isDecorating else { return }
        let centre = StorageCanvas.rect(Self.creamedFrame, in: geo)
        let angle = atan2(Double(point.y - centre.midY), Double(point.x - centre.midX))

        defer { lastTouchAngle = angle }
        guard let last = lastTouchAngle else { return }

        // Shortest way round, so crossing the -pi/pi seam doesn't read as a
        // full turn backwards.
        var delta = angle - last
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        // Direction-agnostic: circling either way ices the cake. Insisting on
        // one direction only tells a left-handed player they're doing it wrong.
        progress = min(1, progress + abs(delta) / sweepNeeded)
        if progress >= 1 { finish() }
    }

    /// Hand the finished action to the host. Everything `reportCompletion`
    /// would re-check is already true by construction — `canDo` gated the
    /// button that started the minigame.
    private func finish() {
        guard let action else { return }
        swirl.stop()
        withAnimation(.easeInOut(duration: 0.1)) { vibrate = false }
        isWorking = false
        progress = 0
        taps = 0
        session.reportCompletion(actionID: action.id)
    }

    // MARK: Tutorial

    /// Same 1.5s flash the chopping board uses, so the tutorial behaves the
    /// same way at every counter. It can also be dismissed by tapping, which
    /// matters here because the assemble overlay is a two-step instruction and
    /// a chef may want to read it twice.
    private func flashTutorial() {
        withAnimation(.easeInOut(duration: 0.15)) { showTutorial = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) { showTutorial = false }
        }
    }

    /// The instruction, on a bright card so the line art actually reads.
    ///
    /// The assemble drawing (`ui-assemble-tutorial-2`) is dark line work with
    /// its own "Tilt / Move in circle" labels baked in, so it is drawn as-is —
    /// no tint. The earlier `-tutorial` art was near-white and vanished into
    /// the dimmed forest, which is what "dim and unreadable" was; the cream
    /// card was meant to carry it but a tinted near-white stroke on cream is
    /// still faint. Dark art on the cream card is the reliable pairing.
    /// Decorating borrows the chopping art (`overlay-chop`), which is a
    /// template with no labels, so that one is tinted to ink and captioned.
    private func tutorialOverlay(_ geo: GeometryProxy) -> some View {
        let art = isDecorating ? "overlay-chop" : "ui-assemble-tutorial-2"
        let caption: String? = isDecorating ? "Tap" : nil

        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 10) {
                if let image = UIImage(named: art) {
                    Image(uiImage: image)
                        // Assemble art is already dark; only the borrowed
                        // chopping template needs tinting to read on cream.
                        .renderingMode(isDecorating ? .template : .original)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(StationPalette.ink)
                        .frame(maxWidth: geo.size.width * 0.5,
                               maxHeight: geo.size.height * 0.42)
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(StationPalette.ink)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(StationPalette.cream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(StationPalette.ink.opacity(0.5), lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
            .padding(24)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showTutorial = false } }
        .transition(.opacity)
    }
}

/// Taps for decorating, drags for assembling — attached as a modifier so the
/// two never fight over the same surface. A `TapGesture` and a `DragGesture`
/// on one view means the drag swallows short taps, which made the decorating
/// half feel broken on a real phone.
private struct WorkInput: ViewModifier {
    let isDecorating: Bool
    let onTap: () -> Void
    let onDrag: (CGPoint) -> Void
    let onDragEnd: () -> Void

    func body(content: Content) -> some View {
        if isDecorating {
            content.onTapGesture(perform: onTap)
        } else {
            content.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onDrag($0.location) }
                    .onEnded { _ in onDragEnd() }
            )
        }
    }
}

// MARK: - Tilt and swirl

/// Reads the phone being tilted and walked round in a circle — the gesture the
/// assemble tutorial teaches ("Tilt", then "Move in circle").
///
/// It measures the same thing the touch fallback does: how far round the chef
/// has gone. `attitude.roll` and `attitude.pitch` together say which way the
/// phone is leaning, so `atan2` of the two is the direction of the lean and
/// swirling the phone sweeps that angle round. Accumulating `abs(delta)` gives
/// the turns.
///
/// Why a lean threshold rather than counting any wobble: held flat, roll and
/// pitch are both near zero and their `atan2` is pure noise, which would fill
/// the bar while the phone sits on a table. Requiring a real lean before any of
/// it counts is what makes the tutorial's first word ("Tilt") mean something.
@MainActor
final class TiltSwirlReader: ObservableObject {

    /// Checked once and cached. A `CMMotionManager` is not free to stand up,
    /// and the answer cannot change while the app is running.
    static let isAvailable: Bool = CMMotionManager().isDeviceMotionAvailable

    /// Radians swept since the last `reset`.
    @Published private(set) var swept: Double = 0
    /// Which way the phone is leaning, for pointing the piping bag.
    @Published private(set) var angle: Double = -.pi / 2

    private let manager = CMMotionManager()
    private var lastAngle: Double?

    /// How far the phone has to lean before the swirl counts. Radians, and
    /// generous — this is "off the flat", not "at arm's length".
    private let leanNeeded: Double = 0.15

    func start() {
        guard Self.isAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] reading, _ in
            guard let self, let attitude = reading?.attitude else { return }

            let roll = attitude.roll, pitch = attitude.pitch
            guard sqrt(roll * roll + pitch * pitch) >= self.leanNeeded else {
                // Dropped back to flat. Forget where we were, so tipping over
                // to the other side doesn't read as half a turn.
                self.lastAngle = nil
                return
            }

            let now = atan2(roll, pitch)
            self.angle = now
            defer { self.lastAngle = now }
            guard let last = self.lastAngle else { return }

            // Shortest way round, so crossing the -pi/pi seam isn't a full
            // turn backwards.
            var delta = now - last
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            self.swept += abs(delta)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        lastAngle = nil
    }

    func reset() {
        swept = 0
        lastAngle = nil
        angle = -.pi / 2
    }
}


// MARK: - Previews

extension AssemblyStationView {

    /// Preview seam: open the page already mid-work, so the piping bag's fixed
    /// placement can be tuned in the canvas without a running game.
    ///
    /// It lives in an extension so the memberwise init survives — declaring an
    /// init inside the struct would remove it, and `StationPage` calls it.
    init(station: StationID, session: KitchenSession, inventory: PlayerInventory,
         onClose: @escaping () -> Void, midWork: Bool) {
        self.init(station: station, session: session, inventory: inventory, onClose: onClose)
        _isWorking = State(initialValue: midWork)
        _showTutorial = State(initialValue: false)
    }
}

/// A host session with the base already on the stand, which is what makes the
/// piping bag appear — it is drawn for `.base`.
@MainActor private func tableWithBase() -> KitchenSession {
    let session = KitchenSession(role: .host)
    session.deposit("bakedBase", at: .table)
    return session
}

#Preview("Piping — bag resting on the cake", traits: .landscapeLeft) {
    AssemblyStationView(station: .table,
                        session: tableWithBase(),
                        inventory: PlayerInventory(),
                        onClose: {})
}

// Mid-work: the tutorial is dismissed and the bag is where it vibrates. The
// canvas is static so the shiver won't play, but the resting pose is what the
// placement is judged on anyway.
#Preview("Piping — mid-pipe (vibrating)", traits: .landscapeLeft) {
    AssemblyStationView(station: .table,
                        session: tableWithBase(),
                        inventory: PlayerInventory(),
                        onClose: {},
                        midWork: true)
}

#Preview("Tutorial — assemble", traits: .landscapeLeft) {
    AssemblyStationView(station: .table,
                        session: tableWithBase(),
                        inventory: PlayerInventory(),
                        onClose: {})
}

#Preview("Empty stand — nothing dropped", traits: .landscapeLeft) {
    AssemblyStationView(station: .table,
                        session: KitchenSession(role: .host),
                        inventory: PlayerInventory(),
                        onClose: {})
}
