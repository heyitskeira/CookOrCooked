//
//  StorageView.swift
//  Cooked
//
//  The storage overlay: choose to search ingredients or utensils, pick one,
//  and (for ingredients) see whether it came out fresh or rotten.
//

import SwiftUI

struct StorageView: View {
    /// Called when the chef leaves storage (closes the overlay).
    var onClose: () -> Void

    private enum Screen {
        case menu
        case ingredients
        case utensils
    }

    @State private var screen: Screen = .menu
    @State private var ingredientDraw: IngredientDraw? = nil   // result popup
    @State private var takenUtensil: Utensil? = nil            // result popup

    var body: some View {
        ZStack {
            AppTheme.background

            VStack(spacing: 24) {
                header
                content
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
        }
        .ignoresSafeArea()
        .overlay { resultPopup }
    }

    // MARK: Header (title + back/close)

    private var header: some View {
        ZStack {
            Text(title)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            HStack {
                Button {
                    if screen == .menu { onClose() } else { screen = .menu }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(AppTheme.cream))
                        .overlay(Circle().stroke(AppTheme.ink, lineWidth: 3))
                }
                .accessibilityLabel(screen == .menu ? "Leave storage" : "Back")

                Spacer()
            }
        }
    }

    private var title: String {
        switch screen {
        case .menu:        return "Storage"
        case .ingredients: return "Ingredients"
        case .utensils:    return "Utensils"
        }
    }

    // MARK: Content per screen

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .menu:
            menu
        case .ingredients:
            itemList(Storage.ingredients.map { ($0.id, $0.name) }) { id in
                guard let ing = Storage.ingredients.first(where: { $0.id == id }) else { return }
                ingredientDraw = Storage.draw(ing)
            }
        case .utensils:
            itemList(Storage.utensils.map { ($0.id, $0.name) }) { id in
                takenUtensil = Storage.utensils.first(where: { $0.id == id })
            }
        }
    }

    private var menu: some View {
        VStack(spacing: 20) {
            bigChoice(title: "Search Ingredients", icon: "leaf.fill") {
                screen = .ingredients
            }
            bigChoice(title: "Search Utensils", icon: "fork.knife") {
                screen = .utensils
            }
        }
    }

    private func bigChoice(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .bold))
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .bold))
                    .opacity(0.5)
            }
            .foregroundStyle(AppTheme.cream)
            .padding(.horizontal, 24)
            .frame(height: 84)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(AppTheme.tomato))
            .overlay(Capsule().stroke(AppTheme.ink, lineWidth: 3))
            .shadow(color: AppTheme.ink.opacity(0.2), radius: 5, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // Generic tappable list used by both ingredients and utensils.
    private func itemList(_ items: [(String, String)], onPick: @escaping (String) -> Void) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(items, id: \.0) { id, name in
                    Button {
                        onPick(id)
                    } label: {
                        HStack {
                            Text(name)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppTheme.ink.opacity(0.4))
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 62)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.cream)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppTheme.ink, lineWidth: 2.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 360)
    }

    // MARK: Result popup (fresh / rotten / utensil taken)

    @ViewBuilder
    private var resultPopup: some View {
        if let draw = ingredientDraw {
            popupCard(
                emoji: draw.isRotten ? "🤢" : "✨",
                headline: draw.isRotten ? "Rotten \(draw.ingredient.name)!" : "Fresh \(draw.ingredient.name)!",
                tint: draw.isRotten ? Color(red: 0.5, green: 0.35, blue: 0.15) : AppTheme.tomato,
                subtitle: draw.isRotten ? "Yuck — better toss this one." : "Nice and fresh."
            ) {
                ingredientDraw = nil
            }
        } else if let utensil = takenUtensil {
            popupCard(
                emoji: "🍴",
                headline: "Got the \(utensil.name)",
                tint: AppTheme.tomato,
                subtitle: "Ready to cook."
            ) {
                takenUtensil = nil
            }
        }
    }

    private func popupCard(emoji: String, headline: String, tint: Color, subtitle: String,
                           dismiss: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 14) {
                Text(emoji).font(.system(size: 56))
                Text(headline)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.6))

                Button(action: dismiss) {
                    Text("OK")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.cream)
                        .frame(width: 160, height: 56)
                        .background(Capsule().fill(tint))
                        .overlay(Capsule().stroke(AppTheme.ink, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.cream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.ink, lineWidth: 4)
            )
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
        }
    }
}

#Preview {
    StorageView(onClose: {})
}
