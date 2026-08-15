//
//  ProximityGate.swift
//  Cooked
//
//  Ultra-wideband distance check, used at exactly one moment: when a guest
//  asks to join. Not during play.
//
//  WHY ONLY AT JOIN TIME
//  UWB ranging is effectively pairwise — one active NISession does not yield
//  to another. Joins are sequential events, so the host can serialise them:
//  open a session with one guest, read a distance, tear it down, move to the
//  next. A full four-player lobby costs about six seconds of queueing, once,
//  and the radio is idle for the whole game afterwards.
//
//  Every failure path — no U1/U2 chip, permission denied, blocked line of
//  sight, timeout — resolves to `.unavailable`, and the caller falls back to
//  the room code. Ranging is a bonus check, never the only one.
//
//  Requires NSNearbyInteractionUsageDescription in Info.plist.
//  Does not work in the Simulator; needs two physical devices.
//

import Foundation
import NearbyInteraction

@MainActor
final class ProximityGate: NSObject {

    enum Verdict: Equatable {
        case near(Float)      // metres
        case tooFar(Float)
        case unavailable      // no hardware, no permission, or no reading

        var isPass: Bool {
            switch self {
            case .near, .unavailable: return true   // unavailable falls back to the code
            case .tooFar:             return false
            }
        }
    }

    /// Roughly a large room. Generous on purpose: a false "too far" is far
    /// more annoying than letting in someone just outside the doorway, and
    /// the room code is still doing the precise work.
    static let sameRoomMetres: Float = 8

    /// False on every iPhone SE, and on anything before iPhone 11.
    static var isSupported: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    private var session: NISession?
    private var waiter: CheckedContinuation<Float?, Never>?

    // MARK: Token exchange

    /// Opens a session and returns our discovery token, archived for sending.
    /// The peer needs this before it can range us back.
    func makeToken() -> Data? {
        guard Self.isSupported else { return nil }
        let session = NISession()
        session.delegate = self
        self.session = session
        guard let token = session.discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token,
                                                 requiringSecureCoding: true)
    }

    // MARK: Measuring

    /// Runs until the first usable distance reading or the timeout, whichever
    /// lands first. Returns nil if no reading arrived.
    func measure(against peerTokenData: Data, timeout: TimeInterval = 4) async -> Float? {
        guard let session,
              let token = Self.decodeToken(peerTokenData) else { return nil }

        session.run(NINearbyPeerConfiguration(peerToken: token))

        return await withCheckedContinuation { continuation in
            waiter = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.resolve(nil)
            }
        }
    }

    /// Convenience: measure and turn the reading into a verdict.
    func verdict(against peerTokenData: Data,
                 limit: Float = ProximityGate.sameRoomMetres) async -> Verdict {
        guard let distance = await measure(against: peerTokenData) else { return .unavailable }
        return distance <= limit ? .near(distance) : .tooFar(distance)
    }

    /// Ends the session and releases the radio for the next guest in the queue.
    func finish() {
        resolve(nil)
        session?.invalidate()
        session = nil
    }

    // MARK: Internals

    private func resolve(_ distance: Float?) {
        guard let waiter else { return }
        self.waiter = nil
        waiter.resume(returning: distance)
    }

    private static func decodeToken(_ data: Data) -> NIDiscoveryToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
    }
}

// MARK: - NISessionDelegate
//
// NISession delivers on the main queue unless told otherwise, so hopping
// synchronously is safe and keeps the first reading first.

extension ProximityGate: NISessionDelegate {

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        let reading = nearbyObjects.compactMap(\.distance).min()
        guard let reading else { return }
        hop { self.resolve(reading) }
    }

    nonisolated func session(_ session: NISession,
                             didRemove nearbyObjects: [NINearbyObject],
                             reason: NINearbyObject.RemovalReason) {
        hop { self.resolve(nil) }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        hop { self.resolve(nil) }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        hop { self.resolve(nil) }
    }

    private nonisolated func hop(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            Task { @MainActor in body() }
        }
    }
}
