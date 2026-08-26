//
//  DrawerView.swift
//  Cooked
//
//  The Storage Rack tab: a wooden rack of two planks, four places on it, out
//  in the clearing behind the pantry.
//
//  Tap anywhere on the rack to set down what you're holding — it goes to the
//  first free place, left to right, top row first. Tap something already on
//  the rack to pick it back up. The hand is only emptied once the host says
//  yes, so a refused shelf never eats an ingredient.
//
//  What changed from the old drawer: there is no cold half and no warm half.
//  Every shelf takes every food. The old rule (whipped cream must go up top,
//  melted butter must go down below) meant an empty-looking shelf could refuse
//  what you were holding, and the only way to learn which shelf wanted what
//  was to be told no. Four interchangeable places, four items kitchen-wide,
//  and the one refusal left is "something is already there".
//

import SwiftUI

struct DrawerView: View {
    /// The chef's hands — storing empties the ingredient slot, taking fills it.
    @ObservedObject var inventory: PlayerInventory
    /// Local rack, used only when there's no networked game (test menu).
    @ObservedObject var box: DrawerBox
    /// The live game. When present the rack is host-authoritative.
    var session: KitchenSession? = nil
    /// False when this is shown as the storage room's Storage Rack tab, which
    /// draws its own back plaque, tab pill and clock above it. Two stacked back
    /// buttons that do the same thing is the sort of thing you only notice once
    /// it ships.
    var showsCloseButton: Bool = true
    var onClose: () -> Void

    /// Shelf we've asked the host about and are waiting on.
    @State private var pendingSlot: Int? = nil
    @State private var notice: String? = nil

    // MARK: Geometry — storage-artboard space, see `StorageCanvas`

    /// The rack itself. It runs off the bottom of the screen on purpose: the
    /// art has legs below the lower plank and the frame crops them.
    private static let rackFrame = CGRect(x: 82, y: 91, width: 733, height: 357)

    /// The hand-drawn "tap anywhere on the shelf…" note down the left side.
    private static let instructionFrame = CGRect(x: 54, y: 236, width: 84, height: 125)

    /// Where the top of each plank is — what a stored item rests on.
    private static let topShelfSurface: CGFloat = 250
    private static let bottomShelfSurface: CGFloat = 378
    /// Centres of the two columns, and the box one item gets.
    private static let leftColumnX: CGFloat = 340
    private static let rightColumnX: CGFloat = 592
    /// Down from 200x96, by the same ~15% the carousel items came down by, so
    /// the three tabs stay in proportion with each other.
    ///
    /// Safe to change on its own: the slot is bottom-aligned onto the shelf
    /// surface and the seating offset is a fraction of this height, so a
    /// shorter slot still rests its prep on the plank rather than floating it.
    private static let slotSize = CGSize(width: 172, height: 82)

