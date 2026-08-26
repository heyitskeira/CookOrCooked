//
//  StorageView.swift
//  Cooked
//
//  The storage room: one cupboard with three tabs — the utensils on their
//  hooks, the ingredients on their shelf, and the storage rack out back where
//  a chef parks a half-finished prep.
//
//  The rack used to be its own station out on the map (the "drawer"). It is a
//  tab here now because all three are the same errand — you go to the pantry to
//  fetch or stash something — and one pin on the map is easier to read than two
//  that look alike. `StationID.drawer` still exists behind this, unchanged, so
//  nothing about how shelves sync had to move.
//
//  Laid out against the storage artboard (see `StorageCanvas`), which is the
//  plain 874x402 screen — not the stretched one the illustrated station pages
//  use.
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

    @State private var tab: StorageTab = .utensils
    /// One cursor per carousel, so switching tabs within a visit keeps your
    /// place. Leaving the pantry tears the view down and resets both — walk
    /// back in and you are on Utensils at the first item again. Hoist these to
    /// `KitchenGameView` if that ever needs to persist.
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

    /// The countdown on the cupboard clock. A solo/test-menu session never
    /// starts the 10Hz snapshot tick, so it reads the full round there — a
    /// still dial rather than a wrong one.
    private var timeRemaining: TimeInterval {
        session?.snapshot.timeRemaining ?? Recipe.timeLimit
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backdrop(geo)
                content(geo)

                // Above the shelves so a tap near the top edge reaches the tab
                // pill rather than the carousel behind it.
                StorageHands(inventory: inventory, geo: geo)
                StorageBackButton(geo: geo, action: onClose)
                StorageTabBar(tab: $tab, geo: geo)
                StorageClock(timeRemaining: timeRemaining, geo: geo)
            }
            .frame(width: geo.size.width, height: geo.size.height)
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

    /// The cupboard interior behind the utensils and ingredients; the rack is
    /// out in the clearing, so that tab gets the forest instead.
    @ViewBuilder
    private func backdrop(_ geo: GeometryProxy) -> some View {
        Group {
            if let art = UIImage(named: tab == .rack ? "forest-background" : "ui-storage-bg") {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFill()
            } else {
                AppTheme.background
            }
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .clipped()
    }

    // MARK: Content per tab

    @ViewBuilder
    private func content(_ geo: GeometryProxy) -> some View {
        switch tab {
        case .utensils:
            StorageCarousel(items: utensilItems, index: $utensilIndex, geo: geo) { item in
                guard let ut = Storage.utensils.first(where: { $0.id == item.id }) else { return }
                guard !item.isInUse else { outOfStock = item.name; return }
                takeUtensil(ut)
            }
            StorageCaption(text: "Select your Utensils", geo: geo)

        case .ingredients:
            StorageCarousel(items: ingredientItems, index: $ingredientIndex, geo: geo) { item in
                pickIngredient(item.id)
            }
            StorageCaption(text: "Select your Ingredients", geo: geo)

        case .rack:
            // The rack, same shelves and the same host round-trip as when it
            // was its own screen. Only the way in changed — and the chrome,
            // which this view already drew before handing over.
            DrawerView(inventory: inventory,
                       box: drawerBox,
                       session: session,
                       showsCloseButton: false,
                       onClose: onClose)
        }
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
                // silhouette the designer drew for exactly this.
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

#Preview("Storage — empty hands", traits: .landscapeLeft) {
    StorageView(inventory: PlayerInventory(),
                pantry: StoragePantry(),
                drawerBox: DrawerBox(),
                onClose: {})
}

#Preview("Storage — knife gone, rack loaded", traits: .landscapeLeft) {
    StorageView(inventory: PlayerInventory(ingredient: HeldIngredient(id: "whippedCream",
                                                                     name: "Whipped cream",
                                                                     isPrep: true),
                                           utensil: HeldUtensil(id: "whisk", name: "Whisk")),
                // Knife stock at zero: the carousel should show the dark
                // silhouette for it and nothing else.
                pantry: StoragePantry(utensilStock: ["knife": 0, "sifter": 1,
                                                     "whisk": 1, "mixer": 1, "pan": 1]),
                drawerBox: DrawerBox(slots: [
                    DrawerItem(foodID: "siftedFlour", name: "Sifted flour"),
                    DrawerItem(foodID: "choppedStrawberries", name: "Chopped strawberries"),
                    DrawerItem(foodID: "bakedBase", name: "Baked base"),
                    nil
                ]),
                onClose: {})
}
