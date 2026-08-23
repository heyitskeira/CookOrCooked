//
//  PausedOverlay.swift
//  Cooked
//
//  The screen that replaces "your game just ended for no reason".
//
//  It shows up over whatever the player was already looking at — the recipe
//  book or the kitchen itself — because that is the honest picture: the match
//  has not gone anywhere, it is simply not running. Three things are on it and
//  nothing else:
//
//    • what happened, in one line
//    • how long the wait has left, so nobody has to guess
//    • who we are still missing, so the wait has a face
//
//  The full-bleed scrim is load-bearing, not decoration: SpriteKit keeps
//  delivering touches to a paused scene, and the SwiftUI station popups
//  underneath are perfectly happy to be tapped. This is what stops both.
//

import SwiftUI

struct PausedOverlay: View {

    @ObservedObject var session: KitchenSession
    /// Give up on the wait. Owned by the presenting screen because leaving the
    /// kitchen also has to collapse the cover stack back to the start screen,
    /// which this overlay knows nothing about.
    let onLeave: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                // Swallows every tap that would otherwise reach the kitchen.
                .contentShape(Rectangle())
                .onTapGesture { }

            VStack(spacing: 18) {
                if let seconds = session.resumeSecondsLeft {
                    resuming(seconds)
                } else {
                    waiting
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
            .frame(maxWidth: 460)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.cream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.ink, lineWidth: 4)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
        }
        .transition(.opacity)
    }

    // MARK: The wait

    private var waiting: some View {
        VStack(spacing: 16) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(AppTheme.tomato)

            Text("Kitchen paused")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            // A guest cannot tell "the host went away" from "my own Wi-Fi
            // went away" — both look like one dead socket — so the copy says
            // the one thing that is true either way rather than guessing and
            // being wrong half the time.
            Text(session.isHost
                 ? "The other chefs dropped out. Nothing is ticking until they're back."
                 : "Lost the connection. Everything is held exactly where you left it.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !missing.isEmpty {
                Text("Waiting on \(missing.joined(separator: ", "))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AppTheme.creamDeep))
            }

            if let seconds = session.pauseSecondsLeft {
                countdownBar(seconds)
            }

            if session.isHost && session.connectedCount >= 2 {
                // The host is the only one who can decide the missing chef
                // isn't coming. Their slot stays held either way, so this is a
                // "carry on without them", not a kick.
                PillButton(title: "Carry on without them",
                           style: .outlined(background: AppTheme.cream,
                                            foreground: AppTheme.ink)) {
                    session.resumeMatch()
                }
            }

            // Ninety seconds is not long, but it is long enough that somebody
            // will want out before it's up — and until this button existed
            // there was no way to get out. The scrim eats every tap, the
            // kitchen has no back button of its own, and on the guest side
            // this card had no controls on it at all.
            PillButton(title: session.isHost ? "Close this kitchen" : "Leave kitchen",
                       style: .filled(background: AppTheme.tomato,
                                      foreground: AppTheme.cream),
                       action: onLeave)
        }
    }

    /// The ninety seconds, drawn as a bar as well as a number. A bare digit
    /// counting down is stressful; a bar that is still mostly full reads as
    /// "there's time" at a glance.
    private func countdownBar(_ seconds: Int) -> some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.ink.opacity(0.12))
                    Capsule()
                        .fill(seconds <= 15 ? AppTheme.tomato : AppTheme.ink.opacity(0.55))
                        .frame(width: geo.size.width *
                               (Double(seconds) / Double(PauseRules.graceSeconds)))
                }
            }
            .frame(height: 10)
            .animation(.linear(duration: 1), value: seconds)

            Text("Closing this kitchen in \(seconds)s")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.5))
        }
    }

    // MARK: The way back

    private func resuming(_ seconds: Int) -> some View {
        VStack(spacing: 12) {
            Text(session.isHost ? "Everyone's back" : "The host is back")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Text("\(seconds)")
                .font(.system(size: 76, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.tomato)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy(duration: 0.3), value: seconds)

            Text("Get back to your station")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.6))
        }
    }

    /// Names of the chefs whose slots are being held open.
    private var missing: [String] {
        session.players.filter { !$0.isConnected }.map(\.name)
    }
}

// MARK: - The kitchen closed for good

/// Shown when the wait ran out, or the host shut the kitchen deliberately.
/// Auto-returns to the start screen so nobody is left holding a dead room.
struct KitchenClosedOverlay: View {

    let reason: String
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }

            VStack(spacing: 18) {
                Image(systemName: "door.left.hand.closed")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(AppTheme.tomato)

                Text("Kitchen closed")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)

                Text(reason)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PillButton(title: "Back to the menu",
                           style: .filled(background: AppTheme.tomato,
                                          foreground: AppTheme.cream),
                           action: onDone)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
            .frame(maxWidth: 440)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.cream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.ink, lineWidth: 4)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
        }
        // The wait already had a countdown on it; making the player sit through
        // another one to acknowledge bad news would be unkind. Three seconds is
        // long enough to read, and the button is there for anyone faster.
        .task {
            try? await Task.sleep(for: .seconds(3))
            onDone()
        }
    }
}
