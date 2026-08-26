//
//  StorageView.swift
//  Cooked
//
//  The storage room: one cupboard with three tabs — the utensils on their
//  hooks, the ingredients on their shelf, and the storage rack where a chef
//  parks a half-finished prep.
//
//  The rack used to be its own station out on the map (the "drawer"). It is a
//  tab here now because all three are the same errand — you go to the pantry to
//  fetch or stash something — and one pin on the map is easier to read than two
//  that look alike. `StationID.drawer` still exists behind this, unchanged, so
//  nothing about how shelves sync had to move.
//

import SwiftUI

struct StorageView: View {
    /// The chef's hands — picking here fills these slots.
    @ObservedObject var inventory: PlayerInventory
    /// Local utensil stock, used only when there's no networked game (test menu).
    @ObservedObject var pantry: StoragePantry
    /// The shelves behind the Storage Rack tab. Local fallback only; the host
    /// owns them once a game is running.
    @ObservedObject var drawerBox: DrawerBox
    /// The live game. When present, utensil stock is host-authoritative and
    /// draws go through it; nil means offline/test-menu (use `pantry`).
    var session: KitchenSession? = nil
    /// Called when the chef leaves storage (closes the overlay).
    var onClose: () -> Void

    /// The three shelves of the cupboard, in the order the design shows them.
    private enum Tab: String, CaseIterable, Identifiable {
        case utensils, ingredients, rack
        var id: String { rawValue }
        var title: String {
            switch self {
            case .utensils:    return "Utensils"
            case .ingredients: return "Ingredients"
            case .rack:        return "Storage Rack"
            }
        }
    }

    @State private var tab: Tab = .utensils
    /// One cursor per carousel, so switching tabs within a visit keeps your
    /// place. Leaving the pantry tears the view down and resets all three —
    /// walk back in and you are on Utensils at the first item again. Hoist
    /// these to `KitchenGameView` if that ever needs to persist.
    @State private var utensilIndex = 0
    @State private var ingredientIndex = 0
    @State private var ingredientDraw: IngredientDraw? = nil   // result popup
    @State private var takenUtensil: Utensil? = nil            // result popup
    @State private var outOfStock: String? = nil               // result popup
    @State private var pendingUtensil: Utensil? = nil          // awaiting host reply
    @State private var prepAlert: String? = nil                // "already holding a prep"

