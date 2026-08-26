//
//  DrawerStation.swift
//  Cooked
//
//  The storage rack: four shelves in a 2x2 grid where chefs park prepped
//  ingredients so their hands are free.
//
//      ┌───────────┬───────────┐
//      │  slot 0   │  slot 1   │   top shelf
//      ├───────────┼───────────┤
//      │  slot 2   │  slot 3   │   bottom shelf
//      └───────────┴───────────┘
//
//  RULES
//    • One item per shelf. Four items stored at most, kitchen-wide.
//    • Anything may go on any shelf. There is no cold half and no warm half.
//
//  The temperature rule that used to live here (top row refrigerated, bottom
//  room temperature, one correct shelf per food) is gone. It made a shelf that
//  looked empty refuse what you were holding, and the only way to learn which
//  shelf wanted what was to be told no — so the rack read as broken rather than
//  as a rule. Four interchangeable shelves is the whole model now: the only
//  question a shelf can answer is "is something already on you".
//
//  Like utensil stock, this is shared state: in a networked game the host owns
//  the real rack and guests read it off the snapshot. `DrawerBox` below is the
//  offline/test-menu equivalent.
//

import Foundation
import Combine

// MARK: - What sits on a shelf

/// One stored item. Carries its own display name so the rack UI doesn't have
/// to look anything up, and `isRotten` so a bad ingredient stays bad in storage.
nonisolated struct DrawerItem: Codable, Equatable {
    let foodID: String
    let name: String
    var isRotten: Bool = false
}

// MARK: - Shelf layout

nonisolated enum Drawer {

    /// Four shelves, laid out 2x2 — two on the top plank, two on the bottom.
    static let slotCount = 4

    /// Player-facing reason a shelf refused an item. Occupancy is the only
    /// refusal left, so this is the only sentence.
    static let occupiedMessage = "That shelf is already taken"
}

// MARK: - Offline rack

/// The rack when there's no networked game (test menu). Mirrors the shape the
/// host keeps, so `DrawerView` can drive either one.
@MainActor
final class DrawerBox: ObservableObject {

    @Published private(set) var slots: [DrawerItem?]

    init(slots: [DrawerItem?] = Array(repeating: nil, count: Drawer.slotCount)) {
        self.slots = slots
    }

    func item(inSlot index: Int) -> DrawerItem? {
        guard index >= 0, index < slots.count else { return nil }
        return slots[index]
    }

    /// Put an item on a shelf. Fails only if the shelf is taken — the caller
    /// keeps holding it.
    @discardableResult
    func store(_ item: DrawerItem, inSlot index: Int) -> Bool {
        guard index >= 0, index < slots.count, slots[index] == nil else { return false }
        slots[index] = item
        return true
    }

    /// Take whatever is on a shelf, emptying it.
    func take(fromSlot index: Int) -> DrawerItem? {
        guard index >= 0, index < slots.count, let item = slots[index] else { return nil }
        slots[index] = nil
        return item
    }

    func reset() {
        slots = Array(repeating: nil, count: Drawer.slotCount)
    }
}
