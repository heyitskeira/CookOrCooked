//
//  JoinKitchenView.swift
//  Cooked
//
//  Browse the local Wi-Fi for hosted kitchens and join one.
//

import SwiftUI
import Network

struct JoinKitchenView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var session = KitchenSession(role: .guest, playerName: "Chef")
    @State private var joined = false

    var body: some View {
        ZStack {
            AppTheme.background

            VStack(spacing: 24) {
                Text("Join a kitchen")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)

                if session.discovered.isEmpty {
                    searching
                } else {
                    roomList
                }
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
        .onAppear { session.startBrowsing() }
        .fullScreenCover(isPresented: $joined) {
            WaitingRoomView(session: session)
        }
    }

    private var searching: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.ink)
            Text("Looking for kitchens on your Wi-Fi…")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.6))
        }
        .frame(maxHeight: .infinity)
    }

    private var roomList: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(session.discovered, id: \.self) { result in
                    RoomRow(name: roomName(result)) {
                        session.join(result)
                        joined = true
                    }
                }
            }
            .padding(.vertical, 4)
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
        .accessibilityLabel("Back")
    }

    // Bonjour service name == the kitchen name the host advertised
    private func roomName(_ result: NWBrowser.Result) -> String {
        if case let .service(name, _, _, _) = result.endpoint {
            return name
        }
        return "Kitchen"
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
                    .font(.system(size: 22, weight: .bold, design: .rounded))
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
