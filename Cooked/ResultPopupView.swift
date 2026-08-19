//
//  ResultPopupView.swift
//  Cooked
//
//  Shown right after a producing action finishes: "Congratulations, you got a
//  Sifted Flour!" + a slot for its animation, and a choice of where the prep
//  goes — into the chef's hands, or left on the station for someone else.
//

import SwiftUI

struct PrepResult: Identifiable, Equatable {
    let station: StationID
    let foodID: String
    var id: String { "\(station.rawValue):\(foodID)" }
}

struct ResultPopupView: View {
    let result: PrepResult
    @ObservedObject var session: KitchenSession
    @ObservedObject var inventory: PlayerInventory
    var onDone: () -> Void

    private var name: String { GatingBridge.displayName(result.foodID) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Congratulations!")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.7))

                Text("You got a \(name)!")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)

                // Animation slot — a real prep animation drops in here later.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.creamDeep.opacity(0.5))
                    .overlay(
                        Text("🍽️").font(.system(size: 52))
                    )
                    .frame(width: 160, height: 140)

                VStack(spacing: 12) {
                    choice(title: "Put in my hands", tint: AppTheme.tomato) {
                        // It's on the station now — take it into hand and clear it.
                        session.pickUpOutput(at: result.station)
                        inventory.pickUp(HeldIngredient(id: result.foodID, name: name))
                        onDone()
                    }
                    choice(title: "Leave on the station", tint: AppTheme.ink) {
                        // Already sitting on the station — nothing more to do.
                        onDone()
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 440)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(AppTheme.cream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AppTheme.ink, lineWidth: 4)
            )
            .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
            .padding(40)
        }
    }

    private func choice(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.cream)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Capsule().fill(tint))
                .overlay(Capsule().stroke(AppTheme.ink, lineWidth: 3))
        }
        .buttonStyle(.plain)
    }
}
