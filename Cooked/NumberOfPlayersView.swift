//
//  NumberOfPlayersView.swift
//  Cooked
//
//  Created by Agung Ananda on 12/08/26.
//

import SwiftUI

struct NumberOfPlayersView: View {
    @Environment(\.dismiss) private var dismiss

    let kitchenName: String

    // Owned here so it survives the transition into the waiting room. The
    // session is inert until `startHosting()` — creating it advertises nothing.
    @StateObject private var session = KitchenSession(role: .host)

    @State private var selected: Int? = nil
    @State private var showWaitingRoom = false

    private let options = [2, 3, 4]

    var body: some View {
        ZStack {
            AppTheme.background

            VStack(spacing: 40) {
                panel

                PillButton(
                    title: "Start",
                    style: .filled(background: AppTheme.tomato, foreground: AppTheme.cream)
                ) {
                    start()
                }
                .frame(maxWidth: 480)
                .opacity(selected == nil ? 0.5 : 1)
                .disabled(selected == nil)
            }
            .padding(.horizontal, 40)

            // Back button, top-left
            VStack {
                HStack {
                    backButton
                    Spacer()
                    settingsButton
                }
                Spacer()
            }
            .padding(24)
        }
        .fullScreenCover(isPresented: $showWaitingRoom) {
            WaitingRoomView(session: session)
        }
    }

    private var panel: some View {
        VStack(spacing: 32) {
            Text("Number of players")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                ForEach(options, id: \.self) { count in
                    PlayerCountBox(
                        count: count,
                        isSelected: selected == count
                    ) {
                        selected = count
                    }
                }
            }
        }
        .padding(40)
        .frame(maxWidth: 560)
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

    private var backButton: some View {
        circleButton(system: "chevron.left", label: "Back") { dismiss() }
    }

    private var settingsButton: some View {
        circleButton(system: "gearshape.fill", label: "Settings") {
            // TODO: present settings
        }
    }

    private func circleButton(system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 56, height: 56)
                .background(Circle().fill(AppTheme.cream))
                .overlay(Circle().stroke(AppTheme.ink, lineWidth: 3))
                .shadow(color: AppTheme.ink.opacity(0.25), radius: 4, x: 0, y: 3)
        }
        .accessibilityLabel(label)
    }

    private func start() {
        guard let selected else { return }
        session.configure(kitchenName: kitchenName, maxPlayers: selected)
        showWaitingRoom = true
    }
}

// MARK: - Player Count Box

private struct PlayerCountBox: View {
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(count)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(isSelected ? AppTheme.cream : AppTheme.ink)
                .frame(width: 96, height: 96)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isSelected ? AppTheme.tomato : AppTheme.cream)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.ink, lineWidth: 3)
                )
                .shadow(color: AppTheme.ink.opacity(0.2),
                        radius: isSelected ? 2 : 5,
                        x: 0, y: isSelected ? 2 : 4)
                .scaleEffect(isSelected ? 1.06 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) players")
    }
}

#Preview {
    NumberOfPlayersView(kitchenName: "Test Kitchen")
}
