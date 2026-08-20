//
//  DrawerStation.swift
//  Cooked
//
//  The drawer: four shelves in a 2x2 grid where chefs park prepped ingredients
//  so their hands are free.
//
//      ┌───────────┬───────────┐
//      │  slot 0   │  slot 1   │   top row  — cold
//      ├───────────┼───────────┤
//      │  slot 2   │  slot 3   │   bottom row — room temperature
//      └───────────┴───────────┘
//
//  RULES
//    • One item per shelf. Four items stored at most, kitchen-wide.
//    • Every food has one correct temperature. Putting whipped cream on a room
//      shelf is refused outright — the item stays in the chef's hand.
//
//  Like utensil stock, this is shared state: in a networked game the host owns
//  the real drawer and guests read it off the snapshot. `DrawerBox` below is the
//  offline/test-menu equivalent.
//

import Foundation
import Combine

// MARK: - Temperature

nonisolated enum StorageTemperature: String, Codable, Equatable {
    case cold, room

    var label: String {
        switch self {
        case .cold: return "Cold"
        case .room: return "Room temp"
        }
    }

    var icon: String {
        switch self {
        case .cold: return "snowflake"
        case .room: return "thermometer.medium"
        }
    }
}

// MARK: - What sits on a shelf

/// One stored item. Carries its own display name so the drawer UI doesn't have
/// to look anything up, and `isRotten` so a bad ingredient stays bad in storage.
nonisolated struct DrawerItem: Codable, Equatable {
    let foodID: String
    let name: String
    var isRotten: Bool = false
}

// MARK: - Shelf layout + the temperature each food wants

nonisolated enum Drawer {

    /// Four shelves, laid out 2x2.
    static let slotCount = 4

    /// Top row is refrigerated, bottom row is not.
    static func temperature(ofSlot index: Int) -> StorageTemperature {
        index < 2 ? .cold : .room
    }

    /// Where each food has to be kept. Ids match `FoodID.rawValue` and the ids
    /// used by `Storage.ingredients`, so raw and prepped foods both resolve.
    ///
    /// The two that matter most for play are deliberate opposites: whipped cream
    /// must stay cold or it collapses, melted butter must stay warm or it sets
    /// again. Everything else follows ordinary kitchen sense.
    private static let required: [String: StorageTemperature] = [
        // Raw
        "strawberries":          .cold,
        "cream":                 .cold,
        "butter":                .cold,
        "egg":                   .cold,
        "flour":                 .room,
        "sugar":                 .room,
        // Prepped
        "choppedStrawberries":   .cold,
        "maceratedStrawberries": .cold,
        "siftedFlour":           .room,
        "meltedButter":          .room,
        "beatenEgg":             .cold,
        "rawDough":              .cold,
        "whippedCream":          .cold,
        "bakedBase":             .room,
        "finishedCake":          .cold
    ]

    /// Anything not listed is treated as room temperature — a new food should
    /// not become unstorable just because this table wasn't updated.
    static func requiredTemperature(for foodID: String) -> StorageTemperature {
        required[foodID] ?? .room
    }

    static func canStore(_ foodID: String, inSlot index: Int) -> Bool {
        guard index >= 0, index < slotCount else { return false }
        return requiredTemperature(for: foodID) == temperature(ofSlot: index)
    }

    /// Player-facing reason a shelf refused an item.
    static func rejectionReason(for foodID: String, name: String) -> String {
        switch requiredTemperature(for: foodID) {
        case .cold: return "\(name) has to go on a cold shelf"
        case .room: return "\(name) has to go on a room-temp shelf"
        }
    }
}

// MARK: - Offline drawer

/// The drawer when there's no networked game (test menu). Mirrors the shape the
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

    /// Put an item on a shelf. Fails if the shelf is taken or the wrong
    /// temperature — the caller keeps holding it.
    @discardableResult
    func store(_ item: DrawerItem, inSlot index: Int) -> Bool {
        guard index >= 0, index < slots.count,
              slots[index] == nil,
              Drawer.canStore(item.foodID, inSlot: index) else { return false }
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
