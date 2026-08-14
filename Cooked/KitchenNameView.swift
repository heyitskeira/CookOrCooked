//
//  KithcenNameView.swift
//  Cooked
//
//  Created by Agung Ananda on 12/08/26.
//
//  "Setup your kitchen" — combined host setup: kitchen name + chef count.
//  (Absorbed what NumberOfPlayersView used to do; that view is now a dud.)
//

import SwiftUI

struct KitchenNameView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var kitchenName = ""
    @State private var chefCount: Int? = nil
    @State private var showWaitingRoom = false
    @FocusState private var nameFocused: Bool

    private let chefOptions = [2, 3, 4]

    private var trimmedName: String {
        kitchenName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty && chefCount != nil
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let panelW = w * 0.34

            ZStack {
                // Dotted blue backdrop
                Image("blue-bg-dotted")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                // Tagline + the two panels + create button
                VStack(spacing: h * 0.08) {
                    Image("setup-your-kitchen")
                        .resizable()
                        .scaledToFit()
                        .frame(height: h * 0.205)

                    HStack(spacing: w * 0.03) {
                        namePanel(width: panelW)
                        chefsPanel(width: panelW)
                    }

                    createButton(width: w * 0.17)
                        .offset(y: -h * 0.02)
                }
                .frame(width: w, height: h)

                // Corners
                VStack {
                    HStack {
                        cornerButton("back-button", label: "Back") { dismiss() }
                        Spacer()
                        cornerButton("settings-button", label: "Settings") {
                            // Dud for now — no settings screen yet
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, w * 0.03)
                .padding(.top, h * 0.04)
            }
            .frame(width: w, height: h)
            .fullScreenCover(isPresented: $showWaitingRoom) {
                WaitingRoomView(session: KitchenSession(
                    role: .host,
                    playerName: "Host Chef",
                    kitchenName: trimmedName,
                    maxPlayers: chefCount ?? 2
                ))
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Name panel (WHOSE KITCHEN?)

    private func namePanel(width: CGFloat) -> some View {
        Image("kitchen-name")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .overlay {
                GeometryReader { g in
                    TextField("", text: $kitchenName, prompt:
                        Text("Host's name")
                            .foregroundColor(.gray.opacity(0.5))
                    )
                    .font(.system(size: g.size.height * 0.19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.29, green: 0.35, blue: 0.62))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .frame(width: g.size.width * 0.78, height: g.size.height * 0.30)
                    // Sits inside the white box; tweak y to taste
                    .position(x: g.size.width * 0.5, y: g.size.height * 0.62)
                }
            }
    }

    // MARK: - Chefs panel (HOW MANY CHEFS?)

    private func chefsPanel(width: CGFloat) -> some View {
        Image("chefs-amount")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .overlay {
                GeometryReader { g in
                    let boxW = g.size.width * 0.24
                    let boxH = g.size.height * 0.32
                    HStack(spacing: g.size.width * 0.045) {
                        ForEach(chefOptions, id: \.self) { n in
                            Button {
                                chefCount = n
                            } label: {
                                ZStack {
                                    Color.clear
                                    RoundedRectangle(cornerRadius: boxW * 0.18)
                                        .fill(Color(red: 0.29, green: 0.35, blue: 0.62).opacity(0.22))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: boxW * 0.18)
                                                .stroke(Color(red: 0.29, green: 0.35, blue: 0.62), lineWidth: 4)
                                        )
                                        .opacity(chefCount == n ? 1 : 0)
                                }
                                .frame(width: boxW, height: boxH)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // Center over the three number boxes; tweak y to align
                    .frame(width: g.size.width, height: g.size.height)
                    .offset(y: g.size.height * 0.12)
                }
            }
    }

    // MARK: - Create button

    private func createButton(width: CGFloat) -> some View {
        Button {
            createKitchen()
        } label: {
            Image("create-button")
                .resizable()
                .scaledToFit()
                .frame(width: width)
        }
        .buttonStyle(.plain)
        .opacity(canCreate ? 1 : 0.5)
        .disabled(!canCreate)
        .accessibilityLabel("Create kitchen")
    }

    // MARK: - Corner button helper

    private func cornerButton(_ asset: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(height: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Action (moved here from NumberOfPlayersView)

    private func createKitchen() {
        guard canCreate else { return }
        // Name + chef count set — open the host lobby
        showWaitingRoom = true
    }
}

#Preview {
    KitchenNameView()
}
