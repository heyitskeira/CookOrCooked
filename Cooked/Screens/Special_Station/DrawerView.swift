//
//  DrawerView.swift
//  Cooked
//
//  The drawer overlay: four shelves in a 2x2 grid. Top row is refrigerated,
//  bottom row is room temperature.
//
//  Tap an empty shelf to put down what you're holding; tap a full one to pick
//  it back up. The hand is only emptied once the host says yes, so a refused
//  shelf never eats an ingredient.
//

import SwiftUI

struct DrawerView: View {
    /// The chef's hands — storing empties the ingredient slot, taking fills it.
    @ObservedObject var inventory: PlayerInventory
    /// Local drawer, used only when there's no networked game (test menu).
    @ObservedObject var box: DrawerBox
    /// The live game. When present the drawer is host-authoritative.
    var session: KitchenSession? = nil
    /// False when this is being shown as the storage room's Storage Rack tab,
    /// which draws its own back button and tab bar above it. Two stacked back
    /// buttons that do the same thing is the sort of thing you only notice once
    /// it ships.
    var showsCloseButton: Bool = true
    var onClose: () -> Void

    /// Shelf we've asked the host about and are waiting on.
    @State private var pendingSlot: Int? = nil
    @State private var notice: String? = nil
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        ZStack {
            if showsCloseButton { AppTheme.background }

            VStack(spacing: 22) {
                if showsCloseButton { header }
                shelves
                handHint
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, showsCloseButton ? 40 : 0)
            .padding(.vertical, showsCloseButton ? 28 : 0)
        }
        .ignoresSafeArea(edges: showsCloseButton ? .all : [])
        .overlay { noticePopup }
        // Host answers synchronously; a guest's reply lands here a moment later.
        .onChange(of: session?.drawerReply) { _, _ in applyReply() }
    }
    
    // MARK: Reading the shelves
    
    private func item(inSlot index: Int) -> DrawerItem? {
        session?.drawerItem(inSlot: index) ?? box.item(inSlot: index)
    }
    
    // MARK: Acting on a shelf
    
    private func tap(slot index: Int) {
        // Rotten food never touches a shelf — check this first, and return,
        // rather than falling into store/take with a stale rotten hand.
        if let held = inventory.ingredient, held.isRotten {
            notice = "Dispose the rotten ingredient"
            return
        }

        if item(inSlot: index) == nil {
            store(into: index)
        } else {
            take(from: index)
        }
    }
    
    private func store(into index: Int) {
        guard let held = inventory.ingredient else {
            notice = "You're not holding anything to put away"
            return
        }
        
        let entry = DrawerItem(foodID: held.id, name: held.name, isRotten: held.isRotten)
        
        if let session {
            pendingSlot = index
            session.storeInDrawer(entry, slot: index)
            applyReply()   // host replies immediately; guest arrives via onChange
        } else {
            guard box.store(entry, inSlot: index) else {
                notice = Drawer.canStore(entry.foodID, inSlot: index)
                ? "That shelf is already taken"
                : Drawer.rejectionReason(for: entry.foodID, name: entry.name)
                return
            }
            inventory.dropIngredient()
        }
    }
    
    /// Taking requires an empty ingredient hand.
    ///
    /// The alternative — swapping the held item onto the shelf just emptied —
    /// only works when the temperatures happen to match, and the failure path
    /// leaves an ingredient with nowhere to go. Refusing up front is honest and
    /// the player can always put theirs down first.
    private func take(from index: Int) {
        guard inventory.ingredient == nil else {
            notice = "Your hands are full — put that down first"
            return
        }
        if let session {
            pendingSlot = index
            session.takeFromDrawer(slot: index)
            applyReply()
        } else {
            guard let taken = box.take(fromSlot: index) else { return }
            putInHand(taken)
        }
    }
    
    private func putInHand(_ taken: DrawerItem) {
        inventory.pickUp(HeldIngredient(id: taken.foodID,
                                        name: taken.name,
                                        isRotten: taken.isRotten))
    }
    
    private func applyReply() {
        guard let session, let reply = session.drawerReply else { return }
        
        switch reply {
        case .stored(let slot):
            guard slot == pendingSlot else { return }
            inventory.dropIngredient()
        case .refused(let slot, let reason):
            guard slot == pendingSlot else { return }
            notice = reason
        case .took(let slot, let item):
            guard slot == pendingSlot else { return }
            if let item {
                putInHand(item)
            } else {
                notice = "Someone got there first"
            }
        }
        pendingSlot = nil
        session.clearDrawerReply()
    }
    
    // MARK: Header
    
    private var header: some View {
        ZStack {
            Text("Drawer")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(AppTheme.cream))
                        .overlay(Circle().stroke(AppTheme.ink, lineWidth: 3))
                }
                .accessibilityLabel("Leave the drawer")
                
                Spacer()
            }
        }
    }
    
    // MARK: The 2x2 grid
    
    private var shelves: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<Drawer.slotCount, id: \.self) { index in
                shelfCard(index)
            }
        }
    }
    
    private func shelfCard(_ index: Int) -> some View {
        let temperature = Drawer.temperature(ofSlot: index)
        let stored = item(inSlot: index)
        let isCold = temperature == .cold
        
        return Button {
            tap(slot: index)
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: temperature.icon)
                        .font(.system(size: 14, weight: .bold))
                    Text(temperature.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(isCold ? coldInk : roomInk)
                
                Spacer(minLength: 0)
                
                if let stored {
                    Text("🥣")
                        .font(.system(size: 30))
                    Text(stored.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Image(systemName: "tray")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(AppTheme.ink.opacity(0.25))
                    Text("Empty")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink.opacity(0.4))
                    
                    if temperature == .cold{
                        Text("This rack can only store: Macerated strawberry & whipped cream")
                            .multilineTextAlignment(.center)
                    }
                }
                
//                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isCold ? coldFill : roomFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.ink, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var coldFill: Color { Color(red: 0.82, green: 0.90, blue: 0.95) }
    private var roomFill: Color { AppTheme.cream }
    private var coldInk: Color { Color(red: 0.16, green: 0.40, blue: 0.58) }
    private var roomInk: Color { Color(red: 0.60, green: 0.36, blue: 0.14) }
    
    // MARK: What's in hand
    
    private var handHint: some View {
        Group {
            if let held = inventory.ingredient {
                Text("Holding: \(held.name)\(held.isRotten ? " - you cannot store rotten ingredient in drawers" : "") — tap an empty shelf")
                    .lineLimit(2)
            } else {
                Text("Hands empty — tap a full shelf to pick something up")
            }
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(AppTheme.ink.opacity(0.6))
        .multilineTextAlignment(.center)
    }
    
    // MARK: Refusals
    
    @ViewBuilder
    private var noticePopup: some View {
        if let text = notice {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { notice = nil }
                
                VStack(spacing: 14) {
                    Text("❄️").font(.system(size: 50))
                    Text(text)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)
                    
                    Button { notice = nil } label: {
                        Text("OK")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.cream)
                            .frame(width: 160, height: 56)
                            .background(Capsule().fill(AppTheme.tomato))
                            .overlay(Capsule().stroke(AppTheme.ink, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(32)
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
}

#Preview {
    DrawerView(inventory: PlayerInventory(ingredient: HeldIngredient(id: "bakedBase", name: "Baked base", isRotten: true)),
               box: DrawerBox(),
               onClose: {})
}
