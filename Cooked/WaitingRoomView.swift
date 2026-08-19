//
//  WaitingRoomView.swift
//  Cooked
//
//  Created by Agung Ananda on 12/08/26.
//
//  The host's screen shows the room code. That is not decoration — it is the
//  same-room check. To type those four digits a guest has to be able to see
//  this screen, which no radio can prove.
//

import SwiftUI

struct WaitingRoomView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var session: KitchenSession
    /// Covers the whole game: recipe book first, then the kitchen.
    @State private var showGame = false
    /// Guards the dismiss-on-idle rule below. Without it the view would tear
    /// itself down the instant it appears, because `.idle` is where every
    /// session starts.
    @State private var didLeaveLobby = false

    private var maxPlayers: Int { max(session.maxPlayers, session.players.count) }

    var body: some View {
        ZStack {
            AppTheme.background

            VStack(spacing: 24) {
                header
                if session.isHost { codeCard }
                panel
                startButton
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)

            VStack {
                HStack {
                    backButton
                    Spacer()
                }
                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            if session.isHost { session.startHosting() }
        }
        // `initial: true` matters: a guest admitted to a briefing or a game
        // already in progress is caught up during admission, so the phase has
        // already moved on before this view appears and a change-only handler
        // would strand them in the lobby forever.
        .onChange(of: session.phase, initial: true) { _, phase in
            switch phase {
            case .briefing, .playing:
                didLeaveLobby = true
                showGame = true
            case .idle where didLeaveLobby:
                // Backing out of the recipe book leaves the kitchen entirely,
                // so the lobby underneath must not linger.
                showGame = false
                dismiss()
            default:
                break
            }
        }
        .fullScreenCover(isPresented: $showGame) {
            GameFlowView(session: session)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(session.kitchenName)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)

            Text("\(session.connectedCount)/\(maxPlayers) chefs ready")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.6))
        }
    }

    // MARK: Room code

    private var codeCard: some View {
        VStack(spacing: 10) {
            Text("Room code")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(AppTheme.ink.opacity(0.5))

            HStack(spacing: 10) {
                ForEach(Array(session.roomCode.characters.enumerated()), id: \.offset) { _, digit in
                    Text(digit)
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 58, height: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.cream)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppTheme.ink, lineWidth: 3)
                        )
                }
            }

            Text("Read this out to the chefs in the room")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.45))
        }
    }

    // MARK: Roster

    private var panel: some View {
        VStack(spacing: 12) {
            ForEach(0..<maxPlayers, id: \.self) { index in
                if index < session.players.count {
                    PlayerRow(player: session.players[index])
                } else {
                    EmptySlotRow()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(AppTheme.cream)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(AppTheme.ink, lineWidth: 4)
        )
        .shadow(color: AppTheme.ink.opacity(0.2), radius: 12, x: 0, y: 8)
    }

    @ViewBuilder
    private var startButton: some View {
        if session.isHost {
            PillButton(
                title: "Start cooking",
                style: .filled(background: AppTheme.tomato, foreground: AppTheme.cream)
            ) {
                session.startCooking()
            }
            .opacity(session.canStart ? 1 : 0.5)
            .disabled(!session.canStart)
        } else {
            HStack(spacing: 12) {
                ProgressView().tint(AppTheme.ink)
                Text("Waiting for the host to start…")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.6))
            }
            .frame(height: 72)
        }
    }

    private var backButton: some View {
        Button {
            session.leave()
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 56, height: 56)
                .background(Circle().fill(AppTheme.cream))
                .overlay(Circle().stroke(AppTheme.ink, lineWidth: 3))
                .shadow(color: AppTheme.ink.opacity(0.25), radius: 4, x: 0, y: 3)
        }
        .accessibilityLabel("Leave kitchen")
    }
}

// MARK: - Rows

private struct PlayerRow: View {
    let player: Player

    private var colour: Color {
        let c = PlayerPalette.components(player.colorIndex)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.cream)
                .frame(width: 48, height: 48)
                .background(Circle().fill(player.isConnected ? colour : Color.gray))
                .overlay(Circle().stroke(AppTheme.ink, lineWidth: 3))

            Text(player.name)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(player.isConnected ? 1 : 0.4))

            Spacer()

            if !player.isConnected {
                Text("RECONNECTING")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.5))
            } else if player.isHost {
                Text("HOST")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.cream)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.ink))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.cream)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.ink.opacity(0.9), lineWidth: 2.5)
        )
    }
}

private struct EmptySlotRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hourglass")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.ink.opacity(0.4))
                .frame(width: 48, height: 48)
                .background(Circle().fill(AppTheme.creamDeep))
                .overlay(Circle().stroke(AppTheme.ink.opacity(0.3), lineWidth: 2.5))

            Text("Waiting for a chef…")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.4))

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.creamDeep.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 2.5, dash: [7, 6]))
                .foregroundStyle(AppTheme.ink.opacity(0.3))
        )
    }
}

#Preview {
    WaitingRoomView(session: {
        let s = KitchenSession(role: .host)
        s.configure(kitchenName: "Gordon's Kitchen", maxPlayers: 4)
        return s
    }())
}
