//
//  HeadChefScreens.swift
//  Cooked
//
//  The post-Start flow: randomly pick a head chef, reveal them, let the head
//  chef read the recipe while everyone else waits, then into the kitchen.
//
//  Presentation only. The pick, the 3-second reveal, and every step transition
//  are host-authoritative (see KitchenSession) so all devices move together and
//  agree on who the head chef is. These views just render `session.phase` +
//  `session.headChefID`.
//

import SwiftUI

/// Drives the whole post-Start sequence off the session phase.
struct HeadChefFlowView: View {
    @ObservedObject var session: KitchenSession

    var body: some View {
        switch session.phase {
        case .selectingHeadChef:
            SelectingHeadChefView()
        case .reading:
            HeadChefReadingView(session: session)
        default:
            KitchenGameView(session: session)
                .ignoresSafeArea()
        }
    }
}

// MARK: - "Selecting head chef" (host lingers here ~3s, then reveals)

struct SelectingHeadChefView: View {
    var body: some View {
        ZStack {
            AppTheme.background
            VStack(spacing: 24) {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppTheme.ink)
                Text("Selecting head chef…")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Reveal + recipe

struct HeadChefReadingView: View {
    @ObservedObject var session: KitchenSession

    var body: some View {
        ZStack {
            AppTheme.background

            VStack(spacing: 28) {
                Text(session.isHeadChef
                     ? "You're the head chef!"
                     : "\(session.headChefName) is the head chef!")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)

                if session.isHeadChef {
                    recipeBox
                    PillButton(
                        title: "Next",
                        style: .filled(background: AppTheme.tomato, foreground: AppTheme.cream)
                    ) {
                        session.finishReading()
                    }
                    .frame(maxWidth: 300)
                } else {
                    Text("Head chef is reading the recipe…")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink.opacity(0.6))
                }
            }
            .frame(maxWidth: 560)
            .padding(40)
        }
        .ignoresSafeArea()
    }

    // Placeholder recipe — a real recipe view drops in here later.
    private var recipeBox: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(AppTheme.cream)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppTheme.ink, lineWidth: 4)
            )
            .overlay(
                Text("Recipe")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.4))
            )
            .frame(height: 260)
    }
}
