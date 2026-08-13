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

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > geo.size.height

            ZStack {
                AppTheme.background

                content(isWide: isWide)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 32)

                // Settings gear, top-right
                VStack {
                    HStack {
                        Spacer()
                        settingsButton
                    }
                    Spacer()
                }
                .padding(24)
            }
            .fullScreenCover(isPresented: $showKitchenName) {
                KitchenNameView()
            }
            .fullScreenCover(isPresented: $showJoinKitchen) {
                JoinKitchenView()
            }
        }
    }

    // Adaptive: side-by-side in landscape, stacked in portrait
    @ViewBuilder
    private func content(isWide: Bool) -> some View {
        if isWide {
            HStack(spacing: 48) {
                logo
                    .frame(maxWidth: .infinity)
                buttons
                    .frame(maxWidth: 420)
            }
        } else {
            VStack(spacing: 56) {
                logo
                buttons
                    .frame(maxWidth: 480)
            }
        }
    }

    private var logo: some View {
        Image("StartLogo")
            .resizable()
            .scaledToFit()
            .shadow(color: AppTheme.ink.opacity(0.18), radius: 12, x: 0, y: 8)
            .accessibilityLabel("Cook or Cooked")
    }

    private var buttons: some View {
        VStack(spacing: 24) {
            PillButton(
                title: "Create Kitchen",
                style: .filled(background: AppTheme.tomato, foreground: AppTheme.cream)
            ) {
                createKitchen()
            }

            PillButton(
                title: "Join Kitchen",
                style: .outlined(background: AppTheme.cream, foreground: AppTheme.ink)
            ) {
                joinKitchen()
            }
        }
    }

    private var settingsButton: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 56, height: 56)
                .background(Circle().fill(AppTheme.cream))
                .overlay(Circle().stroke(AppTheme.ink, lineWidth: 3))
                .shadow(color: AppTheme.ink.opacity(0.25), radius: 4, x: 0, y: 3)
        }
        .accessibilityLabel("Settings")
    }

    // MARK: - Actions (wired to real flows later)

    private func createKitchen() {
        // Host flow: name the kitchen first, then open the kitchen
        showKitchenName = true
    }

    private func joinKitchen() {
        showJoinKitchen = true
    }

    private func openSettings() {
        // TODO: present settings
    }
}

#Preview {
    StartScreenView()
}