    // Stock shown per utensil — from the host if networked, else local.
    private func utensilsLeft(_ id: String) -> Int {
        session?.utensilsLeft(id) ?? pantry.remaining(id)
    }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 12) {
                header
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .ignoresSafeArea()
        .overlay { resultPopup }
        .overlay {
            if let prepAlert {
                PrepHeldAlert(message: prepAlert) { self.prepAlert = nil }
            }
        }
        // Host replies synchronously; a guest's reply lands here a moment later.
        .onChange(of: session?.utensilReply) { _, _ in applyUtensilReply() }
    }

    private func takeUtensil(_ ut: Utensil) {
        if let session {
            // Networked: ask the host, hand back whatever we were holding.
            pendingUtensil = ut
            session.requestUtensil(ut.id, returning: inventory.utensil?.id)
            applyUtensilReply()   // host answers immediately; guest via onChange
        } else {
            // Offline (test menu): local stock.
            guard pantry.take(ut.id) else { outOfStock = ut.name; return }
            if let displaced = inventory.pickUp(HeldUtensil(id: ut.id, name: ut.name)) {
                pantry.giveBack(displaced.id)
            }
            takenUtensil = ut
        }
    }

    private func applyUtensilReply() {
        guard let session,
              let reply = session.utensilReply,
              let ut = pendingUtensil,
              reply.id == ut.id else { return }
        if reply.granted {
            inventory.pickUp(HeldUtensil(id: ut.id, name: ut.name))
            takenUtensil = ut
        } else {
            outOfStock = ut.name
        }
        pendingUtensil = nil
        session.clearUtensilReply()
    }

    // MARK: Backdrop

    /// The cupboard interior behind the utensils and ingredients; the rack tab
    /// brings its own woodland backing, so it gets a plain wash instead.
    @ViewBuilder
    private var backdrop: some View {
        if tab != .rack, let art = UIImage(named: "bg-storage-cupboard") {
            Image(uiImage: art)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            AppTheme.background
        }
    }

    // MARK: Header (back + tabs + clock)

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "arrowshape.turn.up.backward.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(AppTheme.cream))
                    .overlay(Circle().stroke(AppTheme.ink, lineWidth: 3))
            }
            .accessibilityLabel("Leave storage")

            Spacer(minLength: 0)
            tabBar
            Spacer(minLength: 0)

            // Balances the back button so the tab row sits centred. The clock
            // itself is drawn by the scene underneath, not here.
            Color.clear.frame(width: 46, height: 46)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { entry in
                let selected = entry == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = entry }
                } label: {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? AppTheme.ink : AppTheme.cream)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(
                            Capsule().fill(selected ? AppTheme.cream : Color.black.opacity(0.35))
                        )
                        .overlay(
                            Capsule().stroke(AppTheme.ink.opacity(selected ? 1 : 0.35),
                                             lineWidth: selected ? 2.5 : 1.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.18)))
    }

    // MARK: Content per tab

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .utensils:
            VStack(spacing: 6) {
                StorageCarousel(items: utensilItems, index: $utensilIndex) { item in
                    guard let ut = Storage.utensils.first(where: { $0.id == item.id }) else { return }
                    takeUtensil(ut)
                }
                caption("Select your Utensils")
            }

        case .ingredients:
            VStack(spacing: 6) {
                StorageCarousel(items: ingredientItems, index: $ingredientIndex) { item in
                    pickIngredient(item.id)
                }
                caption("Select your Ingredients")
            }

        case .rack:
            // The old drawer screen, unchanged in behaviour — same shelves,
            // same host round-trip, same refusal messages. Only the way in
            // changed.
            DrawerView(inventory: inventory,
                       box: drawerBox,
                       session: session,
                       showsCloseButton: false,
                       onClose: onClose)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.cream)
            .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
    }

    // MARK: Rows

    private var utensilItems: [StorageCarouselItem] {
        Storage.utensils.map { ut in
            let left = utensilsLeft(ut.id)
            return StorageCarouselItem(
                id: ut.id,
                name: ut.name,
                detail: left > 0 ? "\(left) left" : "In use",
                // Someone else is holding the last one — show the dark
                // silhouette rather than letting the chef tap a dead item.
                isInUse: left <= 0
            )
        }
    }

    private var ingredientItems: [StorageCarouselItem] {
        Storage.ingredients.map { StorageCarouselItem(id: $0.id, name: $0.name) }
    }

    private func pickIngredient(_ id: String) {
        guard let ing = Storage.ingredients.first(where: { $0.id == id }) else { return }
        if inventory.isHoldingRotten {
            prepAlert = Rotten.blockedMessage
            return
        }
        if inventory.isHoldingPrep {
            prepAlert = "You already held on to a prep!"
            return
        }
        let draw = Storage.draw(ing)
        ingredientDraw = draw
        // Put it in hand (replaces whatever raw ingredient was held).
        inventory.pickUp(HeldIngredient(id: draw.ingredient.id,
                                        name: draw.ingredient.name,
                                        isRotten: draw.isRotten))
    }

    // MARK: Result popup (fresh / rotten / utensil taken)

    @ViewBuilder
    private var resultPopup: some View {
        if let draw = ingredientDraw {
            popupCard(
                emoji: draw.isRotten ? "🤢" : "✨",
                headline: draw.isRotten ? "Rotten \(draw.ingredient.name)!" : "Fresh \(draw.ingredient.name)!",
                tint: draw.isRotten ? Color(red: 0.5, green: 0.35, blue: 0.15) : AppTheme.tomato,
                subtitle: draw.isRotten ? "Throw it to the garbage bin!" : "Nice and fresh."
            ) {
                let wasRotten = draw.isRotten
                ingredientDraw = nil
                // Rot sticks to the hand until the bin takes it, so there is
                // nothing left to do in here — leave the shelves rather than
                // stand in front of them unable to pick anything up.
                if wasRotten { onClose() }
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
        } else if let name = outOfStock {
            popupCard(
                emoji: "🚫",
                headline: "No \(name) left",
                tint: Color(red: 0.5, green: 0.35, blue: 0.15),
                subtitle: "Someone else has it — wait for it to come back."
            ) {
                outOfStock = nil
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
    StorageView(inventory: PlayerInventory(),
                pantry: StoragePantry(),
                drawerBox: DrawerBox(),
                onClose: {})
}
