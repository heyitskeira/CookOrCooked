//
//  KithcenNameView.swift
//  Cooked
//
//  Created by Agung Ananda on 12/08/26.
//

import SwiftUI

struct KitchenNameView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var kitchenName = ""
    @State private var showPlayerCount = false
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        kitchenName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            AppTheme.background

            VStack(spacing: 40) {
                Text("Enter kitchen's name")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)

                nameField

                PillButton(
                    title: "Create",
                    style: .filled(background: AppTheme.tomato, foreground: AppTheme.cream)
                ) {
                    createKitchen()
                }
                .opacity(trimmedName.isEmpty ? 0.5 : 1)
                .disabled(trimmedName.isEmpty)
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 40)

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
        .onAppear { nameFocused = true }
        .fullScreenCover(isPresented: $showPlayerCount) {
            NumberOfPlayersView(kitchenName: trimmedName)
        }
    }

    private var nameField: some View {
        TextField("", text: $kitchenName, prompt:
            Text("Kitchen name")
                .foregroundColor(AppTheme.ink.opacity(0.35))
        )
        .font(.system(size: 24, weight: .semibold, design: .rounded))
        .foregroundStyle(AppTheme.ink)
        .multilineTextAlignment(.center)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .focused($nameFocused)
        .onSubmit { createKitchen() }
        .padding(.horizontal, 24)
        .frame(height: 72)
        .background(Capsule().fill(AppTheme.cream))
        .overlay(Capsule().stroke(AppTheme.ink, lineWidth: 3))
        .shadow(color: AppTheme.ink.opacity(0.15), radius: 5, x: 0, y: 4)
    }

    private var backButton: some View {
        Button {
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

    private func createKitchen() {
        guard !trimmedName.isEmpty else { return }
        // Name set — next, pick how many players will join
        showPlayerCount = true
    }
}

#Preview {
    KitchenNameView()
}
