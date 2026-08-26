//
//  KitchenSession.swift
//  Cooked
//
//  Host-authoritative lobby and game sync.
//
//  The host owns the only real GameState. Guests never mutate it — they
//  report intent (I moved here, I finished this action) and render whatever
//  the next snapshot says. That keeps four devices agreeing without any
//  conflict resolution, at the cost of the host being a single point of
//  failure. Host migration is still out of scope — but the host going away is
//  no longer the end of the game.
//
//  WHAT HAPPENS WHEN THE HOST DISAPPEARS
//
//  It used to be: everyone's socket dies, everyone falls out of the kitchen,
//  and the host relaunches into a brand new room with a brand new code that
//  nobody can get back into. Three separate things caused that, and all three
//  are fixed here.
//
//    1. The kitchen is frozen, not closed. Guests set `isPaused`, hold the
//       phase exactly where it was, and wait `PauseRules.graceSeconds` for the
//       host to come back. Nothing ticks: not the clock, not the minigames,
//       not the serve holds.
//    2. The room has an identity that survives the process. `ticket.roomID`
//       and the four digits are written to disk (see RoomResume.swift), so a
//       relaunched host reopens the *same* kitchen rather than a new one.
//    3. Guests reconnect by kitchen, not by socket. The old code chased the
//       Bonjour endpoint string, which is regenerated on relaunch; it now
//       matches on the kitchen's name and proves the room with `roomID`.
//
//  Joining is gated twice. The room code proves the guest can see the host's
//  screen, which is the only same-room evidence that does not depend on
//  radios or walls. The UWB check is a bonus that fails open. A *rejoin* skips
//  both, because a resume token the host itself issued is better evidence than
//  either — and asking a player to re-type a code to get back into a match
//  they are already in is exactly the friction this all exists to remove.
//

import Foundation
import Combine
import UIKit   // UIApplication lifecycle notifications only — see watchAppLifecycle

@MainActor
final class KitchenSession: ObservableObject {

    enum Role { case host, guest }

    enum Phase: Equatable {
        case idle
        case searching
        case verifying(String)
        case lobby
        /// Everyone is on the recipe book. The head chef reads Today's Order;
        /// the rest see a closed book. Nothing is ticking — the clock does not
        /// start until the head chef hits START.
        case briefing
        case playing
        case rejected(JoinRejection)
        case hostLeft

        var isVerifying: Bool {
            if case .verifying = self { return true }
            return false
        }

        var isRejected: Bool {
            if case .rejected = self { return true }
            return false
        }
    }

    // MARK: Published state

    @Published private(set) var players: [Player] = []
    @Published private(set) var discovered: [DiscoveredKitchen] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var snapshot = GameSnapshot.empty
    @Published private(set) var kitchenName: String
    @Published private(set) var maxPlayers: Int
    @Published private(set) var roomCode: RoomCode
    @Published private(set) var errorText: String?

    // MARK: The pause
    //
    // A pause is deliberately NOT a phase. The match is still exactly where it
    // was — same screen, same recipe book or same kitchen — it simply isn't
    // running. Making it a phase would mean every view that switches on phase
    // needs a new case, and `GameFlowView` would swap a frozen kitchen for the
    // recipe book the moment the host blipped.

    /// True while the kitchen is held still waiting for the host to come back.
    @Published private(set) var isPaused = false

    /// Seconds left before we give up on the host, or nil if we aren't waiting.
    @Published private(set) var pauseSecondsLeft: Int?

    /// 3… 2… 1… after the host reconnects. Non-nil means still frozen.
    @Published private(set) var resumeSecondsLeft: Int?

    /// 3… 2… 1… after the last chef presses Ready.
    @Published private(set) var startSecondsLeft: Int?

    /// Nothing may move, tick, or be reported while this is true. The scene
    /// reads it to stop its own loop; the views read it to put up an overlay.
    var isFrozen: Bool { isPaused || resumeSecondsLeft != nil }

    /// The station the local player has been *granted*, if any. The scene may
    /// only open a station screen when this matches where the chef is standing.
    /// nil means either not at a station, or still queueing for one.
    @Published private(set) var heldStation: StationID?

    /// The host's answer to this device's most recent utensil request. Storage
    /// observes it to fill the hand (granted) or show "out" (denied).
    @Published private(set) var utensilReply: UtensilReply?

    struct UtensilReply: Equatable {
        let id: String
        let granted: Bool
    }

    /// The host's answer to this device's most recent drawer request. DrawerView
    /// observes it to empty the hand (stored), fill it (took), or explain a
    /// refusal.
    @Published private(set) var drawerReply: DrawerReply?

    enum DrawerReply: Equatable {
        case stored(slot: Int)
        case refused(slot: Int, reason: String)
        case took(slot: Int, item: DrawerItem?)
    }

    let role: Role
    let localPlayerID: String

    var isHost: Bool { role == .host }
    var connectedCount: Int { players.filter(\.isConnected).count }
    var canStart: Bool { isHost && connectedCount >= 2 && phase == .lobby }
    var localPlayer: Player? { players.first { $0.id == localPlayerID } }

    /// Every chef who is actually here has pressed Ready, and there are enough
    /// of them to cook. This is what starts the match — no host button, because
    /// "all ready" is already unanimous consent and asking for one more tap
    /// after that is just a fifth person to wait for.
    var everyoneReady: Bool {
        let here = players.filter(\.isConnected)
        return here.count >= 2 && here.allSatisfy(\.isReady)
    }

    /// This device's own Ready state, for the button's fill.
    var isReady: Bool { localPlayer?.isReady ?? false }

    /// The two phases where a match is under way and a dropped player's slot,
    /// colour and progress must be held rather than thrown away.
    private var isMidMatch: Bool { phase == .playing || phase == .briefing }

    func player(_ id: String) -> Player? { players.first { $0.id == id } }

    /// Who reads Today's Order out loud.
    ///
    /// The head chef is the host for now. This is deliberately one computed
    /// property rather than a check scattered across the views, so the
    /// head-chef randomiser can replace the body — or make it a `@Published`
    /// id the host broadcasts — without touching a single screen.
    var headChefID: String? { players.first(where: \.isHost)?.id }

    var isHeadChef: Bool { headChefID == localPlayerID }

    /// True while a claim is outstanding. The scene uses this to notice that a
    /// queue got silently dropped — a host blip, a grant that arrived too late
    /// — and ask again rather than standing at a counter forever.
    var isQueueingForStation: Bool { pendingClaim != nil }

    /// Who is working at this station right now — nil if it's free. Drives both
    /// the "you must wait" toast and the coloured station box.
    func occupant(of station: StationID) -> Player? {
        guard let id = snapshot.holder(of: station) else { return nil }
        return player(id)
    }


    // MARK: Machinery

    private let transport: KitchenTransport
    private var pump: Task<Void, Never>?
    private var ticker: Timer?
    /// Tokens for the background/foreground observers. See `watchAppLifecycle`.
    private var lifecycleWatchers: [any NSObjectProtocol] = []

    /// Station the local player is standing at and still waiting for. Kept so
    /// the claim can be re-sent the instant the holder walks away, which is
    /// what makes "wait here and it opens by itself" work without polling.
    private var pendingClaim: StationID?

    // Host only
    private let game = GameState()
    /// station rawValue -> player ID. The authoritative lock table; guests only
    /// ever see the copy inside the snapshot.
    private var occupancy: [String: String] = [:]
    /// utensil id -> count left on the shelf. Authoritative; rides the snapshot.
    private var utensilStock: [String: Int] = StoragePantry.defaultUtensilStock
    /// station rawValue -> [foodID] dropped in so far. Authoritative; cleared
    /// when the station's action completes.
    private var deposited: [String: [String]] = [:]
    /// The drawer's four shelves. Authoritative; rides the snapshot.
    private var drawerSlots: [DrawerItem?] = Array(repeating: nil, count: Drawer.slotCount)
    /// Who is standing in the serve zone, and when each of them last pressed.
    /// Host-only: a guest deciding for itself that the team served together is
    /// exactly the bug this whole dance exists to prevent.
    private var serveZone: Set<String> = []
    /// Who is holding the button, and since when. The timestamp is what expires
    /// a lone hold after `gatherWindow` — press early and nothing is banked.
    private var serveHolds: [String: TimeInterval] = [:]
    /// When the whole team last became "all holding at once". nil means the bar
    /// is empty. Reset the instant anyone lets go or steps off their mark,
    /// which is the entire spike-defuse feel.
    private var serveChargeStartedAt: TimeInterval?

    /// station rawValue -> the finished prep sitting on it, waiting for pickup.
    /// A station with an entry here is blocked until the prep is taken.
    private var stationOutput: [String: String] = [:]
    private var chefs: [String: ChefSnapshot] = [:]
    private var peerToPlayer: [PeerID: String] = [:]
    private var playerToPeer: [String: PeerID] = [:]
    private var joinQueue: [PendingJoin] = []
    private var verifying: PendingJoin?
    private var gate: ProximityGate?

    private var verifyTimeout: Task<Void, Never>?
    private var joinTimeout: Task<Void, Never>?

    // Host only — room identity and resumption
    /// This kitchen's durable identity. Written to disk the moment hosting
    /// starts, so relaunching reopens the same room instead of minting a new
    /// one with a code nobody has.
    private var ticket: RoomTicket
    /// playerID -> the token that lets that device back in without the code or
    /// the UWB check. Issued once on first admission and reused forever after.
    private var resumeTokens: [String: String] = [:]
    /// When the freeze started, so wall-clock timers can be shifted forward by
    /// exactly as long as nothing was happening. See `rebaseServeClocks`.
    private var pausedAt: TimeInterval?
    /// Drives both the ready countdown and the resume countdown — only one can
    /// ever be running, and starting either must cancel the other.
    private var countdownTask: Task<Void, Never>?
    /// Bumped every time a countdown starts or is cancelled, so a cancelled
    /// task's tidy-up can tell whether it is still the current one.
    private var countdownGeneration = 0
    /// Same trick for `closeKitchen`'s deferred teardown, on its own counter so
    /// unrelated countdown activity can't cancel a shutdown.
    private var closeGeneration = 0
    /// True while the listener is up. `startHosting` is called from two places
    /// on the resume path, and re-advertising tears the Bonjour advert down and
    /// back up — precisely when frozen guests are hunting for it.
    private var isAdvertising = false
    /// Ticks since the room was last written down. Saving on every one of them
    /// would be ten UserDefaults writes a second for no benefit.
    private var ticksSinceSave = 0

