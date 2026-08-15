//
//  InventoryBar.swift
//  Cooked
//
//  The always-visible "what am I holding" indicator: two boxes at the
//  bottom-centre of the screen. Left = ingredient slot, right = utensil slot.
//  Blank when empty, filled with the item once picked up.
//
//  Pure read-side of PlayerInventory — it only displays, never mutates. Drop it
//  over the kitchen map as an overlay once inventory is wired into gameplay.
//

import SwiftUI

struct InventoryBar: View {
    @ObservedObject var inventory: PlayerInventory

    var body: some View {
        HStack(spacing: 16) {
            InventorySlot(
                caption: "Ingredient",
                content: inventory.ingredient.map {
                    SlotContent(text: $0.name, isRotten: $0.isRotten)
                }
            )
            InventorySlot(
                caption: "Utensil",
                content: inventory.utensil.map {
                    SlotContent(text: $0.name, isRotten: false)
                }
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.28))
        )
    }
}

// What a filled slot shows.
private struct SlotContent {
    let text: String
    let isRotten: Bool
}

private struct InventorySlot: View {
    let caption: String
    let content: SlotContent?

    private var filled: Bool { content != nil }

    var body: some View {
        VStack(spacing: 6) {
            Text(caption.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(filled ? Color.white : Color.white.opacity(0.12))

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2.5, dash: filled ? [] : [6, 5])
                    )
                    .foregroundStyle(.white.opacity(filled ? 0 : 0.5))

                if let content {
                    VStack(spacing: 2) {
                        Text(content.isRotten ? "🤢" : "🥄")
                            .font(.system(size: 24))
                        Text(content.text)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(content.isRotten
                                             ? Color(red: 0.45, green: 0.30, blue: 0.10)
                                             : .black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 6)
                } else {
                    Text("empty")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 108, height: 78)
        }
    }
}

#Preview {
    // Show empty, filled-fresh, and filled-rotten side by side.
    ZStack {
        Color(red: 0.11, green: 0.11, blue: 0.13).ignoresSafeArea()
        VStack(spacing: 30) {
            InventoryBar(inventory: PlayerInventory())
            InventoryBar(inventory: PlayerInventory(
                ingredient: HeldIngredient(id: "egg", name: "Egg"),
                utensil: HeldUtensil(id: "whisk", name: "Whisk")
            ))
            InventoryBar(inventory: PlayerInventory(
                ingredient: HeldIngredient(id: "cream", name: "Cream", isRotten: true),
                utensil: nil
            ))
        }
    }
}
