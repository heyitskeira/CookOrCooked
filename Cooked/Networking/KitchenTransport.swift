//
//  KitchenTransport.swift
//  Cooked
//
//  The network plumbing, behind a protocol so it can be replaced without the
//  game noticing. Today there is one implementation, BonjourTransport, built
//  on Network.framework.
//
//  DISCOVERY POLICY — this is the important line in the whole file:
//
//      params.includePeerToPeer = false
//
//  With it false, Bonjour traffic travels only over ordinary infrastructure
//  interfaces (en0), never AWDL. Two devices see each other if and only if
//  they are on the same Wi-Fi network. Flip it to true and nearby devices on
//  *different* networks start finding each other, which is a different
//  product. Proximity is enforced separately, by ProximityGate and the room
//  code — not by this flag.
//

import Foundation
import Network

// MARK: - Types

/// Opaque handle for one connected peer. The host holds several, a guest
/// holds exactly one (the host).
nonisolated struct PeerID: Hashable, Sendable {
    private let raw: UUID
    init() { raw = UUID() }
}

nonisolated struct DiscoveredKitchen: Identifiable, Equatable, Sendable {
    /// Stable across browse refreshes; hand this back to `connect(toKitchen:)`.
    let id: String
    let name: String
}

nonisolated enum TransportEvent {
    case peerConnected(PeerID)
    case peerLost(PeerID)
    case received(NetMessage, from: PeerID)
    case discoveryChanged([DiscoveredKitchen])
    /// Guest-side: the connection to the host went ready.
    case connectedToHost(PeerID)
    case failed(String)
}

// MARK: - Protocol

@MainActor
protocol KitchenTransport: AnyObject {
    var events: AsyncStream<TransportEvent> { get }

    func startHosting(kitchenName: String)
    func startBrowsing()
    func connect(toKitchen id: String)

    func send(_ message: NetMessage, to peer: PeerID)
    func broadcast(_ message: NetMessage)
    func disconnect(_ peer: PeerID)
    /// Closes sockets and stops advertising, but leaves the event stream open
    /// so the same object can host or browse again.
    func stop()
    /// Ends the event stream for good. Only at teardown.
    func shutdown()
}

// MARK: - Bonjour implementation

@MainActor
final class BonjourTransport: KitchenTransport {

    static let serviceType = "_cookorcooked._tcp"

    let events: AsyncStream<TransportEvent>
    private let feed: AsyncStream<TransportEvent>.Continuation

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [PeerID: NWConnection] = [:]
    private var endpoints: [String: NWEndpoint] = [:]

    init() {
        // Unbounded on purpose. Dropping the oldest event under a burst would
        // be harmless for a snapshot but fatal for a handshake message like
        // joinAccepted or start, and there is no error path for a lost one.
        (events, feed) = AsyncStream.makeStream(of: TransportEvent.self,
                                                bufferingPolicy: .unbounded)
    }

    // Same parameters on both sides. A connection built with different
    // parameters than the browser that discovered the endpoint will simply
    // time out rather than report an error, which is miserable to debug.
    private static func parameters() -> NWParameters {
        let params = NWParameters.tcp
        params.includePeerToPeer = false   // see the note at the top of this file
        return params
    }

    // MARK: Host