    // Guest only
    private var hostPeer: PeerID?
    private var joiningKitchenID: String?
    /// The kitchen's *name*, kept because it is the only thing about a host
    /// that survives its app relaunching. `joiningKitchenID` is a Bonjour
    /// endpoint string and is regenerated with the process — chasing it was
    /// why a returning host could never be found again.
    private var targetKitchenName: String?
    /// The room we belong to and the token that proves it. Both arrive with
    /// `joinAccepted` and are written to disk immediately.
    private var targetRoomID: String?
    private var resumeToken: String?
    private var submittedCode: RoomCode?
    private var rejoinTask: Task<Void, Never>?
    /// Counts the ninety seconds of held breath before we give up on the host.
    private var pauseDeadline: Task<Void, Never>?

    // Guest-only throttle bookkeeping for position reports.
    private var lastSentAt: TimeInterval = 0
    private var lastSentX: Double = -1
    private var lastSentY: Double = -1
    private var lastSentStation: String?
    private var lastSentBusy = false
    /// Last serve-zone state this device told the host about. The scene asks
    /// every frame; only the edges are worth a packet.
    private var lastSentServeReady = false
    /// Same idea for the hold: the button reports its edges, not its state.
    private var lastSentServeHold = false

    private struct PendingJoin {
        let peer: PeerID
        let id: String
        let name: String
        let supportsRanging: Bool
    }

    // MARK: Init

    /// `transport` is nil-defaulted rather than `= BonjourTransport()`:
    /// default argument expressions are evaluated in a nonisolated context,
    /// so constructing a @MainActor object there doesn't compile. Building it
    /// inside the initialiser body is fine — the body is main-actor isolated.
    /// `resuming` reopens a kitchen this device was already hosting before the
    /// app went away. Everything that made the room recognisable — its id, its
    /// four digits, the roster, the colours, the clock, the bowls — comes back,
    /// which is the entire reason a chef still staring at a frozen kitchen can
    /// find their way home.
    init(role: Role,
         kitchenName: String = "",
         maxPlayers: Int = 4,
         transport: KitchenTransport? = nil,
         resuming saved: SavedHostRoom? = nil) {
        self.role = role
        self.transport = transport ?? BonjourTransport()
        self.localPlayerID = PlayerIdentityStore.current.id

        // Only a host can reopen a room; a saved room handed to a guest session
        // would give it a ticket it has no business advertising.
        let restoring = role == .host ? saved : nil
        if let restoring {
            self.ticket = restoring.ticket
            self.kitchenName = restoring.ticket.kitchenName
            self.maxPlayers = restoring.ticket.maxPlayers
        } else {
            let name = kitchenName
            let cap = max(2, min(maxPlayers, PlayerPalette.rgb.count))
            self.ticket = .fresh(kitchenName: name, maxPlayers: cap)
            self.kitchenName = name
            self.maxPlayers = cap
        }
        // Force-unwrap-free: `ticket.code` was produced by RoomCode.random(),
        // so it is four digits by construction. The fallback only exists
        // because the initialiser is failable and this one cannot be.
        self.roomCode = RoomCode(ticket.code) ?? .random()

        if let restoring {
            restore(restoring)
        } else if role == .host {
            players = [Player(id: localPlayerID,
                              name: PlayerIdentityStore.current.name,
                              isHost: true,
                              isConnected: true,
                              colorIndex: 0)]
            chefs[localPlayerID] = ChefSnapshot(playerID: localPlayerID,
                                                x: 0.5, y: 0.5,
                                                station: nil, isBusy: false)
        }
        listen()
    }

    /// Rebuild the host's authoritative tables from disk.
    ///
    /// The match comes back *paused*, always — even if it was saved mid-play.
    /// The chefs are not here yet; unfreezing before they reconnect would run
    /// the clock down on an empty kitchen, which is a worse bug than the one
    /// this whole feature is fixing.
    private func restore(_ saved: SavedHostRoom) {
        players = saved.players.map {
            var player = $0
            // Nobody is connected across a relaunch, whatever the file says.
            // The host is the exception: it is, definitionally, here.
            player.isConnected = player.id == localPlayerID
            player.isReady = false
            return player
        }
        // A roster with no host in it means the file predates this device
        // being the host — repair it rather than opening an ownerless kitchen.
        if !players.contains(where: { $0.id == localPlayerID }) {
            players.insert(Player(id: localPlayerID,
                                  name: PlayerIdentityStore.current.name,
                                  isHost: true, isConnected: true, colorIndex: 0),
                           at: 0)
        }
        resumeTokens = saved.resumeTokens
        chefs = Dictionary(uniqueKeysWithValues: saved.chefs.map { ($0.playerID, $0) })
        utensilStock = saved.utensilStock
        deposited = saved.deposited
        drawerSlots = saved.drawer
        stationOutput = saved.stationOutput
        game.restore(completed: Set(saved.completed), timeRemaining: saved.timeRemaining)

        switch saved.stage {
        case .lobby:
            phase = .idle           // startHosting() moves it to .lobby
        case .briefing:
            phase = .briefing
            pauseMatch(announce: false)
        case .playing:
            phase = .playing
            pauseMatch(announce: false)
        }
    }

    // Task inherits this class's @MainActor isolation, so the stream is
    // consumed on the main actor and no hops are needed here.
    private func listen() {
        // `transport` is captured, `self` is not: hoisting `guard let self`
        // above the loop would upgrade the weak capture to a strong one for
        // the life of the stream — and `BonjourTransport.stop()` deliberately
        // never finishes its stream, so that life is forever. Every session
        // ever created would be retained, which matters here because the
        // lifecycle observers below have no `deinit` to unregister them.
        let transport = self.transport
        pump = Task { [weak self] in
            for await event in transport.events {
                guard let self else { return }
                self.handle(event)
            }
        }
        watchAppLifecycle()
    }

