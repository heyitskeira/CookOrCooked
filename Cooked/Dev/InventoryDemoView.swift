//
//  InventoryDemoView.swift
//  Cooked
//
//  A throwaway test harness for PlayerInventory. NOT part of the game flow —
//  it just lets you see the two slots fill, replace, and clear on device or in
//  the Xcode preview canvas. Delete (or ignore) once inventory is wired into
//  the real kitchen.
//

import SwiftUI

struct InventoryDemoView: View {
    @StateObject private var inv = PlayerInventory()

    // A few sample items to poke at (the real ones come from Storage later).
    private let sampleIngredients: [HeldIngredient] = [
        HeldIngredient(id: "strawberries", name: "Strawberries"),
        HeldIngredient(id: "cream", name: "Cream"),
        HeldIngredient(id: "egg", name: "Egg", isRotten: true),
    ]
    private let sampleUtensils: [HeldUtensil] = [
        HeldUtensil(id: "whisk", name: "Whisk"),
        HeldUtensil(id: "knife", name: "Knife"),
    ]

    var body: some View {
        ZStack {
            Color(white: 0.96).ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Inventory test")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))

                hands

                pickers

                Button("Empty both hands") { inv.clear() }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .disabled(inv.isEmpty)
            }
            .padding(32)

            // The real indicator bar, pinned bottom-centre like it will be in-game.
            VStack {
                Spacer()
                InventoryBar(inventory: inv)
                    .padding(.bottom, 20)
            }
        }
    }

    // Shows what's currently in each slot.
    private var hands: some View {
        HStack(spacing: 16) {
            slot(title: "Ingredient",
                 label: inv.ingredient.map { $0.isRotten ? "🤢 \($0.name)" : $0.name } ?? "— empty —",
                 filled: inv.hasIngredient) {
                inv.dropIngredient()
            }
            slot(title: "Utensil",
                 label: inv.utensil?.name ?? "— empty —",
                 filled: inv.hasUtensil) {
                inv.dropUtensil()
            }
        }
    }

    private func slot(title: String, label: String, filled: Bool, onDrop: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(RoundedRectangle(cornerRadius: 14).fill(filled ? Color.orange.opacity(0.25) : Color.gray.opacity(0.15)))
            if filled {
                Button("Drop", action: onDrop).font(.caption.weight(.bold))
            }
        }
    }

    // Buttons that pick up a sample item (replacing whatever's held).
    private var pickers: some View {
        VStack(spacing: 12) {
            Text("Pick up (replaces the slot — only one each)")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                ForEach(sampleIngredients) { item in
                    Button(item.isRotten ? "🤢 \(item.name)" : item.name) { inv.pickUp(item) }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
            }
            HStack {
                ForEach(sampleUtensils) { item in
                    Button(item.name) { inv.pickUp(item) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

#Preview {
    InventoryDemoView()
}
