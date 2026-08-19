//
//  JoinKitchenView.swift
//  Cooked
//
//  Browse the local Wi-Fi for hosted kitchens, then prove you're in the room
//  by typing the code off the host's screen.
//
//  The list shows every kitchen the radio can find. It deliberately does NOT
//  filter by distance: ranging each advertiser before drawing its row would
//  need one UWB session per kitchen, and only one can run at a time. The
//  distance check happens after you tap.
//

import SwiftUI

struct JoinKitchenView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var session = KitchenSession(role: .guest)
    @State private var pendingKitchen: DiscoveredKitchen?
    @State private var typedCode = ""
    @State private var showLobby = false

    var body: some View {
        ZStack {
            AppTheme.background

            VStack(spacing: 24) {
                Text("Join a kitchen")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)

                if let errorText = session.errorText {
                    Text(errorText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.cream)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(AppTheme.tomato))
                }

                content
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
        .onAppear { session.startBrowsing() }
        .sheet(item: $pendingKitchen) { kitchen in
            codeEntry(for: kitchen)
        }
        .onChange(of: session.phase) { _, phase in
            // Only ever raise the cover from here. A constant binding would
            // present fine but leave the lobby's back button unable to close.
            // .briefing and .playing both mean "admitted to a kitchen that has
            // already left the lobby" — the waiting room passes them straight
            // through to the recipe book or the game.
            if phase == .lobby || phase == .briefing || phase == .playing { showLobby = true }
        }
        .fullScreenCover(isPresented: $showLobby) {
            WaitingRoomView(session: session)
        }
    }

    // MARK: Body states

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .verifying(let status):
            waiting(status)
        case .rejected(let reason):
            rejected(reason)
        case .hostLeft:
            rejected(nil, text: "The host closed this kitchen")
        default:
            if session.discovered.isEmpty { searching } else { roomList }
        }
    }

    private var searching: some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large).tint(AppTheme.ink)
            Text("Looking for kitchens on your Wi-Fi…")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.6))
            Text("You and the host must be on the same network")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.4))
        }
        .frame(maxHeight: .infinity)
    }

    private func waiting(_ status: String) -> some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large).tint(AppTheme.ink)
            Text(status)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
        }
        .frame(maxHeight: .infinity)
    }

    private func rejected(_ reason: JoinRejection?, text: String? = nil) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(AppTheme.tomato)

            Text(text ?? reason?.message ?? "Couldn't join")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)

            PillButton(title: "Try again",
                       style: .outlined(background: AppTheme.cream, foreground: AppTheme.ink)) {
                session.startBrowsing()
            }
            .frame(maxWidth: 300)
        }
        .frame(maxHeight: .infinity)
    }

    private var roomList: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(session.discovered) { kitchen in
                    RoomRow(name: kitchen.name) {
                        typedCode = ""
                        pendingKitchen = kitchen
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Code entry

    private func codeEntry(for kitchen: DiscoveredKitchen) -> some View {
        VStack(spacing: 26) {
            Text(kitchen.name)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Text("Type the four digits shown on the host's screen")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.55))
                .multilineTextAlignment(.center)

            TextField("0000", text: $typedCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .frame(maxWidth: 260)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.cream)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.ink, lineWidth: 3)
                )
                .onChange(of: typedCode) { _, new in
                    typedCode = String(new.filter(\.isNumber).prefix(4))
                }

            PillButton(title: "Join",
                       style: .filled(background: AppTheme.tomato, foreground: AppTheme.cream)) {
                guard let code = RoomCode(typedCode) else { return }
                pendingKitchen = nil
                session.join(kitchen: kitchen.id, code: code)
            }
            .frame(maxWidth: 300)
            .opacity(RoomCode(typedCode) == nil ? 0.5 : 1)
            .disabled(RoomCode(typedCode) == nil)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
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
        .accessibilityLabel("Back")
    }
}

// MARK: - Room Row

private struct RoomRow: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "frying.pan.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.cream)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(AppTheme.tomato))
                    .overlay(Circle().stroke(AppTheme.ink, lineWidth: 3))

                Text(name)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.ink.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .frame(height: 68)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.cream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.ink, lineWidth: 3)
            )
            .shadow(color: AppTheme.ink.opacity(0.15), radius: 4, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    JoinKitchenView()
}