    func startHosting(kitchenName: String) {
        stopDiscovery()
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = NWListener.Service(name: kitchenName, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] conn in
                self?.hop { self?.accept(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard case .failed(let error) = state else { return }
                self?.hop { self?.feed.yield(.failed("Hosting failed: \(error.localizedDescription)")) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            feed.yield(.failed("Could not start hosting: \(error.localizedDescription)"))
        }
    }

    private func accept(_ conn: NWConnection) {
        let peer = PeerID()
        connections[peer] = conn
        conn.stateUpdateHandler = { [weak self] state in
            self?.hop {
                guard let self else { return }
                switch state {
                case .ready:
                    self.feed.yield(.peerConnected(peer))
                case .failed, .cancelled:
                    self.drop(peer)
                default:
                    break
                }
            }
        }
        conn.start(queue: .main)
        receiveNext(on: conn, peer: peer)
    }

    // MARK: Guest

    func startBrowsing() {
        stopDiscovery()
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil),
                                using: Self.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.hop { self?.publish(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            guard case .failed(let error) = state else { return }
            self?.hop { self?.feed.yield(.failed("Search failed: \(error.localizedDescription)")) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func publish(_ results: Set<NWBrowser.Result>) {
        var found: [DiscoveredKitchen] = []
        endpoints.removeAll()
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            let key = String(describing: result.endpoint)
            endpoints[key] = result.endpoint
            found.append(DiscoveredKitchen(id: key, name: name))
        }
        feed.yield(.discoveryChanged(found.sorted { $0.name < $1.name }))
    }

    func connect(toKitchen id: String) {
        guard let endpoint = endpoints[id] else {
            feed.yield(.failed("That kitchen is no longer available"))
            return
        }
        let peer = PeerID()
        let conn = NWConnection(to: endpoint, using: Self.parameters())
        connections[peer] = conn
        conn.stateUpdateHandler = { [weak self] state in
            self?.hop {
                guard let self else { return }
                switch state {
                case .ready:
                    self.feed.yield(.connectedToHost(peer))
                case .failed(let error):
                    self.feed.yield(.failed("Could not join: \(error.localizedDescription)"))
                    self.drop(peer)
                case .cancelled:
                    self.drop(peer)
                default:
                    break
                }
            }
        }
        conn.start(queue: .main)
        receiveNext(on: conn, peer: peer)
    }

    // MARK: Sending

    func send(_ message: NetMessage, to peer: PeerID) {
        guard let conn = connections[peer] else { return }
        write(message, to: conn)
    }

    func broadcast(_ message: NetMessage) {
        for conn in connections.values { write(message, to: conn) }
    }

    private func write(_ message: NetMessage, to conn: NWConnection) {
        guard let payload = try? JSONEncoder().encode(message) else { return }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        conn.send(content: frame, completion: .contentProcessed { _ in })
    }

    // MARK: Receiving
    //
    // Length-prefixed frames: four big-endian bytes, then that many bytes of
    // JSON. Each frame re-arms the loop exactly once — the original version of
    // this code could re-arm twice on a partial read and interleave frames.

    private nonisolated func receiveNext(on conn: NWConnection, peer: PeerID) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, data.count == 4 {
                let length = Int(data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
                guard length > 0, length < 4_000_000 else {
                    self.hop { self.drop(peer) }
                    return
                }
                self.receiveBody(on: conn, peer: peer, length: length)
            } else if isComplete || error != nil {
                self.hop { self.drop(peer) }
            } else {
                self.receiveNext(on: conn, peer: peer)
            }
        }
    }

    private nonisolated func receiveBody(on conn: NWConnection, peer: PeerID, length: Int) {
        conn.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, data.count == length,
               let message = try? JSONDecoder().decode(NetMessage.self, from: data) {
                self.hop { self.feed.yield(.received(message, from: peer)) }
            }
            if isComplete || error != nil {
                self.hop { self.drop(peer) }
            } else {
                self.receiveNext(on: conn, peer: peer)
            }
        }
    }

    // MARK: Teardown

    func disconnect(_ peer: PeerID) {
        connections[peer]?.cancel()
        drop(peer)
    }

    private func drop(_ peer: PeerID) {
        guard connections.removeValue(forKey: peer) != nil else { return }
        feed.yield(.peerLost(peer))
    }

    private func stopDiscovery() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
    }

    /// Note: deliberately does NOT finish the stream. Views own their session
    /// as a @StateObject and survive being dismissed, so backing out of a
    /// lobby and starting a new one reuses this object. Finishing here left it
    /// advertising happily while never delivering another event again.
    func stop() {
        stopDiscovery()
        for conn in connections.values { conn.cancel() }
        connections.removeAll()
        endpoints.removeAll()
    }

    func shutdown() {
        stop()
        feed.finish()
    }

    // Network.framework calls back on the queue we handed it (.main). That is
    // the main actor's executor, so hopping synchronously keeps message order
    // intact — a plain `Task { @MainActor in }` does not guarantee ordering,
    // and a reordered snapshot would visibly rewind the game.
    private nonisolated func hop(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            Task { @MainActor in body() }
        }
    }
}
