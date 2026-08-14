//
//  KitchenSession.swift
//  Cooked
//
//  Local multiplayer lobby over Network.framework + Bonjour.
//
//  Host advertises a Bonjour service named after the kitchen; guests browse
//  for it and connect. Messages are length-prefixed JSON. The host owns the
//  authoritative player roster and broadcasts it whenever it changes.
//
//  NOTE: Requires two Info.plist entries (see project setup):
//    • NSLocalNetworkUsageDescription (String)
//    • NSBonjourServices (Array) containing "_cookorcooked._tcp"
//  Local networking is unreliable simulator-to-simulator — test on devices.
//

import Foundation
import Network
import Combine

// MARK: - Model

struct Player: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var isHost: Bool
}

private enum NetMessage: Codable {
    case hello(id: String, name: String)                        // guest -> host
    case lobby(name: String, maxPlayers: Int, players: [Player]) // host -> guests
    case start                                                   // host -> guests
}

// MARK: - Session

@MainActor
final class KitchenSession: ObservableObject {
    static let serviceType = "_cookorcooked._tcp"

    enum Role { case host, guest }

    @Published private(set) var players: [Player] = []
    @Published private(set) var started = false
    @Published private(set) var discovered: [NWBrowser.Result] = []

    let role: Role
    let localPlayer: Player
    // Fixed for the host; filled in from the host's lobby broadcast for guests.
    @Published private(set) var kitchenName: String
    @Published private(set) var maxPlayers: Int

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []   // host: guests. guest: [host]

    init(role: Role, playerName: String, kitchenName: String = "", maxPlayers: Int = 0) {
        self.role = role
        self.kitchenName = kitchenName
        self.maxPlayers = maxPlayers
        self.localPlayer = Player(id: UUID().uuidString, name: playerName, isHost: role == .host)
        if role == .host {
            players = [localPlayer]
        }
    }

    var isFull: Bool { players.count >= maxPlayers }
    var canStart: Bool { role == .host && players.count >= 2 }

    // MARK: Host

    func startHosting() {
        guard role == .host else { return }
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        do {
            let listener = try NWListener(using: params)
            listener.service = NWListener.Service(name: kitchenName, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.acceptConnection(conn) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            print("KitchenSession: failed to start hosting — \(error)")
        }
    }

    private func acceptConnection(_ conn: NWConnection) {
        guard !isFull else {
            conn.cancel()
            return
        }
        connections.append(conn)
        conn.start(queue: .main)
        receiveHeader(on: conn)
    }

    private func broadcastRoster() {
        let msg = NetMessage.lobby(name: kitchenName, maxPlayers: maxPlayers, players: players)
        for conn in connections { send(msg, over: conn) }
    }

    func startCooking() {
        guard role == .host else { return }
        for conn in connections { send(.start, over: conn) }
        started = true
    }

    // MARK: Guest

    func startBrowsing() {
        guard role == .guest else { return }
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.discovered = Array(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func join(_ result: NWBrowser.Result) {
        guard role == .guest else { return }
        // Must match the parameters the browser and listener use. A plain
        // .tcp connection cannot reach an endpoint discovered over
        // peer-to-peer (AWDL), so the join silently times out instead.
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let conn = NWConnection(to: result.endpoint, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }
            Task { @MainActor in
                guard let self else { return }
                self.send(.hello(id: self.localPlayer.id, name: self.localPlayer.name), over: conn)
            }
        }
        connections = [conn]
        conn.start(queue: .main)
        receiveHeader(on: conn)
    }

    // MARK: Messaging

    nonisolated private func send(_ msg: NetMessage, over conn: NWConnection) {
        guard let payload = try? JSONEncoder().encode(msg) else { return }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        conn.send(content: frame, completion: .contentProcessed { _ in })
    }

    nonisolated private func receiveHeader(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, data.count == 4 {
                let length = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                self.receiveBody(on: conn, length: Int(length))
            } else if isComplete || error != nil {
                Task { @MainActor in self.remove(conn) }
            }
        }
    }

    nonisolated private func receiveBody(on conn: NWConnection, length: Int) {
        conn.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, let msg = try? JSONDecoder().decode(NetMessage.self, from: data) {
                Task { @MainActor in self.handle(msg, from: conn) }
            }
            if isComplete || error != nil {
                Task { @MainActor in self.remove(conn) }
            } else {
                self.receiveHeader(on: conn)
            }
        }
    }

    private func handle(_ msg: NetMessage, from conn: NWConnection) {
        switch msg {
        case .hello(let id, let name):
            guard role == .host else { return }
            if !players.contains(where: { $0.id == id }) {
                players.append(Player(id: id, name: name, isHost: false))
            }
            broadcastRoster()
        case .lobby(let name, let max, let list):
            guard role == .guest else { return }
            kitchenName = name
            maxPlayers = max
            players = list
        case .start:
            guard role == .guest else { return }
            started = true
        }
    }

    private func remove(_ conn: NWConnection) {
        conn.cancel()
        connections.removeAll { $0 === conn }
        // Host can't map a raw connection back to a player id here without more
        // bookkeeping; roster pruning on disconnect is a TODO.
    }

    func leave() {
        listener?.cancel()
        browser?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener = nil
        browser = nil
    }
}
