//
//  StationMinigame.swift
//  Cooked
//
//  How a chef actually performs an action on an illustrated station page, and
//  how much of it they've done.
//
//  Keyed by `ActionMotion` rather than by action — the same way the
//  instruction art is — so a recipe that grows a second sifting action gets
//  the sifting minigame with no wiring here.
//
//  Every number below is lifted from the SpriteKit overlay it replaces
//  (`HoldOverlay`, `SiftOverlay`, `WhiskOverlay`, `EggOverlay` in
//  Cooked/Screens). Moving a station onto its illustrated page must not
//  quietly re-balance the game, so the tuning travels with the mechanic. The
//  one number that couldn't travel unchanged is the egg's pull-apart — see
//  `spreadNeeded`.
//

import SwiftUI
import Combine
import CoreMotion

@MainActor
final class StationMinigame: ObservableObject {

    /// Cracking an egg is the one action in two beats: break the shell, then
    /// pull it open. Everything else fills a single bar.
    enum Beat { case crack, open }

    let motion: ActionMotion

    // MARK: What the page draws

    /// 0...1, for the header bar.
    @Published private(set) var progress: CGFloat = 0
    /// True while the chef is actually doing the thing — shaking, circling,
    /// holding — rather than just standing at the counter with the screen up.
    @Published private(set) var isWorking = false
    @Published private(set) var isFinished = false
    /// A one-off correction on a flick that missed ("Too soft" / "Too hard"),
    /// which clears itself.
    @Published private(set) var notice: String?
    @Published private(set) var beat: Beat = .crack

    var onFinish: (() -> Void)?

    // MARK: Tuning, per motion

    /// Seconds of work — except for `.chop`, where it's taps, and
    /// `.breakEgg`, where it's a share of the whole job.
    private let amountNeeded: Double

    /// How hard the phone must be moving to count as shaking, in G.
    /// (`SiftOverlay.shakeNeeded`)
    private let shakeNeeded = 0.55
    /// Radians a second of circling to count as whisking.
    /// (`WhiskOverlay.speedNeeded`)
    private let speedNeeded = 1.5
    /// Touches nearer than this to the middle are ignored: a small movement
    /// close to the centre swings the angle wildly. (`WhiskOverlay.centerSize`)
    private let centreDeadZone = 34.0

    /// A flick softer than this doesn't break the shell; harder than this
    /// makes a mess. (`EggOverlay`)
    private let flickTooSoft = 1.3
    private let flickTooHard = 3.2
    private let flickCooldown = 0.7
    /// How much of the bar the crack itself is worth; the rest is opening.
    private let crackShare = 0.35
    /// How far the fingers must pull apart, as a pinch-out factor.
    ///
    /// The overlay measured this in points (130pt of extra gap), because it
    /// had both raw touch positions. SwiftUI's magnify gesture reports a
    /// scale rather than two points, so the same movement is stated as a
    /// factor instead: fingers 60% further apart than where they landed,
    /// which is ~130pt for the ~215pt gap a two-finger grab usually starts at.
    private let spreadNeeded = 0.6

    // MARK: Working state

    private var amountDone = 0.0
    private var isPressing = false
    private var isDragging = false

    /// Whisking: the angle the finger was last at, and how far round it has
    /// come since the last frame.
    private var previousAngle = 0.0
    private var hasPreviousAngle = false
    private var turnDirection = 0.0
    private var turnedThisFrame = 0.0
    private var currentSpeed = 0.0

    /// Shaking / flicking, straight off the accelerometer.
    private var shakeAmount = 0.0
    private var isInFlick = false
    private var peakThisFlick = 0.0
    private var secondsSinceFlick = 999.0
    private var spreadSoFar = 0.0

    private let motionManager = CMMotionManager()
    private var timer: Timer?
    private var lastFrame: CFTimeInterval = 0
    private var noticeToken = 0

    /// No accelerometer means the simulator, where shaking and flicking are
    /// impossible. Each of those motions keeps a touch fallback so the whole
    /// station is still testable without a device.
    ///
    /// Static because `ActionMotion.instruction` asks the same question to
    /// word itself, and standing up a `CMMotionManager` per question is waste
    /// — whether the hardware exists can't change while the app is running.
    static let hasMotionSensor: Bool = CMMotionManager().isDeviceMotionAvailable
    private var hasMotionSensor: Bool { Self.hasMotionSensor }

    // MARK: Setting up

