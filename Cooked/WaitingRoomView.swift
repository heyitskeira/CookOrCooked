//
//  WaitingRoomView.swift
//  Cooked
//
//  Created by Agung Ananda on 12/08/26.
//

import SwiftUI

struct WaitingRoomView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var session: KitchenSession
    @State private var showKitchen = false

    init(session: KitchenSession) {
        _session = StateObject(wrappedValue: session)
    }

    private var kitchenName: String { session.kitchenName }
    private var maxPlayers: Int { max(session.maxPlayers, session.players.count) }

    var body: some View {
        ZStack {
            AppTheme.background

            VStack(spacing: 28) {
                header
                panel
                startButton
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)

            // Back button, top-left
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
            if session.role == .host { session.startHosting() }
        }
        .onChange(of: session.started) { started in
            if started { showKitchen = true }
        }
        .fullScreenCover(isPresented: $showKitchen) {
            ContentView()
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(kitchenName)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)

            Text("\(session.players.count)/\(maxPlayers) chefs ready")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.6))
        }
    }

    private var panel: some View {
        VStack(spacing: 14) {
            ForEach(0..<maxPlayers, id: \.self) { index in
                if index < session.players.count {
                    PlayerRow(player: session.players[index])
                } else {
                    EmptySlotRow()
                }
            }
        }
        .padding(24)
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
        if session.role == .host {
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
                ProgressView()
                    .tint(AppTheme.ink)
                Text("Waiting for the host to start…")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
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

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.cream)
                .frame(width: 48, height: 48)
                .background(Circle().fill(AppTheme.tomato))
                .overlay(Circle().stroke(AppTheme.ink, lineWidth: 3))

            Text(player.name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Spacer()

            if player.isHost {
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
                .font(.system(size: 20, weight: .semibold, design: .rounded))
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
    WaitingRoomView(session: KitchenSession(
        role: .host,
        playerName: "Host Chef",
        kitchenName: "Gordon's Kitchen",
        maxPlayers: 4
    ))
}
