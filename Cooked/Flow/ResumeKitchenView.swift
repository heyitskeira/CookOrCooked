//
//  ResumeKitchenView.swift
//  Cooked
//
//  Reopening the app puts you back in the kitchen you were in.
//
//  This is the other half of the pause. Freezing the game buys the room ninety
//  seconds; this is what the host — or a guest whose own app died — does with
//  them. There is no room list and no code to re-type, because both of those
//  are things the player already did and being asked again is the bad
//  experience we're removing.
//
//  Two sides, one screen:
//
//    • The host rebuilds its kitchen from disk — same room id, same four
//      digits, same roster, same clock — and starts advertising again. The
//      chefs frozen in the old room are browsing for exactly that name, so
//      they find it within a couple of seconds.
//    • A guest browses for the kitchen it remembers and presents the resume
//      token the host issued it, which gets it back into its own slot with its
//      own colour and no code entry.
//
//  Either way the match comes back *paused*, and the 3-2-1 runs once everyone
//  is accounted for.
//

import SwiftUI

struct ResumeKitchenView: View {
    @Environment(\.dismiss) private var dismiss

    let saved: ResumableKitchen

    @StateObject private var session: KitchenSession
    @State private var showKitchen = false
    /// Guards the same dismiss-on-idle rule the waiting room uses: `.idle` is
    /// where a guest session starts, so it can't mean "we're finished" yet.
    @State private var didEnter = false

    init(saved: ResumableKitchen) {
        self.saved = saved
        switch saved {
        case .host(let room):
            _session = StateObject(wrappedValue: KitchenSession(role: .host, resuming: room))
        case .guest:
            _session = StateObject(wrappedValue: KitchenSession(role: .guest))
        }
    }

    var body: some View {
        ZStack {
            AppTheme.background

            VStack(spacing: 22) {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppTheme.ink)

                Text(headline)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)

                Text(detail)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = session.errorText {
                    Text(error)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.cream)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(AppTheme.tomato))
                }

                PillButton(title: "Not now",
                           style: .outlined(background: AppTheme.cream,
                                            foreground: AppTheme.ink)) {
                    abandon()
                }
                .frame(maxWidth: 280)
                .padding(.top, 8)
            }
            .frame(maxWidth: 480)
            .padding(40)
        }
        .onAppear(perform: reopen)
        .onChange(of: session.phase, initial: true) { _, phase in
            switch phase {
            case .lobby, .briefing, .playing:
                didEnter = true
                showKitchen = true
            case .rejected(_), .hostLeft:
                // The kitchen we remembered isn't there any more. Forget it
                // rather than offering it again on the next launch.
                forget()
                dismiss()
            case .idle where didEnter:
                dismiss()
            default:
                break
            }
        }
        .fullScreenCover(isPresented: $showKitchen) {
            WaitingRoomView(session: session)
        }
    }

    // MARK: Copy

    private var headline: String {
        switch saved {
        case .host:  return "Reopening \(saved.kitchenName)"
        case .guest: return "Getting you back into \(saved.kitchenName)"
        }
    }

    private var detail: String {
        switch saved {
        case .host:
            return "Same room code, same chefs, same clock. "
                 + "Everyone still waiting will find you in a moment."
        case .guest:
            return "Looking for the kitchen on your Wi-Fi. "
                 + "You'll go straight back to your station — no code needed."
        }
    }

    // MARK: Actions

    private func reopen() {
        switch saved {
        case .host:
            session.startHosting()
        case .guest(let room):
            session.resumeAsGuest(room)
        }
    }

    /// Declining is a decision, so the room is forgotten rather than offered
    /// again on every launch for the next quarter of an hour. `leave()` does
    /// the forgetting as part of shutting the session down cleanly — the
    /// important part here is that it also stops a half-open kitchen from being
    /// left advertising on the network.
    private func abandon() {
        session.leave()
        dismiss()
    }

    private func forget() {
        switch saved {
        case .host:  RoomResumeStore.clearHost()
        case .guest: RoomResumeStore.clearGuest()
        }
    }
}