    init(motion: ActionMotion) {
        self.motion = motion
        switch motion {
        case .hold:      amountNeeded = 3.0    // HoldOverlay
        case .sift:      amountNeeded = 9.0    // SiftOverlay
        case .whisk:     amountNeeded = 5.5    // WhiskOverlay
        case .breakEgg:  amountNeeded = 1.0    // EggOverlay — a share, not seconds
        case .mix:       amountNeeded = 3.0
        case .melt:      amountNeeded = 3.0
        // Here for completeness — the chopping page still counts its own taps
        // in `ChoppingStationView.registerChopTap`, at this same 7.
        case .chop:      amountNeeded = 7.0
        // The bin has its own aiming screen; this never runs for it.
        case .throwAway: amountNeeded = 1.0
        }
    }

    deinit {
        timer?.invalidate()
        motionManager.stopDeviceMotionUpdates()
    }

    func start() {
        guard timer == nil, !isFinished else { return }
        lastFrame = CACurrentMediaTime()
        // 60Hz, the same cadence the SpriteKit overlays ran their `update` at.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        startReadingMotion()
    }

    /// Stops the clock and the sensors. Always call this on the way out:
    /// device-motion updates left running keep draining the battery long
    /// after the chef has walked away from the counter.
    func stop() {
        timer?.invalidate()
        timer = nil
        motionManager.stopDeviceMotionUpdates()
        isWorking = false
    }

    private func startReadingMotion() {
        guard motion == .sift || motion == .breakEgg, hasMotionSensor else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] reading, _ in
            guard let self, let reading else { return }
            // userAcceleration is what the chef is doing to the phone, with
            // gravity already taken out.
            let a = reading.userAcceleration
            let strength = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)

            if self.motion == .sift {
                // Eased towards the new reading so the bar doesn't flicker.
                self.shakeAmount += (strength - self.shakeAmount) * 0.4
            } else {
                // Not smoothed: a flick is a sharp spike, and smoothing would
                // flatten the very thing we're watching for.
                self.shakeAmount = strength
            }
        }
    }

    // MARK: The chef's input

    /// A finger went down (hold, and the no-sensor fallbacks).
    func pressDown() {
        guard !isFinished else { return }
        isPressing = true
        // On a simulator a tap stands in for the flick that cracks the shell.
        if motion == .breakEgg, beat == .crack, !hasMotionSensor {
            crack()
        }
    }

    func release() {
        isPressing = false
    }

    /// One tap of a tap-counted action.
    func tapped() {
        guard !isFinished, motion == .chop else { return }
        amountDone = min(amountNeeded, amountDone + 1)
        publish()
        if amountDone >= amountNeeded { finish() }
    }

    /// The finger moved while circling. `centre` is the middle of the surface
    /// being circled around.
    func dragged(to point: CGPoint, around centre: CGPoint) {
        guard !isFinished, motion == .whisk else { return }

        let across = Double(point.x - centre.x)
        let up = Double(point.y - centre.y)
        guard sqrt(across * across + up * up) > centreDeadZone else { return }

        let newAngle = atan2(up, across)
        isDragging = true

        guard hasPreviousAngle else {
            previousAngle = newAngle
            hasPreviousAngle = true
            return
        }

        var change = newAngle - previousAngle
        previousAngle = newAngle

        // Angles wrap from +pi to -pi. When they do, the change looks enormous
        // even though the finger barely moved.
        if change > .pi { change -= 2 * .pi }
        if change < -.pi { change += 2 * .pi }

        // The first real movement decides which way round counts as forwards,
        // so scrubbing back and forth gets the chef nowhere.
        if turnDirection == 0, abs(change) > 0.05 {
            turnDirection = change > 0 ? 1 : -1
        }
        let forward = change * turnDirection
        if forward > 0 { turnedThisFrame += forward }
    }

    func dragEnded() {
        isDragging = false
        hasPreviousAngle = false
    }

    /// Two fingers pulling the cracked shell apart. `magnification` is the
    /// gesture's own scale: 1 is where the fingers landed.
    func spread(_ magnification: CGFloat) {
        guard !isFinished, motion == .breakEgg, beat == .open else { return }
        // Only ever record the widest they got: letting go a little shouldn't
        // undo the pull.
        spreadSoFar = max(spreadSoFar, min(spreadNeeded, Double(magnification) - 1))
        isPressing = true
    }

    func spreadEnded() {
        isPressing = false
    }

    // MARK: Every frame

    private func frame() {
        guard !isFinished else { return }
        let now = CACurrentMediaTime()
        // A long gap (the app was backgrounded mid-action) would otherwise
        // hand the chef a chunk of free progress.
        let dt = min(0.1, now - lastFrame)
        lastFrame = now
        guard dt > 0 else { return }

        switch motion {
        case .hold, .mix, .melt, .throwAway:
            isWorking = isPressing
            if isWorking { amountDone += dt }

        case .sift:
            // The sensor if there is one, a held finger if there isn't.
            isWorking = hasMotionSensor ? shakeAmount >= shakeNeeded : isPressing
            if isWorking { amountDone += dt }

        case .whisk:
            let speedNow = turnedThisFrame / dt
            turnedThisFrame = 0
            // Blended into the running speed so the bar doesn't flicker.
            currentSpeed += (speedNow - currentSpeed) * 0.35
            isWorking = isDragging && currentSpeed >= speedNeeded
            if isWorking { amountDone += dt }

        case .breakEgg:
            secondsSinceFlick += dt
            if beat == .crack {
                watchForFlick()
                amountDone = 0
                isWorking = isInFlick
            } else {
                // The crack, plus however far the shell has been opened.
                amountDone = crackShare + (spreadSoFar / spreadNeeded) * (1 - crackShare)
                isWorking = isPressing
            }

        case .chop:
            isWorking = false   // taps drive it, not time
        }

        publish()
        if amountDone >= amountNeeded { finish() }
    }

    /// Watches for one sharp jolt, then judges how hard it was.
    private func watchForFlick() {
        guard secondsSinceFlick >= flickCooldown else { return }

        // Strong enough to be the beginning of a flick: ride it up and keep
        // the peak.
        if shakeAmount > flickTooSoft * 0.6 {
            isInFlick = true
            peakThisFlick = max(peakThisFlick, shakeAmount)
            return
        }

        // It's died down again, so the flick is over — judge what it peaked at.
        guard isInFlick else { return }
        isInFlick = false
        let strength = peakThisFlick
        peakThisFlick = 0
        secondsSinceFlick = 0

        if strength < flickTooSoft {
            say("Too soft")
        } else if strength > flickTooHard {
            say("Too hard")
        } else {
            crack()
        }
    }

    private func crack() {
        beat = .open
        say("Cracked")
    }

    /// A correction that clears itself, so it doesn't sit on screen through
    /// the rest of the action.
    private func say(_ words: String) {
        notice = words
        noticeToken += 1
        let token = noticeToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, token == self.noticeToken else { return }
            self.notice = nil
        }
    }

    private func publish() {
        progress = CGFloat(min(1, amountDone / amountNeeded))
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        amountDone = amountNeeded
        progress = 1
        isWorking = false
        stop()
        onFinish?()
    }
}