    /// The session listens for backgrounding itself rather than having every
    /// screen forward `scenePhase`. Five screens own or observe a session, and
    /// only one of them would have to remember — putting it here is the
    /// difference between "handled" and "handled on four screens out of five".
    ///
    /// No `deinit` unregisters these. A `@MainActor` class cannot touch its own
    /// isolated storage from a nonisolated `deinit`, and the observers are
    /// harmless without one: each closure holds only a weak reference, so once
    /// the session is gone they fire into nothing. The alternative — a
    /// notification `AsyncSequence` — hands a non-Sendable `Notification`
    /// across an isolation boundary, which is a worse trade.
    private func watchAppLifecycle() {
        let centre = NotificationCenter.default
        // Delivered on the main queue, which is the main actor's executor —
        // the same assumption `BonjourTransport.hop` is built on.
        lifecycleWatchers = [
            centre.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                               object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleDidEnterBackground() }
            },
            centre.addObserver(forName: UIApplication.willEnterForegroundNotification,
                               object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleWillEnterForeground() }
            }
        ]
    }

    // MARK: Lifecycle

    /// Host settings arrive from two different screens, so they're applied
    /// after init. Ignored once the kitchen is open — renaming a kitchen out
    /// from under connected guests would desync the roster.
    func configure(kitchenName: String, maxPlayers: Int) {
        guard isHost, phase == .idle, players.count <= 1 else { return }
        self.kitchenName = kitchenName
        self.maxPlayers = max(2, min(maxPlayers, PlayerPalette.rgb.count))
        // The ticket carries the name because the name is what a reconnecting
        // guest browses for — it has to be written down with the room, not left
        // to be re-derived from a view that may never be built again.
        ticket.kitchenName = self.kitchenName
        ticket.maxPlayers = self.maxPlayers
    }

    func startHosting() {
        guard isHost, !isAdvertising else { return }
        // Opening a kitchen cancels any teardown `closeKitchen` still has in
        // flight. Backing out of the waiting room and straight back in beats
        // that 250ms by less than the cover animation takes, and the deferred
        // `leave()` landing here would stop the transport of the kitchen that
        // is now on screen — leaving a waiting room that advertises nothing.
        closeGeneration &+= 1
        isAdvertising = true
        transport.startHosting(kitchenName: kitchenName)
        // A resumed match must not be dragged back to the lobby — it is
        // already under way, just frozen until the chefs find their way back.
        if !isMidMatch { phase = .lobby }
        saveHostRoom()
    }

    // MARK: Coming back from the background
    //
    // iOS suspends the app, and suspension kills the listener, every socket,
    // and every Timer with it. Nothing restarts them by itself — which meant
    // the pause feature rescued the dramatic case (the app being killed) while
    // missing by far the commonest one: somebody taking a phone call.
    //
    // These two are wired to UIApplication notifications in `listen()`, so the
    // session looks after itself rather than needing every screen that owns one
    // to remember to forward the scene phase.

    /// Only the host freezes on the way out, and only the host.
    ///
    /// A guest that froze itself here would have nothing to unfreeze it: the
    /// host is fine, so no `.resumeCountdown` is ever coming, and a short trip
    /// to Notification Center doesn't necessarily kill the socket — so the
    /// reconnect path wouldn't run either. The guest would sit out the full
    /// ninety seconds and then be ejected from a perfectly healthy match. A
    /// guest that genuinely loses its connection is caught by `handleLoss`,
    /// which is the honest signal; a suspended app renders nothing anyway.
    private func handleDidEnterBackground() {
        guard isHost, isMidMatch else { return }
        // Freeze deliberately and say so, while the sockets are still alive
        // enough to carry it. The alternative is every guest discovering it for
        // themselves a few seconds later via a dead connection.
        pauseMatch()
    }

    private func handleWillEnterForeground() {
        if isHost {
            // The listener did not survive suspension. Re-advertise under the
            // same name, code and room id so the frozen guests — who are
            // browsing for exactly that — find their way back.
            guard isAdvertising || isMidMatch else { return }
            isAdvertising = false
            startHosting()
            // If the sockets happened to survive — a very short trip to the
            // home screen — there is nobody to wait for, so don't sit out the
            // full ninety seconds before noticing.
            if isPaused, connectedCount >= players.count { resumeMatch() }
        } else if isMidMatch, !snapshot.isOver, hostPeer == nil, targetKitchenName != nil {
            // Our socket is gone too. Start hunting again rather than sitting
            // on a rejoin loop whose browser was torn down while we were away.
            //
            // Gated on being mid-match so a player who already gave up — phase
            // `.hostLeft`, transport stopped — isn't quietly put back on a
            // two-second retry loop with no deadline behind it by nothing more
            // than a trip to the home screen.
            transport.startBrowsing()
            if rejoinTask == nil { scheduleRejoin() }
        }
    }

    func startBrowsing() {
        guard !isHost else { return }
        transport.startBrowsing()
        phase = .searching
    }

    // MARK: Ready

    /// Toggle this device's Ready lamp. Guests ask the host; the host decides
    /// for everyone, so two people readying in the same frame can't produce two
    /// different opinions about whether the room is unanimous.
    func setReady(_ ready: Bool) {
        guard phase == .lobby else { return }
        if isHost {
            applyReady(ready, for: localPlayerID)
        } else if let hostPeer {
            // Set it locally too, or the lamp lags a whole round trip behind
            // the thumb. The host's roster broadcast overwrites this a moment
            // later, so a rejected toggle self-corrects.
            if let index = players.firstIndex(where: { $0.id == localPlayerID }) {
                players[index].isReady = ready
            }
            transport.send(.ready(ready), to: hostPeer)
        }
    }

    private func applyReady(_ ready: Bool, for id: String) {
        guard isHost, phase == .lobby,
              let index = players.firstIndex(where: { $0.id == id }),
              players[index].isReady != ready else { return }

        players[index].isReady = ready
        broadcastLobby()

        // Un-readying is a veto: it has to be able to stop a countdown that is
        // already running, otherwise the button is a lie for three seconds.
        if everyoneReady { beginStartCountdown() } else { cancelCountdown() }
    }

    /// Everyone said yes — count down and open the book by ourselves.
    private func beginStartCountdown() {
        guard isHost, countdownTask == nil else { return }
        let generation = nextCountdownGeneration()
        countdownTask = Task { [weak self] in
            // Every exit from here MUST clear `countdownTask`, including the
            // "someone un-readied at 1" bail below. A finished-but-non-nil task
            // fails the guard above forever, and since the ready gate is now the
            // only way out of the lobby, that would wedge the room permanently.
            defer { self?.finishCountdown(generation) }

            for remaining in stride(from: PauseRules.startCountdown, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.startSecondsLeft = remaining
                self.transport.broadcast(.startCountdown(seconds: remaining))
                try? await Task.sleep(for: .seconds(1))
            }
            // Re-checked at zero rather than trusted from three seconds ago: a
            // chef can walk in, drop out, or change their mind mid-count.
            guard let self, !Task.isCancelled, self.everyoneReady else { return }
            self.startSecondsLeft = nil
            self.transport.broadcast(.startCountdown(seconds: 0))
            self.startCooking()
        }
    }

    /// Countdowns are identified by generation rather than by object.
    ///
    /// A cancelled task still runs its `defer`, and it does so *after* whatever
    /// cancelled it has already started the next countdown. Without the
    /// generation check that late tidy-up would nil out a live task and wedge
    /// the room — the exact failure the tidy-up exists to prevent.
    private func nextCountdownGeneration() -> Int {
        countdownGeneration &+= 1
        return countdownGeneration
    }

    /// Tidy up after a countdown however it ended.
    ///
    /// If it was interrupted — someone un-readied, or a fourth chef walked in
    /// mid-count — the guests are still showing a number, so they get an
    /// explicit "never mind". Without it their Ready button stays replaced by a
    /// frozen "1" for the rest of the lobby.
    private func finishCountdown(_ generation: Int) {
        guard countdownGeneration == generation else { return }
        countdownTask = nil
        guard startSecondsLeft != nil else { return }
        startSecondsLeft = nil
        transport.broadcast(.startCountdown(seconds: nil))
    }

    private func cancelCountdown() {
        _ = nextCountdownGeneration()
        countdownTask?.cancel()
        countdownTask = nil
        let wasStarting = startSecondsLeft != nil
        startSecondsLeft = nil
        resumeSecondsLeft = nil
        if isHost && wasStarting { transport.broadcast(.startCountdown(seconds: nil)) }
    }

    // MARK: Pause and resume
    //
    // A frozen kitchen is the whole point of this section. The alternative —
    // what the game used to do — is that the host vanishing ends everyone
    // else's match at whatever moment the Wi-Fi happened to hiccup. Freezing
    // costs nothing to the players who are still there and turns a lost game
    // into a ninety-second wait.

    /// Stop the kitchen where it stands. Host side.
    ///
    /// `announce` is false when the pause is part of rebuilding a saved room:
    /// there is nobody connected yet to tell, and broadcasting into an empty
    /// listener is just noise.
    private func pauseMatch(announce: Bool = true) {
        // A finished match is not a match. Nothing moves the phase away from
        // `.playing` when the clock runs out, so without `!game.isOver` the
        // last guest leaving would freeze the kitchen *over the results
        // screen* — the pause card outranks it — and then close the room
        // ninety seconds later while the host was still reading their score.
        guard isHost, isMidMatch, !game.isOver else { return }

        // Note the deliberate absence of a plain `!isPaused` guard. A kitchen
        // three seconds into its resume countdown when the chefs drop *again*
        // is still nominally paused, and bailing here would let that countdown
        // run to completion and unfreeze a room with nobody left in it.
        guard !isPaused || resumeSecondsLeft != nil else { return }

        ticker?.invalidate()
        ticker = nil
        cancelCountdown()
        // Only stamp the freeze start on the way *in*. Re-stamping it when an
        // already-paused kitchen re-pauses would throw away the elapsed time
        // that `rebaseServeClocks` needs to shift the serve holds by.
        if pausedAt == nil { pausedAt = Date.timeIntervalSinceReferenceDate }
        isPaused = true
        if announce { transport.broadcast(.paused) }
        beginPauseDeadline()
        saveHostRoom()
    }

    /// The chefs are back. Count everyone in and start the clock again.
    func resumeMatch() {
        guard isHost, isPaused, isMidMatch, connectedCount >= 2 else { return }
        cancelPauseDeadline()
        rebaseServeClocks()
        runResumeCountdown()
    }

    /// Wall-clock timestamps have no idea the game stopped.
    ///
    /// `serveHolds` and `serveChargeStartedAt` are absolute times, and
    /// `resolveServe` expires a hold that has been waiting longer than
    /// `gatherWindow`. Without this, ninety seconds of pause silently expires
    /// every hold in the room and the serve bar everyone was halfway through
    /// empties itself the instant play resumes. Shifting them forward by the
    /// length of the freeze makes the pause invisible to that logic.
    private func rebaseServeClocks() {
        guard let pausedAt else { return }
        let frozenFor = Date.timeIntervalSinceReferenceDate - pausedAt
        serveHolds = serveHolds.mapValues { $0 + frozenFor }
        if let started = serveChargeStartedAt {
            serveChargeStartedAt = started + frozenFor
        }
        self.pausedAt = nil
    }

    private func runResumeCountdown() {
        guard resumeSecondsLeft == nil else { return }   // already counting in
        countdownTask?.cancel()
        let generation = nextCountdownGeneration()
        countdownTask = Task { [weak self] in
            defer { self?.finishCountdown(generation) }

            for remaining in stride(from: PauseRules.resumeCountdown, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.resumeSecondsLeft = remaining
                self.transport.broadcast(.resumeCountdown(seconds: remaining))
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled else { return }
            self.resumeSecondsLeft = nil

            // Three seconds is long enough for the kitchen to empty out again.
            // Unfreezing anyway would leave the host cooking alone against a
            // clock nobody else can see — worse than staying paused.
            guard self.connectedCount >= 2 else {
                self.transport.broadcast(.paused)
                self.pausedAt = Date.timeIntervalSinceReferenceDate
                self.beginPauseDeadline()
                self.saveHostRoom()
                return
            }

            self.transport.broadcast(.resumeCountdown(seconds: 0))
            self.isPaused = false
            if self.phase == .playing { self.startTicking() }
            self.saveHostRoom()
        }
    }

    /// Shut the kitchen deliberately, and say so.
    ///
    /// Distinct from simply going quiet: a guest that hears this stops waiting
    /// immediately instead of freezing for ninety seconds on a host who has
    /// already walked away.
    func closeKitchen() {
        guard isHost else { return }
        transport.broadcast(.kitchenClosed)
        RoomResumeStore.clearHost()
        // Stop advertising immediately even though the sockets linger, so the
        // 250ms below can't be spent letting a new guest into a kitchen that
        // has already said goodbye.
        isAdvertising = false
        // Sockets are torn down a beat later, exactly as in `reject`: cancelling
        // a connection is not obliged to flush what was already queued on it,
        // and a goodbye nobody receives leaves the room frozen for ninety
        // seconds waiting for a host who is already gone.
        closeGeneration &+= 1
        let generation = closeGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            // If the session has been reopened in the meantime — backing out
            // and straight into a new kitchen is two taps — this deferred
            // teardown must not reach in and stop the transport of a session
            // that has already moved on.
            guard let self, self.closeGeneration == generation else { return }
            self.leave()
        }
    }

    /// Guest taps a kitchen and supplies the code the host is displaying.
    ///
    /// Bonjour lists ghosts. A host killed by Xcode's stop button never sends
    /// a goodbye packet, so its advert lingers in the mDNS cache for minutes.
    /// Tapping one would otherwise sit on a spinner for the full TCP timeout,
    /// so we give the host a few seconds to say literally anything back.
    func join(kitchen: DiscoveredKitchen, code: RoomCode) {
        guard !isHost else { return }
        errorText = nil
        // Belt and braces alongside `leave()`: this is a *fresh* join, so any
        // membership of a previous room must not ride along in the handshake.
        targetRoomID = nil
        resumeToken = nil
        joiningKitchenID = kitchen.id
        // The name, not just the endpoint. When the host's app relaunches its
        // Bonjour endpoint is brand new and the id we were handed is worthless
        // — the name is the only thread back to the same kitchen.
        targetKitchenName = kitchen.name
        submittedCode = code
        phase = .verifying("Connecting…")
        transport.connect(toKitchen: kitchen.id)

        joinTimeout?.cancel()
        joinTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled, self.phase.isVerifying else { return }
            self.abandonJoin(kitchenID: kitchen.id)
        }
    }

    /// Walk straight back into the kitchen this device was in when the app
    /// last closed — no room list, no code to re-type.
    ///
    /// The saved room supplies everything the handshake needs: which kitchen to
    /// look for, which room it must actually be, and the token proving we were
    /// already admitted to it. If the host is still up we are back in seconds;
    /// if it isn't, `scheduleRejoin` keeps looking until the caller gives up.
    func resumeAsGuest(_ saved: SavedGuestRoom) {
        guard !isHost else { return }
        errorText = nil
        targetKitchenName = saved.kitchenName
        targetRoomID = saved.roomID
        resumeToken = saved.resumeToken
        submittedCode = RoomCode(saved.code)
        kitchenName = saved.kitchenName
        phase = .verifying("Looking for \(saved.kitchenName)…")
        transport.startBrowsing()
        scheduleRejoin()
    }

    private func abandonJoin(kitchenID: String) {
        joinTimeout?.cancel()
        joinTimeout = nil
        // Drop the dead row so it can't be tapped again, and let the browser
        // re-add it if it turns out to be alive after all.
        discovered.removeAll { $0.id == kitchenID }
        errorText = "That kitchen isn't there any more"
        phase = .searching
        transport.startBrowsing()
    }

    /// Any reply at all proves the host is alive — stand the timer down.
    private func hostAnswered() {
        joinTimeout?.cancel()
        joinTimeout = nil
    }

    /// Lobby → recipe book. Called by the host's "Start cooking" button.
    ///
    /// This used to drop straight into the kitchen and start the clock. It now
    /// stops at the briefing, because two minutes is short enough that reading
    /// the recipe has to be free.
    func startCooking() {
        guard isHost, canStart else { return }
        occupancy.removeAll()
        heldStation = nil
        pendingClaim = nil
        // Ready lamps belong to the lobby. Carrying them into the match would
        // mean a second round starts with everyone still ready from the first.
        for index in players.indices { players[index].isReady = false }
        transport.broadcast(.start)
        phase = .briefing
        broadcastLobby()
        saveHostRoom()
    }

    /// Recipe book → kitchen. Called by the head chef's START signpost, and
    /// the only place the clock ever begins.
    ///
    /// Host-only by design: if a guest could start the game, one player still
    /// reading page two would lose time to someone else's impatience.
    ///
    /// ⚠️ Head chef == host today (see `headChefID`). The day the randomiser
    /// can hand the apron to a guest, that guest's START needs a new
    /// guest→host message asking the host to run this — a guest broadcasting
    /// it themselves would start a clock the host isn't ticking.
    func beginCooking() {
        guard isHost, phase == .briefing else { return }
        transport.broadcast(.beginCooking)
        phase = .playing
        // A briefing that was frozen mid-read resumes into a *paused* kitchen,
        // not a running one — the head chef pressing START while half the room
        // is still reconnecting would start their clock without them.
        if !isPaused { startTicking() }
        saveHostRoom()
    }

    /// Closes the kitchen but keeps this object usable — the views that own it
    /// outlive a dismissal, so a player backing out and starting again must get
    /// a working session, not a dead one.
    func leave() {
        // Invalidates any teardown `closeKitchen` has in flight — this one is
        // happening now, and a second one landing 250ms into the next kitchen
        // would stop a transport that has just been started.
        closeGeneration &+= 1
        rejoinTask?.cancel()
        rejoinTask = nil
        verifyTimeout?.cancel()
        joinTimeout?.cancel()
        cancelPauseDeadline()
        cancelCountdown()
        ticker?.invalidate()
        ticker = nil
        gate?.finish()
        gate = nil
        transport.stop()
        joinQueue.removeAll()
        occupancy.removeAll()
        serveZone.removeAll()
        serveHolds.removeAll()
        serveChargeStartedAt = nil
        lastSentServeReady = false
        lastSentServeHold = false
        heldStation = nil
        pendingClaim = nil
        verifying = nil
        peerToPlayer.removeAll()
        playerToPeer.removeAll()
        hostPeer = nil
        isAdvertising = false
        isPaused = false
        pausedAt = nil
        pauseSecondsLeft = nil
        resumeSecondsLeft = nil
        startSecondsLeft = nil
        // Every trace of which kitchen we belonged to. Views keep their session
        // as a @StateObject across a dismissal, so backing out of one kitchen
        // and into another reuses this object — and a leftover `targetRoomID`
        // would have us introduce ourselves to the new host as a member of the
        // old room, which it would (correctly) reject as `.wrongRoom`.
        targetKitchenName = nil
        joiningKitchenID = nil
        targetRoomID = nil
        resumeToken = nil
        submittedCode = nil
        // A guest's roster belongs to the kitchen it came from. Leaving it
        // behind would show the old room's chefs in the next lobby until the
        // first broadcast arrived. The host keeps its own roster — that is the
        // room, and `configure` guards on it being a party of one.
        if isHost {
            // A host that leaves and starts again is opening a *new* kitchen,
            // so it gets a new room id, new digits and a clean set of tables.
            // Reusing the old ones would let a chef from the previous game walk
            // straight back in on a stale resume token, into a half-cooked
            // recipe. (The roster keeps its single host entry, which is what
            // `configure` checks to decide the kitchen is still unopened.)
            ticket = .fresh(kitchenName: kitchenName, maxPlayers: maxPlayers)
            roomCode = RoomCode(ticket.code) ?? roomCode
            resumeTokens.removeAll()
            game.reset()
            deposited.removeAll()
            stationOutput.removeAll()
            drawerSlots = Array(repeating: nil, count: Drawer.slotCount)
            utensilStock = StoragePantry.defaultUtensilStock
            players = players.filter { $0.id == localPlayerID }
            for index in players.indices { players[index].isReady = false }
        } else {
            // A guest's roster belongs to the kitchen it came from. Leaving it
            // behind would show the old room's chefs in the next lobby until
            // the first broadcast arrived.
            players.removeAll()
            // The rows too. `transport.stop()` above throws away the endpoints
            // behind them, so every kitchen still listed is now untappable —
            // better an empty "looking for kitchens…" than a list that fails.
            discovered.removeAll()
        }
        chefs = chefs.filter { isHost && $0.key == localPlayerID }
        snapshot = .empty
        errorText = nil
        // Walking out on purpose means there is nothing to come back to. Any
        // other exit — a crash, a lock screen, a dead socket — deliberately
        // leaves the written-down room alone, because that file is the only
        // way back into it.
        if isHost { RoomResumeStore.clearHost() } else { RoomResumeStore.clearGuest() }
        phase = .idle
    }

    // MARK: Writing the room down

    /// Snapshot the host's authoritative tables to disk.
    ///
    /// Called on every transition that changes what a returning chef would
    /// need, plus every couple of seconds while the clock runs. The cost is one
    /// small JSON blob into UserDefaults; the benefit is that a host whose app
    /// is killed can reopen the *same* kitchen rather than a new one nobody has
    /// the code for.
    private func saveHostRoom() {
        guard isHost else { return }
        let stage: SavedHostRoom.Stage
        switch phase {
        case .briefing: stage = .briefing
        case .playing:  stage = .playing
        case .lobby:    stage = .lobby
        default:        return      // idle, rejected, hostLeft — nothing to keep
        }
        // A finished match is not resumable, and offering to reopen it would
        // drop everyone back into an end screen they already dismissed.
        guard !game.isOver else {
            RoomResumeStore.clearHost()
            return
        }
        RoomResumeStore.saveHost(
            SavedHostRoom(ticket: ticket,
                          stage: stage,
                          players: players,
                          resumeTokens: resumeTokens,
                          completed: Array(game.completed),
                          timeRemaining: game.timeRemaining,
                          chefs: players.compactMap { chefs[$0.id] },
                          utensilStock: utensilStock,
                          deposited: deposited,
                          drawer: drawerSlots,
                          stationOutput: stationOutput,
                          savedAt: Date()))
    }

    private func saveGuestRoom() {
        guard !isHost,
              let roomID = targetRoomID,
              let token = resumeToken,
              let code = submittedCode?.digits else { return }
        RoomResumeStore.saveGuest(
            SavedGuestRoom(roomID: roomID,
                           code: code,
                           kitchenName: targetKitchenName ?? kitchenName,
                           resumeToken: token,
                           wasMidMatch: isMidMatch,
                           savedAt: Date()))
    }

    // MARK: Reports from KitchenScene

    /// Called from the SpriteKit update loop — sixty times a second. Guests
    /// throttle to roughly the host's broadcast rate; sending every frame
    /// floods the socket with positions nobody will ever render.
    func reportPosition(x: Double, y: Double, station: String?, isBusy: Bool) {
        // Nobody moves in a frozen kitchen. The scene stops its own loop too,
        // but a report that slipped through would be rebroadcast to everyone
        // and slide one chef across a still frame.
        guard !isFrozen else { return }
        if isHost {
            chefs[localPlayerID] = ChefSnapshot(playerID: localPlayerID, x: x, y: y,
                                                station: station, isBusy: isBusy)
            return
        }
        guard let hostPeer else { return }

        let now = Date.timeIntervalSinceReferenceDate
        let moved = abs(x - lastSentX) > 0.002 || abs(y - lastSentY) > 0.002
        let stateChanged = station != lastSentStation || isBusy != lastSentBusy
        guard stateChanged || (moved && now - lastSentAt >= 0.1) else { return }

        lastSentAt = now
        lastSentX = x
        lastSentY = y
        lastSentStation = station
        lastSentBusy = isBusy
        transport.send(.moveTo(x: x, y: y, station: station, isBusy: isBusy), to: hostPeer)
    }

    func reportCompletion(actionID: Int) {
        // Serving never arrives this way. It is the one action that isn't a
        // station minigame, and accepting it here would mean a single device
        // could end the game as a win with nobody gathered — the exact thing
        // the ritual exists to prevent. See `resolveServe`.
        guard actionID != ServeRitual.actionID else { return }
        // Minigames are stopped while frozen, so anything arriving here during
        // a pause finished on a clock that was supposed to be off.
        guard !isFrozen else { return }

        if isHost {
            guard let action = Recipe.action(actionID) else { return }
            applyCompletion(action, at: heldStation, claimant: localPlayerID)
        } else if let hostPeer {
            transport.send(.finishedAction(id: actionID), to: hostPeer)
        }
    }

    // MARK: Serving together
    //
    // The rule: every connected chef has to be standing in the serve zone, and
    // then all of them have to hold SERVE at the same time until the bar fills.
    //
    // Both halves are judged by the host and nowhere else. Guests report where
    // they are and when they pressed; whether that adds up to a served cake is
    // never their call. That is also why a press is stored as a *timestamp*
    // rather than a flag — presses expire by themselves, so a mistimed serve
    // simply doesn't happen instead of needing to be undone.

    /// Called by the scene as the chef walks in and out of the circle.
    func reportServeReady(_ inZone: Bool) {
        guard !isFrozen else { return }
        // Edge-triggered, but reconciled against what the host actually thinks.
        // The host wipes the zone on a disconnect and again after a serve, and
        // a purely local flag would then never speak up again — leaving a chef
        // standing in the circle that nobody can see them in.
        let hostHasUs = snapshot.serveReady.contains(localPlayerID)
        guard inZone != lastSentServeReady || inZone != hostHasUs else { return }
        lastSentServeReady = inZone

        if isHost {
            setServeReady(localPlayerID, inZone)
        } else if let hostPeer {
            transport.send(.serveReady(inZone), to: hostPeer)
        }
    }

    /// Called as this device's SERVE button goes down and comes back up.
    func setServeHold(_ holding: Bool) {
        // Letting go still counts while frozen — a thumb lifted during the
        // pause is a thumb that is off the button when play resumes. Only new
        // presses are refused.
        guard !isFrozen || !holding else { return }
        guard holding != lastSentServeHold else { return }
        lastSentServeHold = holding

        if isHost {
            registerServeHold(localPlayerID, holding)
        } else if let hostPeer {
            transport.send(.serveHold(holding), to: hostPeer)
        }
    }

    private func setServeReady(_ id: String, _ inZone: Bool) {
        if inZone {
            serveZone.insert(id)
        } else {
            // Walking off your mark drops your hold with you. Otherwise you
            // could press, wander away, and still count towards the serve.
            serveZone.remove(id)
            serveHolds.removeValue(forKey: id)
        }
    }

    private func registerServeHold(_ id: String, _ holding: Bool) {
        guard holding else {
            serveHolds.removeValue(forKey: id)
            return
        }
        guard serveIsArmed else { return }
        // Keep the original timestamp if they're already holding: re-sending
        // must not refresh your own gather window and let you lean on the
        // button indefinitely while the others sort themselves out.
        if serveHolds[id] == nil {
            serveHolds[id] = Date.timeIntervalSinceReferenceDate
        }
    }

    /// Everyone still connected is standing in the circle, and there is
    /// actually a cake to serve.
    private var serveIsArmed: Bool {
        guard let serve = ServeRitual.action, game.isUnlocked(serve) else { return false }

        let here = Set(players.filter(\.isConnected).map(\.id))
        guard !here.isEmpty, here.isSubset(of: serveZone) else { return false }

        // A dropped player's slot is held so the recipe stays winnable, and
        // "everyone connected" would otherwise mean the last chef standing can
        // serve alone the moment the others blip. A kitchen that started with
        // company has to still have company.
        return players.count < 2 || here.count >= 2
    }

    /// Runs inside the host's tick — the whole serve, judged in one place.
    ///
    /// Two phases, and the second only exists while the first is perfectly
    /// true:
    ///   1. Gathering. Anyone can hold. A hold nobody joins within
    ///      `gatherWindow` is dropped, so the button pops back out on its own.
    ///   2. Charging. The instant *everyone* is holding, the bar starts. Any
    ///      hand off the button — or any chef off their mark — empties it.
    private func resolveServe() {
        // The clock is checked before this in `tick`, and `complete` doesn't
        // consult `isOver` — without this a serve resolving on the very tick
        // time ran out would flip a loss into a win.
        guard !game.isOver else {
            serveHolds.removeAll()
            serveChargeStartedAt = nil
            return
        }

        let alive = Set(players.filter(\.isConnected).map(\.id))
        serveZone.formIntersection(alive)
        serveHolds = serveHolds.filter { alive.contains($0.key) }

        let now = Date.timeIntervalSinceReferenceDate
        let everyoneHolding = !alive.isEmpty && alive.isSubset(of: Set(serveHolds.keys))

        guard serveIsArmed else {
            // Someone stepped off. Nothing survives that.
            serveHolds.removeAll()
            serveChargeStartedAt = nil
            return
        }

        if !everyoneHolding {
            // Phase one. Drop holds that have been waiting alone too long —
            // this is what makes an early press quietly release itself instead
            // of banking a head start.
            serveHolds = serveHolds.filter { now - $0.value <= ServeRitual.gatherWindow }
            serveChargeStartedAt = nil
            return
        }

        // Phase two.
        let startedAt = serveChargeStartedAt ?? now
        serveChargeStartedAt = startedAt

        guard now - startedAt >= ServeRitual.chargeDuration,
              let serve = ServeRitual.action else { return }

        game.complete(serve)
        serveZone.removeAll()
        serveHolds.removeAll()
        serveChargeStartedAt = nil
    }

    /// How full the bar is right now, 0...1.
    private var serveProgress: Double {
        // Completing clears `serveChargeStartedAt`, so without this the last
        // thing the team sees is the bar snapping back to empty at the exact
        // moment they won.
        if game.completed.contains(ServeRitual.actionID) { return 1 }
        guard let startedAt = serveChargeStartedAt else { return 0 }
        let elapsed = Date.timeIntervalSinceReferenceDate - startedAt
        return min(1, max(0, elapsed / ServeRitual.chargeDuration))
    }

    /// Host-authoritative completion — used whether the host itself finished the
    /// action or a guest reported it. Marks it done, consumes the deposits,
    /// leaves the prep on the station, and frees the station lock.
    private func applyCompletion(_ action: CookAction, at worked: StationID?, claimant: String?) {
        guard isHost else { return }
        // The bowls are interchangeable, so a chef can perform a bowl1 action
        // standing at bowl2. Consume the deposits and leave the prep at the
        // counter they actually worked, not at the one the recipe declares.
        let station = (worked ?? stationHeld(by: claimant, for: action) ?? action.station).rawValue
        game.complete(action)
        deposited[station] = nil
        if let output = action.output {
            stationOutput[station] = output
        }
        if let claimant, occupancy[station] == claimant {
            occupancy.removeValue(forKey: station)
        }
    }

    /// Which station this player holds that can run this action — how the host
    /// tells bowl1 from bowl2 for a completion reported by a guest.
    private func stationHeld(by playerID: String?, for action: CookAction) -> StationID? {
        guard let playerID else { return nil }
        for (key, holder) in occupancy where holder == playerID {
            if let id = StationID(rawValue: key), GameState.sharesActions(id, action.station) {
                return id
            }
        }
        return nil
    }

    // MARK: Station locks
    //
    // One player per station. The host owns the lock table, so two chefs
    // arriving in the same frame are serialised by the order their claims
    // reach the host rather than by whoever's animation happened to finish
    // first. A refused claim isn't an error — the chef simply stands there and
    // the claim is retried automatically when the station frees up.

    /// Called by KitchenScene the moment a chef finishes walking to a station.
    /// The station screen must not open until `heldStation` comes back matching.
    func claimStation(_ station: StationID) {
        // A lock handed out during a freeze would be held by someone who can't
        // use it, in a kitchen where nobody can see them holding it.
        guard !isFrozen else { return }
        guard phase == .playing else {
            // Offline or pre-game there is nobody to contend with.
            heldStation = station
            return
        }
        if heldStation == station { return }

        // Standing somewhere new — drop whatever we were holding first, so a
        // player can never sit on two stations at once.
        if let held = heldStation, held != station { releaseStation() }
        pendingClaim = station

        if isHost {
            resolveClaim(station: station.rawValue, playerID: localPlayerID, peer: nil)
        } else if let hostPeer {
            transport.send(.claimStation(station: station.rawValue), to: hostPeer)
        }
    }

    /// Called when the chef finishes the action, backs out, or walks away.
    func releaseStation() {
        let leaving = heldStation ?? pendingClaim
        heldStation = nil
        pendingClaim = nil
        guard let leaving, phase == .playing else { return }

        if isHost {
            if occupancy[leaving.rawValue] == localPlayerID {
                occupancy.removeValue(forKey: leaving.rawValue)
            }
        } else if let hostPeer {
            transport.send(.releaseStation(station: leaving.rawValue), to: hostPeer)
        }
    }

    // MARK: Storage + deposit
    //
    // Same shape as station claims: the host owns the counts and the bowls, so
    // guests send intent and read the answer off the snapshot (stock, deposits)
    // or a direct reply (utensil grant/out).

    /// Take a utensil off the shelf. `returning` is the tool the chef was
    /// already holding, so it goes back. Offline/host resolves immediately.
    func requestUtensil(_ id: String, returning: String?) {
        if isHost || phase != .playing {
            grantUtensil(id: id, returning: returning, to: nil)
        } else if let hostPeer {
            transport.send(.requestUtensil(id: id, returning: returning), to: hostPeer)
        }
    }

    /// Drop the held ingredient into the station the chef is standing at.
    func deposit(_ foodID: String, at station: StationID) {
        if isHost || phase != .playing {
            depositFood(foodID, at: station.rawValue)
        } else if let hostPeer {
            transport.send(.deposit(station: station.rawValue, foodID: foodID), to: hostPeer)
        }
    }

    /// Take the finished prep off a station (into the caller's hand). Returns
    /// the foodID that was there, or nil if the station was empty.
    @discardableResult
    func pickUpOutput(at station: StationID) -> String? {
        let food = outputFood(at: station)
        guard food != nil else { return nil }
        if isHost || phase != .playing {
            stationOutput[station.rawValue] = nil
        } else if let hostPeer {
            transport.send(.pickUpOutput(station: station.rawValue), to: hostPeer)
        }
        return food
    }

    /// The prep waiting on a station (host reads its table; guest the snapshot).
    func outputFood(at station: StationID) -> String? {
        isHost ? stationOutput[station.rawValue] : snapshot.outputFood(at: station)
    }

    /// Seconds left on the kitchen clock (host reads its own game; guest the
    /// snapshot) — the same host-aware split `outputFood` and `depositedFoods`
    /// use, and for the same reason: a solo session never starts the 10Hz tick
    /// that refreshes the snapshot, so a direct snapshot read would show a
    /// clock frozen at 15:00 for the whole round.
    var secondsRemaining: TimeInterval {
        isHost ? game.timeRemaining : snapshot.timeRemaining
    }

    /// Ingredients dropped at a station so far (host table / guest snapshot).
    func depositedFoods(at station: StationID) -> [String] {
        isHost ? (deposited[station.rawValue] ?? []) : snapshot.depositedFoods(at: station)
    }

    /// Take one previously-dropped ingredient back off a station (into hand).
    @discardableResult
    func takeDeposit(_ foodID: String, at station: StationID) -> Bool {
        guard depositedFoods(at: station).contains(foodID) else { return false }
        if isHost || phase != .playing {
            takeDepositFood(foodID, at: station.rawValue)
        } else if let hostPeer {
            transport.send(.takeDeposit(station: station.rawValue, foodID: foodID), to: hostPeer)
        }
        return true
    }

    private func takeDepositFood(_ foodID: String, at station: String) {
        guard let idx = deposited[station]?.firstIndex(of: foodID) else { return }
        deposited[station]?.remove(at: idx)
        if deposited[station]?.isEmpty == true { deposited[station] = nil }
    }

    /// Consumed by StorageView once it has acted on a grant/out reply.
    func clearUtensilReply() { utensilReply = nil }

    /// Put the held item on a drawer shelf. The hand is only emptied once the
    /// answer comes back, so a refusal can't destroy an ingredient.
    func storeInDrawer(_ item: DrawerItem, slot: Int) {
        if isHost || phase != .playing {
            resolveStore(item, slot: slot, to: nil)
        } else if let hostPeer {
            transport.send(.requestStoreDrawer(slot: slot, item: item), to: hostPeer)
        }
    }

    /// Take whatever is on a drawer shelf.
    func takeFromDrawer(slot: Int) {
        if isHost || phase != .playing {
            resolveTake(slot: slot, to: nil)
        } else if let hostPeer {
            transport.send(.requestTakeDrawer(slot: slot), to: hostPeer)
        }
    }

    /// Consumed by DrawerView once it has acted on a reply.
    func clearDrawerReply() { drawerReply = nil }

    /// What's on a shelf — from the host's own table, or the snapshot mirror.
    func drawerItem(inSlot index: Int) -> DrawerItem? {
        let slots = isHost ? drawerSlots : snapshot.drawer
        guard index >= 0, index < slots.count else { return nil }
        return slots[index]
    }

    /// Host-authoritative shelving. `peer == nil` means the host itself asked.
    private func resolveStore(_ item: DrawerItem, slot: Int, to peer: PeerID?) {
        guard slot >= 0, slot < drawerSlots.count else { return }

        let answer: NetMessage
        let local: DrawerReply

        // Occupancy is the only thing a shelf can refuse on now — the
        // per-food temperature rule that used to be checked here is gone
        // (see `Drawer` in DrawerStation.swift).
        if drawerSlots[slot] != nil {
            let reason = Drawer.occupiedMessage
            answer = .drawerRefused(slot: slot, reason: reason)
            local = .refused(slot: slot, reason: reason)
        } else {
            drawerSlots[slot] = item
            answer = .drawerStored(slot: slot)
            local = .stored(slot: slot)
        }

        if let peer { transport.send(answer, to: peer) } else { drawerReply = local }
    }

    /// Host-authoritative retrieval. Two chefs reaching for the same shelf are
    /// serialised here, so the second one gets nil rather than a duplicate.
    private func resolveTake(slot: Int, to peer: PeerID?) {
        guard slot >= 0, slot < drawerSlots.count else { return }
        let item = drawerSlots[slot]
        drawerSlots[slot] = nil
        if let peer {
            transport.send(.drawerTaken(slot: slot, item: item), to: peer)
        } else {
            drawerReply = .took(slot: slot, item: item)
        }
    }

    /// Host-authoritative utensil hand-out. `peer == nil` means the host itself
    /// asked, so the answer is published locally instead of sent.
    private func grantUtensil(id: String, returning: String?, to peer: PeerID?) {
        if (utensilStock[id] ?? 0) > 0 {
            utensilStock[id, default: 0] -= 1
            if let returning { utensilStock[returning, default: 0] += 1 }
            if let peer { transport.send(.utensilGranted(id: id), to: peer) }
            else { utensilReply = UtensilReply(id: id, granted: true) }
        } else {
            if let peer { transport.send(.utensilOut(id: id), to: peer) }
            else { utensilReply = UtensilReply(id: id, granted: false) }
        }
    }

    /// Host-authoritative deposit. Ignores a duplicate of something already in.
    private func depositFood(_ foodID: String, at station: String) {
        if deposited[station]?.contains(foodID) == true { return }
        deposited[station, default: []].append(foodID)
    }

    /// Read helpers so views/scene don't need to know host vs guest.
    func utensilsLeft(_ id: String) -> Int {
        isHost ? (utensilStock[id] ?? 0) : (snapshot.utensilStock[id] ?? 0)
    }

    /// Re-sends a claim that was refused earlier, but only once the station is
    /// actually free — otherwise this would turn into a request flood.
    private func retryPendingClaim() {
        guard let pending = pendingClaim, heldStation == nil, phase == .playing else { return }
        if isHost {
            guard occupancy[pending.rawValue] == nil else { return }
            resolveClaim(station: pending.rawValue, playerID: localPlayerID, peer: nil)
        } else {
            guard snapshot.holder(of: pending) == nil, let hostPeer else { return }
            transport.send(.claimStation(station: pending.rawValue), to: hostPeer)
        }
    }

    /// Host-side adjudication. `peer` is nil when the host is claiming for
    /// itself, in which case the verdict is applied directly instead of sent.
    private func resolveClaim(station: String, playerID: String, peer: PeerID?) {
        guard isHost else { return }

        // A player may hold only one station, so an earlier lock is dropped.
        // Without this, walking away mid-action would strand the old station.
        for (key, holder) in occupancy where holder == playerID && key != station {
            occupancy.removeValue(forKey: key)
        }

        if let holder = occupancy[station], holder != playerID {
            if let peer {
                transport.send(.stationDenied(station: station,
                                              holderID: holder), to: peer)
            } else {
                heldStation = nil   // host keeps `pendingClaim` and waits its turn
            }
            return
        }

        occupancy[station] = playerID
        if let peer {
            transport.send(.stationGranted(station: station), to: peer)
        } else {
            heldStation = StationID(rawValue: station)
            pendingClaim = nil
        }
    }

    /// Host-side cleanup: drop every lock a player is holding. Used when they
    /// disconnect and when the game ends.
    private func releaseAll(for playerID: String) {
        guard isHost else { return }
        for (key, holder) in occupancy where holder == playerID {
            occupancy.removeValue(forKey: key)
        }
        // Someone who dropped is not standing in the serve zone, whatever they
        // last reported. Leaving them in it would let the rest of the kitchen
        // serve without them — or, worse, never be able to.
        serveZone.remove(playerID)
        serveHolds.removeValue(forKey: playerID)
        serveChargeStartedAt = nil
    }

    // MARK: Host — snapshot loop

    private func startTicking() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        // Belt and braces: `pauseMatch` invalidates the ticker, but a timer
        // already in flight when it did would otherwise steal one more tenth of
        // a second off a clock that is supposed to be stopped.
        guard isHost, !isFrozen else { return }
        game.tick(0.1)

        // A lock held by a player who has since vanished from the roster would
        // close a station for the rest of the game with nobody to reopen it.
        let living = Set(players.map(\.id))
        occupancy = occupancy.filter { living.contains($0.value) }
        if game.isOver {
            occupancy.removeAll()
            heldStation = nil
            pendingClaim = nil
        }

        // The host is a player too, so its own queued claim needs the same
        // "did it free up yet?" pass the guests get when a snapshot lands.
        retryPendingClaim()

        // Presses expire on a clock, so this has to run every tick rather than
        // only when one arrives.
        resolveServe()

        var shot = GameSnapshot(completed: Array(game.completed),
                                timeRemaining: game.timeRemaining,
                                isOver: game.isOver,
                                didWin: game.didWin,
                                chefs: players.compactMap { chefs[$0.id] },
                                occupancy: occupancy)
        shot.utensilStock = utensilStock
        shot.deposited = deposited
        shot.drawer = drawerSlots
        shot.serveReady = Array(serveZone)
        shot.serveArmed = serveIsArmed
        shot.serveHolding = Array(serveHolds.keys)
        shot.serveProgress = serveProgress
        shot.stationOutput = stationOutput
        snapshot = shot
        transport.broadcast(.snapshot(shot))

        // Write the room down a couple of times a second. Ten UserDefaults
        // writes a second would be silly; losing two seconds of progress when
        // the app is killed is not worth noticing.
        ticksSinceSave += 1
        if ticksSinceSave >= 20 {
            ticksSinceSave = 0
            saveHostRoom()
        }

        if game.isOver {
            ticker?.invalidate()
            ticker = nil
            // A finished match is not something to be resumed into.
            RoomResumeStore.clearHost()
        }
    }

    // MARK: Event handling

    private func handle(_ event: TransportEvent) {
        switch event {
        case .discoveryChanged(let kitchens):
            discovered = kitchens
            // Don't make a reconnecting player wait out the two-second retry
            // when the kitchen they're looking for has just this moment
            // reappeared in the browse results.
            //
            // Gated on `rejoinTask` rather than on having a target: a *first*
            // join also has a target the whole time it is handshaking, and
            // connecting again on top of that would leave the host holding two
            // sockets for one chef.
            if rejoinTask != nil, hostPeer == nil { attemptRejoin() }

        case .connectedToHost(let peer):
            hostPeer = peer
            phase = .verifying(resumeToken == nil ? "Checking the code…" : "Getting you back in…")
            transport.send(.hello(id: localPlayerID,
                                  name: PlayerIdentityStore.current.name,
                                  code: submittedCode?.digits ?? "",
                                  supportsRanging: ProximityGate.isSupported,
                                  roomID: targetRoomID,
                                  resume: resumeToken),
                           to: peer)

        case .peerConnected:
            break   // host waits for `hello` before doing anything

        case .peerLost(let peer):
            handleLoss(of: peer)

        case .received(let message, let peer):
            handle(message, from: peer)

        case .failed(let text):
            errorText = text
            // A failure while still handshaking means the join never landed —
            // drop back to the list rather than stranding the guest on a
            // spinner that will never resolve.
            if phase.isVerifying { phase = .searching }
            // And put the browser back up. `BonjourTransport.stop()` empties
            // its endpoint table, so after backing out of one kitchen every
            // row still on screen points at an endpoint the transport can no
            // longer resolve — tapping any of them fails here, forever, with
            // nothing left to repopulate the list. This is that repopulation.
            if !isHost, hostPeer == nil, phase != .idle,
               !phase.isRejected, phase != .hostLeft {
                transport.startBrowsing()
            }
        }
    }

    private func handle(_ message: NetMessage, from peer: PeerID) {
        if !isHost { hostAnswered() }

        switch message {

        // ---- host side ----

        case .hello(let id, let name, let code, let supportsRanging, let roomID, let resume):
            guard isHost else { return }
            admitOrReject(peer: peer, id: id, name: name, code: code,
                          supportsRanging: supportsRanging,
                          roomID: roomID, resume: resume)

        case .ready(let ready):
            guard isHost, let id = peerToPlayer[peer] else { return }
            applyReady(ready, for: id)

        case .moveTo(let x, let y, let station, let isBusy):
            guard isHost, let id = peerToPlayer[peer] else { return }
            chefs[id] = ChefSnapshot(playerID: id, x: x, y: y,
                                     station: station, isBusy: isBusy)

        case .finishedAction(let id):
            // A guest claiming it "finished" the serve would end the game for
            // everyone with nobody in the circle. Serving is decided in
            // `resolveServe` and nowhere else.
            guard id != ServeRitual.actionID else { return }
            guard isHost, let action = Recipe.action(id) else { return }
            applyCompletion(action, at: nil, claimant: peerToPlayer[peer])

        case .claimStation(let station):
            guard isHost, let id = peerToPlayer[peer] else { return }
            resolveClaim(station: station, playerID: id, peer: peer)

        case .releaseStation(let station):
            guard isHost, let id = peerToPlayer[peer] else { return }
            if occupancy[station] == id { occupancy.removeValue(forKey: station) }

        case .requestUtensil(let id, let returning):
            guard isHost else { return }
            grantUtensil(id: id, returning: returning, to: peer)

        case .serveReady(let inZone):
            guard isHost, let id = peerToPlayer[peer] else { return }
            setServeReady(id, inZone)

        case .serveHold(let holding):
            guard isHost, let id = peerToPlayer[peer] else { return }
            registerServeHold(id, holding)

        case .deposit(let station, let foodID):
            guard isHost else { return }
            depositFood(foodID, at: station)

        case .requestStoreDrawer(let slot, let item):
            guard isHost else { return }
            resolveStore(item, slot: slot, to: peer)

        case .requestTakeDrawer(let slot):
            guard isHost else { return }
            resolveTake(slot: slot, to: peer)
        case .pickUpOutput(let station):
            guard isHost else { return }
            stationOutput[station] = nil

        case .takeDeposit(let station, let foodID):
            guard isHost else { return }
            takeDepositFood(foodID, at: station)

        // ---- guest side ----

        case .queued(let position):
            phase = .verifying(position <= 1 ? "You're next…" : "\(position) ahead of you…")

        case .rangingRequest:
            break   // token arrives immediately after; nothing to do

        case .joinAccepted(let player, let roomID, let resume):
            hostPeer = peer
            // We're in — stop counting down to giving up, and stop hunting.
            rejoinTask?.cancel()
            rejoinTask = nil
            cancelPauseDeadline()
            targetRoomID = roomID
            resumeToken = resume
            // We are back in a kitchen that is, as far as we know, running. Any
            // freeze we were holding was ours — our own socket died, or we were
            // waiting on a host who has now answered — so it ends here.
            //
            // If the kitchen is in fact still paused, `.paused` arrives on this
            // same connection immediately after and freezes us again. TCP and
            // the transport's ordered hop guarantee it lands after this, which
            // is the only reason clearing first is safe.
            isPaused = false
            resumeSecondsLeft = nil
            saveGuestRoom()
            // Only a fresh join lands in the lobby. A reconnection is caught up
            // by the `start`/`beginCooking`/`paused` messages that follow, and
            // bouncing through `.lobby` on the way would flash the waiting room
            // over a match already in progress.
            if !isMidMatch { phase = .lobby }
            if let index = players.firstIndex(where: { $0.id == player.id }) {
                players[index] = player
            } else {
                players.append(player)
            }

        case .joinRejected(let reason):
            // A reconnection that gets turned away is final: the kitchen we
            // remember is not the kitchen that answered. Stop retrying, or we
            // spend the next ninety seconds being rejected every two.
            rejoinTask?.cancel()
            rejoinTask = nil
            cancelPauseDeadline()
            unfreeze()
            RoomResumeStore.clearGuest()
            phase = .rejected(reason)
            transport.disconnect(peer)

        case .lobby(let name, let max, let roster):
            guard !isHost else { return }
            kitchenName = name
            maxPlayers = max
            players = roster

        case .start:
            guard !isHost else { return }
            phase = .briefing
            startSecondsLeft = nil
            // Re-written now the match is under way, so a relaunch offers to
            // walk us back in rather than treating this as an abandoned lobby.
            saveGuestRoom()

        case .beginCooking:
            guard !isHost else { return }
            phase = .playing
            saveGuestRoom()

        case .startCountdown(let seconds):
            guard !isHost else { return }
            startSecondsLeft = (seconds ?? 0) > 0 ? seconds : nil

        case .paused:
            guard !isHost else { return }
            // Sent both when the host steps away mid-match and to anyone who
            // reconnects while the freeze is still on, so a returning chef
            // lands in the same held breath as everyone else rather than alone
            // in a kitchen that looks live but isn't.
            freezeForHost()

        case .resumeCountdown(let seconds):
            guard !isHost else { return }
            if seconds > 0 {
                // The deadline deliberately keeps running through the count.
                // The guest has no local timer for the resume — it is driven
                // entirely by these broadcasts — so a host that dies silently
                // between "3" and "0" (a crash or a yanked Wi-Fi sends no FIN,
                // so no socket death to notice) would strand everyone on "3"
                // until TCP keepalive gave up minutes later. It stays hidden:
                // the overlay shows the countdown, not the bar, while it runs.
                resumeSecondsLeft = seconds
            } else {
                cancelPauseDeadline()
                resumeSecondsLeft = nil
                isPaused = false
            }

        case .kitchenClosed:
            guard !isHost else { return }
            // The host left on purpose. No freeze, no ninety seconds — there is
            // nothing to wait for.
            rejoinTask?.cancel()
            rejoinTask = nil
            cancelPauseDeadline()
            unfreeze()
            RoomResumeStore.clearGuest()
            transport.stop()
            phase = .hostLeft

        case .stationGranted(let station):
            // Only accept a grant for the station we're actually still queued
            // for. Walking from A to B while the grant for A is in flight would
            // otherwise clear the pending claim on B and strand us at a counter
            // that never opens.
            guard !isHost, pendingClaim?.rawValue == station else { return }
            heldStation = pendingClaim
            pendingClaim = nil

        case .stationDenied(let station, let holderID):
            guard !isHost, pendingClaim?.rawValue == station else { return }
            // Stay queued. The chef keeps standing there and the retry fires
            // as soon as a snapshot shows the station empty.
            heldStation = nil
            // Patch the local mirror so the "X is using this" nudge appears
            // now instead of up to a snapshot later. The next snapshot
            // overwrites this anyway, so a wrong guess self-corrects.
            snapshot.occupancy[station] = holderID

        case .utensilGranted(let id):
            guard !isHost else { return }
            utensilReply = UtensilReply(id: id, granted: true)

        case .utensilOut(let id):
            guard !isHost else { return }
            utensilReply = UtensilReply(id: id, granted: false)

        case .drawerStored(let slot):
            guard !isHost else { return }
            drawerReply = .stored(slot: slot)

        case .drawerRefused(let slot, let reason):
            guard !isHost else { return }
            drawerReply = .refused(slot: slot, reason: reason)

        case .drawerTaken(let slot, let item):
            guard !isHost else { return }
            drawerReply = .took(slot: slot, item: item)

        case .snapshot(let shot):
            guard !isHost else { return }
            snapshot = shot
            // A finished match is not resumable, so the ticket back into it is
            // dead weight — and leaving it would have the start screen offering
            // to rejoin a game everyone already saw the results of.
            if shot.isOver { RoomResumeStore.clearGuest() }
            // A station we're queued for may have just freed up.
            retryPendingClaim()
            // The host is the authority on who holds what, so if it says we
            // don't hold our station any more, we don't — drop the claim and
            // let the scene close the screen.
            if let held = heldStation, shot.holder(of: held) != localPlayerID {
                heldStation = nil
            }

        // ---- both sides ----

        case .rangingToken(let data):
            Task { await handleToken(data, from: peer) }
        }
    }

    // MARK: Host — admission

    private func admitOrReject(peer: PeerID, id: String, name: String,
                               code: String, supportsRanging: Bool,
                               roomID: String?, resume: String?) {
        // A device that names a room is reconnecting. If it names the wrong
        // one, its kitchen is gone and something else is advertising under the
        // same name — say so plainly instead of letting a code collision drop
        // it into a stranger's game.
        if let roomID, roomID != ticket.roomID {
            reject(peer, .wrongRoom)
            return
        }

        // A token this host issued is stronger evidence than the code: it can
        // only exist because this exact device was already admitted to this
        // exact room. That is what lets a reconnection skip the four digits.
        let hasTicketBack = resume != nil && resumeTokens[id] == resume

        // Cheap checks first — no reason to spin up a radio to reject a typo.
        guard hasTicketBack || code == roomCode.digits else {
            reject(peer, .wrongCode)
            return
        }
        if game.isOver {
            reject(peer, .alreadyStarted)
            return
        }
        let returning = hasTicketBack || players.contains { $0.id == id }
        if !returning && players.count >= maxPlayers {
            reject(peer, .kitchenFull)
            return
        }

        // A returning player already proved they were in the room. Re-ranging
        // them mid-game would stall the lobby for no new information.
        guard supportsRanging, ProximityGate.isSupported, !returning else {
            admit(peer: peer, id: id, name: name)
            return
        }

        joinQueue.append(PendingJoin(peer: peer, id: id, name: name,
                                     supportsRanging: supportsRanging))
        notifyQueuePositions()
        advanceQueue()
    }

    /// Everyone waiting gets told where they are in line. Position 0 is the
    /// guest about to be ranged.
    private func notifyQueuePositions() {
        for (offset, waiting) in joinQueue.enumerated() {
            transport.send(.queued(position: offset), to: waiting.peer)
        }
    }

    /// One ranging session at a time. This is the whole trick that makes UWB
    /// workable with four players.
    private func advanceQueue() {
        guard verifying == nil, !joinQueue.isEmpty else { return }
        let next = joinQueue.removeFirst()
        verifying = next

        let gate = ProximityGate()
        self.gate = gate
        guard let token = gate.makeToken() else {
            finishVerification(admitting: true)
            return
        }
        transport.send(.rangingRequest, to: next.peer)
        transport.send(.rangingToken(token), to: next.peer)

        // A guest that connects and then goes quiet — permission dialog left
        // sitting, app backgrounded — would otherwise hold `verifying` forever
        // and freeze the queue for everyone behind them. Fail open after six
        // seconds: the room code still had to be right to get this far.
        verifyTimeout?.cancel()
        verifyTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled,
                  self.verifying?.peer == next.peer else { return }
            self.finishVerification(admitting: true)
        }
    }

    private func handleToken(_ data: Data, from peer: PeerID) async {
        if isHost {
            guard let pending = verifying, pending.peer == peer, let gate else { return }
            let verdict = await gate.verdict(against: data)
            if case .tooFar = verdict {
                reject(peer, .tooFarAway)
                finishVerification(admitting: false)
            } else {
                finishVerification(admitting: true)
            }
        } else {
            // Guest: run our own session so the host gets a reading, and send
            // our token back. We never look at the distance ourselves.
            let gate = ProximityGate()
            self.gate = gate
            phase = .verifying("Checking you're in the room…")
            guard let token = gate.makeToken() else { return }
            transport.send(.rangingToken(token), to: peer)
            _ = await gate.measure(against: data)
            gate.finish()
            self.gate = nil
        }
    }

    private func finishVerification(admitting: Bool) {
        verifyTimeout?.cancel()
        verifyTimeout = nil
        gate?.finish()
        gate = nil
        if admitting, let pending = verifying {
            admit(peer: pending.peer, id: pending.id, name: pending.name)
        }
        verifying = nil
        advanceQueue()
    }

    private func admit(peer: PeerID, id: String, name: String) {
        let player: Player
        if let index = players.firstIndex(where: { $0.id == id }) {
            // Returning player reclaims their original slot and colour.
            players[index].isConnected = true
            players[index].name = name
            // Back from a drop is not the same as back from thinking about it:
            // a returning chef has to press Ready again, so the lobby can't
            // auto-start on a lamp they lit before they disappeared.
            if phase == .lobby { players[index].isReady = false }
            player = players[index]
        } else {
            let used = Set(players.map(\.colorIndex))
            let colour = (0..<PlayerPalette.rgb.count).first { !used.contains($0) } ?? 0
            player = Player(id: id, name: name, isHost: false,
                            isConnected: true, colorIndex: colour)
            players.append(player)
            // Spawned on their own spot in the middle of the ring — the same
            // place the whole team has to return to in order to serve.
            let spawn = ServeRitual.spawnUnitPosition(forColorIndex: colour)
            chefs[id] = ChefSnapshot(playerID: id, x: Double(spawn.x), y: Double(spawn.y),
                                     station: nil, isBusy: false)
        }
        // Anyone arriving in the lobby — new face or returning one — lands
        // not-ready, so a room that was unanimous a second ago isn't any more.
        // Stopping the countdown here, rather than letting it run to zero and
        // bail, is what stops everyone watching "3… 2… 1…" and then nothing.
        if phase == .lobby { cancelCountdown() }
        peerToPlayer[peer] = id
        playerToPeer[id] = peer

        // Issued once and kept for the life of the room. Reusing it means a
        // player can drop and return as many times as they like — including
        // across the host's own app relaunch, since the tokens are saved with
        // the room — without ever seeing the code screen again.
        let token = resumeTokens[id] ?? UUID().uuidString
        resumeTokens[id] = token
        transport.send(.joinAccepted(player: player,
                                     roomID: ticket.roomID,
                                     resume: token), to: peer)

        // Catch a late arrival up to wherever everyone else already is. A guest
        // admitted during the briefing gets the book; one admitted mid-game
        // skips it, because the kitchen is already open and the clock is
        // already running.
        switch phase {
        case .briefing:
            transport.send(.start, to: peer)
        case .playing:
            // Straight to the kitchen — sending `.start` first would flash the
            // recipe book for a frame on a game that is already running.
            transport.send(.beginCooking, to: peer)
        default:
            break
        }
        // ...and if the kitchen is currently holding its breath, they hold it
        // too. Landing in a live-looking kitchen that nobody else can move in
        // is worse than landing in an obviously frozen one.
        if isPaused { transport.send(.paused, to: peer) }

        broadcastLobby()
        saveHostRoom()

        // Everyone who was here is here again — start the 3, 2, 1.
        if isPaused, connectedCount >= max(2, players.count) { resumeMatch() }
    }

    private func reject(_ peer: PeerID, _ reason: JoinRejection) {
        transport.send(.joinRejected(reason: reason), to: peer)
        joinQueue.removeAll { $0.peer == peer }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.transport.disconnect(peer)
        }
    }

    private func broadcastLobby() {
        guard isHost else { return }
        transport.broadcast(.lobby(kitchenName: kitchenName,
                                   maxPlayers: maxPlayers,
                                   players: players))
    }

    // MARK: Disconnection

    private func handleLoss(of peer: PeerID) {
        if isHost {
            joinQueue.removeAll { $0.peer == peer }
            if verifying?.peer == peer { finishVerification(admitting: false) }

            guard let id = peerToPlayer.removeValue(forKey: peer) else { return }
            // A late `peerLost` for a socket this player has already replaced
            // must not tear down the live one — that would strip the lock they
            // were just granted and drop them from the roster while connected.
            guard playerToPeer[id] == peer else { return }
            playerToPeer.removeValue(forKey: id)

            // Whatever they were working at is now nobody's. Holding the lock
            // for a player who might never come back would make the recipe
            // unwinnable for everyone still in the kitchen.
            releaseAll(for: id)

            if isMidMatch {
                // Mid-game: hold the slot so their chef doesn't vanish from the
                // kitchen and the recipe stays winnable. They can reclaim it.
                //
                // The briefing counts as mid-game here. It is human-paced — as
                // long as it takes to read fourteen steps aloud — so it is the
                // likeliest place to blip, and dropping the slot would hand a
                // returning chef a new colour or a "kitchen full" rejection.
                if let index = players.firstIndex(where: { $0.id == id }) {
                    players[index].isConnected = false
                }
                // Last one out freezes the kitchen. A host cooking alone while
                // everybody else reconnects is burning a clock they can't win
                // on — far more likely to be the host's own Wi-Fi that dropped
                // than three guests leaving at once.
                if connectedCount <= 1 { pauseMatch() }
            } else {
                // In the lobby: free the slot for someone else, as requested.
                players.removeAll { $0.id == id }
                chefs.removeValue(forKey: id)
                // Re-ask the question rather than only cancelling: the chef who
                // just walked out may have been the one everybody was waiting
                // on, in which case the room is unanimous now that they're gone.
                if everyoneReady { beginStartCountdown() } else { cancelCountdown() }
            }
            broadcastLobby()
            saveHostRoom()
        } else {
            guard peer == hostPeer else { return }
            hostPeer = nil
            // Our lock lived on the host and has just been dropped there, so
            // stop believing we hold it — otherwise the station screen stays
            // open over a frozen kitchen.
            heldStation = nil
            pendingClaim = nil
            lastSentServeReady = false
            lastSentServeHold = false
            if isMidMatch {
                // Grey ourselves out too. Without this the reconnecting player
                // sees a frozen kitchen and no explanation for it.
                //
                // Briefing included: a drop while the head chef is still
                // reading has to auto-rejoin like any other, or the player sits
                // on "head chef is reading…" until the game ends without them.
                if let index = players.firstIndex(where: { $0.id == localPlayerID }) {
                    players[index].isConnected = false
                }
                // And grey out the host, which is who we actually lost. The
                // overlay names the chefs we're waiting on, and "waiting for
                // nobody in particular" is not a useful thing to tell someone
                // staring at a still frame.
                if let index = players.firstIndex(where: \.isHost) {
                    players[index].isConnected = false
                }
                // THE FIX. The kitchen stops instead of ending. Everything is
                // held exactly where it was — clock, bowls, half-finished
                // minigames — and we wait for the host rather than dumping
                // three people out of a game they were winning.
                //
                // Both halves are gated on the match still being live. The
                // phase never leaves `.playing` when the clock runs out, so
                // without this the host tapping "Back to the menu" from the
                // results screen would put every guest on an unbounded
                // two-second browse-and-connect loop over a finished game.
                if !snapshot.isOver {
                    freezeForHost()
                    scheduleRejoin()
                }
            } else if !phase.isRejected {
                // A rejection already closed the socket on purpose — don't
                // overwrite the reason with a generic "host left".
                phase = .hostLeft
            }
        }
    }

    // MARK: Guest — waiting for the host

    /// Lift the freeze completely.
    ///
    /// Both halves, always, together. `isFrozen` is `isPaused ||
    /// resumeSecondsLeft != nil`, and clearing only the first leaves the views
    /// still frozen — showing the resume card, which has no button on it,
    /// behind a scrim that eats every tap. That is a force-quit, and it is
    /// reachable: the grace deadline deliberately keeps running through the
    /// 3-2-1 so a host that dies silently mid-countdown can't strand anyone.
    private func unfreeze() {
        isPaused = false
        resumeSecondsLeft = nil
    }

    private func freezeForHost() {
        // Same reason as the host's guard in `pauseMatch`: the host tapping
        // "Back to the menu" from the results screen drops our socket, and
        // freezing then would bury our own score under a pause card for ninety
        // seconds. The match is over — there is nothing left to hold still.
        guard !snapshot.isOver else { return }
        isPaused = true
        resumeSecondsLeft = nil
        // Re-stamp the ticket home. `savedAt` is what `RoomResumeStore.window`
        // measures, and for a full-length match the record written at join time
        // would have expired by the time it was needed — which is exactly now.
        saveGuestRoom()
        // Re-arm rather than early-return when already frozen. A guest who
        // reconnects into a still-paused kitchen has just had its deadline
        // cancelled by `joinAccepted`; without this it would wait behind an
        // overlay with no bar and no number, indefinitely.
        if pauseDeadline == nil { beginPauseDeadline() }
    }

    /// Ninety seconds of patience, counted out loud so the wait has a shape.
    ///
    /// Both sides run it, for the same reason and on the same clock: an
    /// unbounded freeze would be worse than the bug it replaces — at least a
    /// closed kitchen tells you to go and do something else. What differs is
    /// only what happens at zero.
    private func beginPauseDeadline() {
        pauseDeadline?.cancel()
        pauseSecondsLeft = PauseRules.graceSeconds
        pauseDeadline = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, let left = self.pauseSecondsLeft else { return }
                guard left > 1 else {
                    self.pauseSecondsLeft = nil
                    self.pauseDeadline = nil
                    self.patienceRanOut()
                    return
                }
                self.pauseSecondsLeft = left - 1
            }
        }
    }

    private func cancelPauseDeadline() {
        pauseDeadline?.cancel()
        pauseDeadline = nil
        pauseSecondsLeft = nil
    }

    private func patienceRanOut() {
        guard isPaused else { return }
        if isHost {
            // Carry on with whoever made it back. The missing chef's slot is
            // still held, so this is a "start without them", not a kick — they
            // can still walk in later and pick up their own colour.
            if connectedCount >= 2 { resumeMatch() } else { closeKitchen() }
        } else {
            giveUpOnHost()
        }
    }

    /// The host never came back. Close the kitchen for real.
    private func giveUpOnHost() {
        rejoinTask?.cancel()
        rejoinTask = nil
        cancelPauseDeadline()
        unfreeze()
        // The room is gone, so the ticket back into it is worthless. Leaving it
        // on disk would have the start screen offering to rejoin a kitchen that
        // stopped existing a minute and a half ago.
        RoomResumeStore.clearGuest()
        transport.stop()
        phase = .hostLeft
    }

    /// Guest-side auto-rejoin, retried every two seconds until the host turns
    /// up or the patience runs out.
    ///
    /// The original version connected to `joiningKitchenID` — a Bonjour
    /// endpoint string — and that is precisely why a host who relaunched could
    /// never be rejoined: the endpoint is minted with the process, so the id we
    /// were holding pointed at a socket that no longer existed. We now try the
    /// old endpoint first (instant, for a host that only blipped) and fall back
    /// to matching the kitchen's name, with `roomID` in the handshake to make
    /// sure the name led us somewhere real.
    private func scheduleRejoin() {
        rejoinTask?.cancel()
        rejoinTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.hostPeer == nil else { return }
                self.transport.startBrowsing()
                self.attemptRejoin()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func attemptRejoin() {
        guard !isHost, hostPeer == nil else { return }

        // A host that merely blipped is still advertising on the endpoint we
        // already know, and reconnecting there needs no search at all.
        if let id = joiningKitchenID, discovered.contains(where: { $0.id == id }) {
            transport.connect(toKitchen: id)
            return
        }
        // Otherwise the host's app restarted. Find the kitchen by name; the
        // room id we send in `hello` is what stops us walking into a different
        // kitchen that happens to be called the same thing.
        guard let name = targetKitchenName,
              let match = discovered.first(where: { $0.name == name }) else { return }
        joiningKitchenID = match.id
        transport.connect(toKitchen: match.id)
    }
}
