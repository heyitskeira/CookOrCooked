//
//  StartScreenView.swift
//  Cooked
//
//  Created by Agung Ananda on 12/08/26.
//

import SwiftUI

struct StartScreenView: View {
    @State private var showKitchenName = false
    @State private var showJoinKitchen = false
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Forest clearing backdrop, full-bleed
                Image("woods-clearing-art")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                // Chef animals, bottom-left
                VStack {
                    Spacer()
                    HStack {
                        Image("start-animals")
                            .resizable()
                            .scaledToFit()
                            .frame(height: h * 0.82)
                        Spacer()
                    }
                    .offset(x: w * 0.29)
                }

                // Tree trunk with the two signs nailed on, right side
                HStack {
                    Spacer()
                    ZStack {
                        Image("trunk-planks")
                            .resizable()
                            .scaledToFit()
                            .frame(height: h)

                        VStack(spacing: h * 0.28) {
                            ImageButton(asset: "create-kitchen",
                                        width: w * 0.33,
                                        label: "Create Kitchen") {
                                createKitchen()
                            }
                            ImageButton(asset: "join-kitchen",
                                        width: w * 0.32,
                                        label: "Join Kitchen") {
                                joinKitchen()
                            }
                        }
                        // Nudge the signs left so they read as nailed to the trunk
                        .offset(x: -w * 0.002)
                    }
                }

                // Settings gear, top-left (clear of the trunk on the right)
                VStack {
                    HStack {
                        settingsButton
                        Spacer()
                    }
                    Spacer()
                }
                .padding(24)
            }
            .frame(width: w, height: h)
            .fullScreenCover(isPresented: $showKitchenName) {
                KitchenNameView()
            }
            .fullScreenCover(isPresented: $showJoinKitchen) {
                JoinKitchenView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .ignoresSafeArea()
        // Game over -> collapse the whole cover stack back to here.
        .onReceive(NotificationCenter.default.publisher(for: .returnToStart)) { _ in
            showKitchenName = false
            showJoinKitchen = false
        }
    }

    private var settingsButton: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(.black.opacity(0.35)))
                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
        }
        .accessibilityLabel("Settings")
    }

    // MARK: - Actions (unchanged)

    private func createKitchen() {
        // Host flow: name the kitchen first, then open the kitchen
        showKitchenName = true
    }

    private func joinKitchen() {
        showJoinKitchen = true
    }

    private func openSettings() {
        showSettings = true
    }
}

// MARK: - Image Button

/// A tappable image (wooden sign) with a subtle press-down animation.
private struct ImageButton: View {
    let asset: String
    let width: CGFloat
    let label: String
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: width)
                .scaleEffect(pressed ? 0.94 : 1)
                .shadow(color: .black.opacity(0.25), radius: pressed ? 2 : 6,
                        x: 0, y: pressed ? 1 : 4)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .accessibilityLabel(label)
    }
}

#Preview {
    StartScreenView()
}