// MARK: - The surface the chef works on

/// The whole station page, listening for however this action is performed.
///
/// Sits below the back and help buttons in z-order on purpose: backing out or
/// re-reading the instruction stays possible mid-action, and only input that
/// misses both of them counts as work.
struct MinigameSurface: View {

    @ObservedObject var game: StationMinigame

    var body: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            Color.clear
                .contentShape(Rectangle())
                .gesture(gesture(around: centre))
        }
    }

    private func gesture(around centre: CGPoint) -> AnyGesture<Void> {
        switch game.motion {
        case .whisk:
            return AnyGesture(DragGesture(minimumDistance: 0)
                .onChanged { game.dragged(to: $0.location, around: centre) }
                .onEnded { _ in game.dragEnded() }
                .map { _ in () })

        case .breakEgg:
            // Beat one is the phone itself (or a tap, with no sensor to flick);
            // beat two is two fingers pulling apart.
            if game.beat == .open {
                return AnyGesture(MagnifyGesture()
                    .onChanged { game.spread($0.magnification) }
                    .onEnded { _ in game.spreadEnded() }
                    .map { _ in () })
            }
            return AnyGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in game.pressDown() }
                .onEnded { _ in game.release() }
                .map { _ in () })

        case .chop:
            return AnyGesture(DragGesture(minimumDistance: 0)
                .onEnded { _ in game.tapped() }
                .map { _ in () })

        case .hold, .sift, .mix, .melt, .throwAway:
            // Press and hold. `minimumDistance: 0` is what makes a finger that
            // lands and never moves register at all.
            return AnyGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in game.pressDown() }
                .onEnded { _ in game.release() }
                .map { _ in () })
        }
    }
}