    /// Slot index → the box its contents are drawn in, resting on the plank.
    private static func slotFrame(_ index: Int) -> CGRect {
        let x = index % 2 == 0 ? leftColumnX : rightColumnX
        let surface = index < 2 ? topShelfSurface : bottomShelfSurface
        return CGRect(x: x - slotSize.width / 2,
                      y: surface - slotSize.height,
                      width: slotSize.width,
                      height: slotSize.height)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if showsCloseButton { backdrop(geo) }

                rack(geo)
                instruction(geo)
                ForEach(0..<Drawer.slotCount, id: \.self) { index in
                    storedItem(index, geo: geo)
                }

                if showsCloseButton {
                    StorageBackButton(geo: geo, action: onClose)
                    StorageHands(inventory: inventory, geo: geo,
                             pawAsset: session?.localPawAsset ?? ChefCast.paw(seat: 0, roomCode: ""))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay { noticePopup }
        // Host answers synchronously; a guest's reply lands here a moment later.
        .onChange(of: session?.drawerReply) { _, _ in applyReply() }
    }

    // MARK: Reading the shelves

    private func item(inSlot index: Int) -> DrawerItem? {
        session?.drawerItem(inSlot: index) ?? box.item(inSlot: index)
    }

    /// The place a "put this down" tap lands: first free, left to right, top
    /// row first. Reads the host's table in a game and the local box otherwise,
    /// so both paths agree on which shelf is next.
    private var firstFreeSlot: Int? {
        (0..<Drawer.slotCount).first { item(inSlot: $0) == nil }
    }

    // MARK: Acting on the rack

    /// A tap on bare rack — put down whatever is in hand.
    private func tapEmptyRack() {
        if let blocked = handBlockMessage { notice = blocked; return }
        guard inventory.ingredient != nil else {
            notice = "You're not holding anything to put away"
            return
        }
        guard let slot = firstFreeSlot else {
            notice = "The rack is full — take something off it first"
            return
        }
        store(into: slot)
    }

    /// A tap on something already on the rack — pick it up.
    private func tapStored(_ index: Int) {
        if let blocked = handBlockMessage { notice = blocked; return }
        take(from: index)
    }

    /// Rot never touches a shelf, and it is checked before anything else so a
    /// stale rotten hand can't fall through into store/take.
    private var handBlockMessage: String? {
        if inventory.ingredient?.isRotten == true { return "Dispose the rotten ingredient" }
        return nil
    }

    private func store(into index: Int) {
        guard let held = inventory.ingredient else { return }

        let entry = DrawerItem(foodID: held.id, name: held.name, isRotten: held.isRotten)

        if let session {
            pendingSlot = index
            session.storeInDrawer(entry, slot: index)
            applyReply()   // host replies immediately; guest arrives via onChange
        } else {
            guard box.store(entry, inSlot: index) else {
                notice = Drawer.occupiedMessage
                return
            }
            inventory.dropIngredient()
        }
    }

    /// Taking requires an empty ingredient hand.
    ///
    /// The alternative — swapping the held item onto the shelf just emptied —
    /// reads as a single tap doing two things, and the failure path leaves an
    /// ingredient with nowhere to go. Refusing up front is honest, and the
    /// player can always put theirs down first.
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
                                        isRotten: taken.isRotten,
                                        // Anything that was worth parking here
                                        // is a prep, and a prep locks the hand
                                        // — picking it back up has to restore
                                        // that or the lock leaks away through
                                        // the rack.
                                        isPrep: GatingBridge.isPrep(taken.foodID)))
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

    // MARK: The rack

    /// Forest clearing. Only drawn standalone — as a tab, `StorageView` has
    /// already laid this down behind all three shelves.
    private func backdrop(_ geo: GeometryProxy) -> some View {
        Group {
            if let art = UIImage(named: "forest-background") {
                Image(uiImage: art).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.24, green: 0.32, blue: 0.26),
                                        Color(red: 0.14, green: 0.20, blue: 0.16)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .clipped()
        .ignoresSafeArea()
    }

    /// The rack art, and the whole of it as one "put it down" target.
    ///
    /// One target rather than four, because that is what the note beside it
    /// promises: tap the shelf, the item lands in the next free place. Four
    /// invisible boxes would mean a tap between them did nothing, which is the
    /// same dead-tap problem the temperature rule used to cause.
    private func rack(_ geo: GeometryProxy) -> some View {
        Button(action: tapEmptyRack) {
            Group {
                if let art = UIImage(named: "ui-storage") {
                    Image(uiImage: art).resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.55, green: 0.38, blue: 0.22))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .storagePlaced(Self.rackFrame, alignment: .top, in: geo)
        .accessibilityLabel("Storage rack")
        .accessibilityHint(inventory.ingredient == nil
                           ? "Nothing in hand to put away"
                           : "Put down what you're holding")
    }

    /// The hand-lettered note telling a first-time chef what the rack is for.
    /// It ships as artwork, not text — it is drawn in the game's own hand,
    /// paw and all.
    private func instruction(_ geo: GeometryProxy) -> some View {
        Group {
            if let art = UIImage(named: "ui-drawer-instruction") {
                Image(uiImage: art).resizable().scaledToFit()
            } else {
                Text("Tap anywhere on the shelf to set aside your partially prepared ingredients")
                    .font(.system(size: 11 * StorageCanvas.scale(in: geo),
                                  weight: .bold, design: .rounded))
                    .foregroundStyle(StoragePalette.cream)
            }
        }
        .storagePlaced(Self.instructionFrame, in: geo)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// What's on one shelf, resting on the plank. `.bottom` alignment is what
    /// makes it rest rather than float: the art is every shape from a wide
    /// cake to a tall bowl, and centring the slack in the box would leave the
    /// short ones hovering above the wood.
    @ViewBuilder
    private func storedItem(_ index: Int, geo: GeometryProxy) -> some View {
        if let stored = item(inSlot: index) {
            Button {
                tapStored(index)
            } label: {
                Group {
                    if let art = StorageArt.image(stored.foodID) ?? FoodArt.art(stored.foodID) {
                        Image(uiImage: art).resizable().scaledToFit()
                    } else {
                        Image(systemName: FoodArt.look(stored.foodID).symbol)
                            .resizable().scaledToFit()
                            .foregroundStyle(FoodArt.look(stored.foodID).tint)
                            .padding(10 * StorageCanvas.scale(in: geo))
                    }
                }
                .shadow(color: .black.opacity(0.35),
                        radius: 6 * StorageCanvas.scale(in: geo),
                        x: 0, y: 4 * StorageCanvas.scale(in: geo))
                .contentShape(Rectangle())
                // Seat the object on the plank rather than the image's own
                // bottom edge — see `StorageArt.seatOffsetFraction`. The slot
                // is far wider than it is tall, so `scaledToFit` always makes
                // the drawing exactly `slotSize.height` tall and this offset
                // is exact rather than approximate.
                .offset(y: StorageCanvas.rect(Self.slotFrame(index), in: geo).height
                        * StorageArt.seatOffsetFraction(stored.foodID))
            }
            .buttonStyle(.plain)
            .storagePlaced(Self.slotFrame(index), alignment: .bottom, in: geo)
            .accessibilityLabel(stored.name)
            .accessibilityHint("Take it off the rack")
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: Refusals

    @ViewBuilder
    private var noticePopup: some View {
        if let text = notice {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { notice = nil }

                VStack(spacing: 14) {
                    Text("🪵").font(.system(size: 50))
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

#Preview("Rack — two parked preps", traits: .landscapeLeft) {
    DrawerView(inventory: PlayerInventory(),
               box: DrawerBox(slots: [
                DrawerItem(foodID: "siftedFlour", name: "Sifted flour"),
                DrawerItem(foodID: "choppedStrawberries", name: "Chopped strawberries"),
                nil,
                nil
               ]),
               onClose: {})
}

#Preview("Rack — full, hands empty", traits: .landscapeLeft) {
    DrawerView(inventory: PlayerInventory(),
               box: DrawerBox(slots: [
                DrawerItem(foodID: "siftedFlour", name: "Sifted flour"),
                DrawerItem(foodID: "choppedStrawberries", name: "Chopped strawberries"),
                DrawerItem(foodID: "bakedBase", name: "Baked base"),
                DrawerItem(foodID: "meltedButter", name: "Melted butter")
               ]),
               onClose: {})
}
