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
//  failure: if the host leaves, the game ends. Host migration is deliberately
//  out of scope.
//
//  Joining is gated twice. The room code proves the guest can see the host's
//  screen, which is the only same-room evidence that does not depend on
//  radios or walls. The UWB check is a bonus that fails open.
//

import Foundation
import Combine

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

    let role: Role
    let localPlayerID: String

    var isHost: Bool { role == .host }
    var connectedCount: Int { players.filter(\.isConnected).count }
    var canStart: Bool { isHost && connectedCount >= 2 && phase == .lobby }
    var localPlayer: Player? { players.first { $0.id == localPlayerID } }

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

    private var chefs: [String: ChefSnapshot] = [:]
    private var peerToPlayer: [PeerID: String] = [:]
    private var playerToPeer: [String: PeerID] = [:]
    private var joinQueue: [PendingJoin] = []
    private var verifying: PendingJoin?
    private var gate: ProximityGate?

    private var verifyTimeout: Task<Void, Never>?
    private var joinTimeout: Task<Void, Never>?

    // Guest only
    private var hostPeer: PeerID?
    private var joiningKitchenID: String?
    private var submittedCode: RoomCode?
    private var rejoinTask: Task<Void, Never>?

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
    init(role: Role,
         kitchenName: String = "",
         maxPlayers: Int = 4,
         transport: KitchenTransport? = nil) {
        self.role = role
        self.kitchenName = kitchenName
        self.maxPlayers = max(2, min(maxPlayers, PlayerPalette.rgb.count))
        self.transport = transport ?? BonjourTransport()
        self.roomCode = .random()
        self.localPlayerID = PlayerIdentityStore.current.id

        if role == .host {
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

    // Task inherits this class's @MainActor isolation, so the stream is
    // consumed on the main actor and no hops are needed here.
    private func listen() {
        pump = Task { [weak self] in
            guard let self else { return }
            for await event in self.transport.events {
                self.handle(event)
            }
        }
    }

    // MARK: Lifecycle

    /// Host settings arrive from two different screens, so they're applied
    /// after init. Ignored once the kitchen is open — renaming a kitchen out
    /// from under connected guests would desync the roster.
    func configure(kitchenName: String, maxPlayers: Int) {
        guard isHost, phase == .idle else { return }
        self.kitchenName = kitchenName
        self.maxPlayers = max(2, min(maxPlayers, PlayerPalette.rgb.count))
    }

    func startHosting() {
        guard isHost else { return }
        transport.startHosting(kitchenName: kitchenName)
        phase = .lobby
    }

    func startBrowsing() {
        guard !isHost else { return }
        transport.startBrowsing()
        phase = .searching
    }

    /// Guest taps a kitchen and supplies the code the host is displaying.
    ///
    /// Bonjour lists ghosts. A host killed by Xcode's stop button never sends
    /// a goodbye packet, so its advert lingers in the mDNS cache for minutes.
    /// Tapping one would otherwise sit on a spinner for the full TCP timeout,
    /// so we give the host a few seconds to say literally anything back.
    func join(kitchen id: String, code: RoomCode) {
        guard !isHost else { return }
        errorText = nil
        joiningKitchenID = id
        submittedCode = code
        phase = .verifying("Connecting…")
        transport.connect(toKitchen: id)

        joinTimeout?.cancel()
        joinTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled, self.phase.isVerifying else { return }
            self.abandonJoin(kitchenID: id)
        }
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
        transport.broadcast(.start)
        phase = .briefing
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
        startTicking()
    }

    /// Closes the kitchen but keeps this object usable — the views that own it
    /// outlive a dismissal, so a player backing out and starting again must get
    /// a working session, not a dead one.
    func leave() {
        rejoinTask?.cancel()
        verifyTimeout?.cancel()
        joinTimeout?.cancel()
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
        phase = .idle
    }

    // MARK: Reports from KitchenScene

    /// Called from the SpriteKit update loop — sixty times a second. Guests
    /// throttle to roughly the host's broadcast rate; sending every frame
    /// floods the socket with positions nobody will ever render.
    func reportPosition(x: Double, y: Double, station: String?, isBusy: Bool) {
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

        if isHost {
            guard let action = Recipe.action(actionID) else { return }
            game.complete(action)
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

    /// Consumed by StorageView once it has acted on a grant/out reply.
    func clearUtensilReply() { utensilReply = nil }

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
        guard isHost else { return }
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
                                mess: game.mess,
                                timeRemaining: game.timeRemaining,
                                isOver: game.isOver,
                                didWin: game.didWin,
                                chefs: players.compactMap { chefs[$0.id] },
                                occupancy: occupancy)
        shot.utensilStock = utensilStock
        shot.deposited = deposited
        shot.serveReady = Array(serveZone)
        shot.serveArmed = serveIsArmed
        shot.serveHolding = Array(serveHolds.keys)
        shot.serveProgress = serveProgress
        snapshot = shot
        transport.broadcast(.snapshot(shot))
        if game.isOver {
            ticker?.invalidate()
            ticker = nil
        }
    }

    // MARK: Event handling

    private func handle(_ event: TransportEvent) {
        switch event {
        case .discoveryChanged(let kitchens):
            discovered = kitchens

        case .connectedToHost(let peer):
            hostPeer = peer
            phase = .verifying("Checking the code…")
            transport.send(.hello(id: localPlayerID,
                                  name: PlayerIdentityStore.current.name,
                                  code: submittedCode?.digits ?? "",
                                  supportsRanging: ProximityGate.isSupported),
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
        }
    }

    private func handle(_ message: NetMessage, from peer: PeerID) {
        if !isHost { hostAnswered() }

        switch message {

        // ---- host side ----

        case .hello(let id, let name, let code, let supportsRanging):
            guard isHost else { return }
            admitOrReject(peer: peer, id: id, name: name,
                          code: code, supportsRanging: supportsRanging)

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
            game.complete(action)
            // The ingredients that were dropped in are consumed by the action.
            deposited[action.station.rawValue] = nil
            // Free the station immediately rather than waiting for the guest's
            // own release to arrive — a completed action always ends the visit,
            // and a packet lost here would lock the station forever.
            if let claimant = peerToPlayer[peer],
               occupancy[action.station.rawValue] == claimant {
                occupancy.removeValue(forKey: action.station.rawValue)
            }

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

        // ---- guest side ----

        case .queued(let position):
            phase = .verifying(position <= 1 ? "You're next…" : "\(position) ahead of you…")

        case .rangingRequest:
            break   // token arrives immediately after; nothing to do

        case .joinAccepted(let player):
            hostPeer = peer
            phase = .lobby
            if !players.contains(where: { $0.id == player.id }) { players.append(player) }

        case .joinRejected(let reason):
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

        case .beginCooking:
            guard !isHost else { return }
            phase = .playing

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

        case .snapshot(let shot):
            guard !isHost else { return }
            snapshot = shot
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
                               code: String, supportsRanging: Bool) {
        // Cheap checks first — no reason to spin up a radio to reject a typo.
        guard code == roomCode.digits else {
            reject(peer, .wrongCode)
            return
        }
        if game.isOver {
            reject(peer, .alreadyStarted)
            return
        }
        let returning = players.contains { $0.id == id }
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
        peerToPlayer[peer] = id
        playerToPeer[id] = peer
        transport.send(.joinAccepted(player: player), to: peer)
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
        broadcastLobby()
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

            if phase == .playing || phase == .briefing {
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
            } else {
                // In the lobby: free the slot for someone else, as requested.
                players.removeAll { $0.id == id }
                chefs.removeValue(forKey: id)
            }
            broadcastLobby()
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
            if phase == .playing || phase == .briefing {
                // Grey ourselves out too. Without this the reconnecting player
                // sees a frozen kitchen and no explanation for it.
                //
                // Briefing included: a drop while the head chef is still
                // reading has to auto-rejoin like any other, or the player sits
                // on "head chef is reading…" until the game ends without them.
                if let index = players.firstIndex(where: { $0.id == localPlayerID }) {
                    players[index].isConnected = false
                }
                scheduleRejoin()
            } else if !phase.isRejected {
                // A rejection already closed the socket on purpose — don't
                // overwrite the reason with a generic "host left".
                phase = .hostLeft
            }
        }
    }

    /// Guest-side auto-rejoin: same kitchen, same code, retried every two
    /// seconds. The host matches us by persistent player ID, so we land back
    /// in our original slot with our original colour.
    private func scheduleRejoin() {
        rejoinTask?.cancel()
        rejoinTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.hostPeer == nil else { return }
                guard let id = self.joiningKitchenID else { return }
                self.transport.startBrowsing()
                self.transport.connect(toKitchen: id)
            }
        }
    }
}
