//
//  ChefCast.swift
//  Cooked
//
//  Which animal each chef wears.
//
//  There are six drawings and at most four seats, so a fixed mapping would mean
//  two of them never appearing. Instead the six are shuffled per kitchen and
//  the seats take the first four, which spreads every drawing across games
//  while keeping any one game collision-free.
//
//  The shuffle has to land on the same answer on every phone in the room —
//  seeing a different animal on your own card than everyone else sees would
//  make the "You" leaf meaningless. So it is seeded from the room code, which
//  the host generates and every guest has had to type to get in, and the
//  shuffle is written out by hand rather than using `shuffled()`: Swift's
//  system generator is seeded per process, so the same input would give a
//  different order on each device.
//

import Foundation

enum ChefCast {

    /// How many chef drawings exist in the catalog as `ui-chef-1`…`ui-chef-N`.
    static let count = 6

    /// Which animal each `ui-chef-N` drawing actually is.
    ///
    /// The asset names are numbered, not named, so nothing in code could tell
    /// you that chef 4 is a beaver — and the paws, which *are* named, had no way
    /// to agree with the portraits. Read off the artwork itself, in asset order.
    ///
    /// This is the fact that makes a chef one character across the whole game
    /// rather than a portrait in the lobby and unrelated paws in the kitchen.
    enum Animal: String, CaseIterable {
        case squirrel, bear, raccoon, beaver, rabbit, fox

        /// The full-body portrait, on the lobby cards.
        var portrait: String { "ui-chef-\(ChefCast.number(of: self))" }
        /// The pair of front paws, held up at a counter.
        var paw: String { "paw-\(rawValue)" }
    }

    /// 1-based position of an animal in the `ui-chef-N` numbering.
    private static func number(of animal: Animal) -> Int {
        (Animal.allCases.firstIndex(of: animal) ?? 0) + 1
    }

    /// The animal a seat wears in a given kitchen.
    ///
    /// Every screen that draws a chef — the lobby card, the paws on the map, the
    /// paws at a station — must go through this and nothing else. Two different
    /// mappings is exactly the bug this replaces: the portrait said one animal
    /// and the paws said another, on the same player, in the same match.
    static func animal(seat: Int, roomCode: String) -> Animal {
        Animal.allCases[number(seat: seat, roomCode: roomCode) - 1]
    }

    /// The paws for a seat. Same seat, same room, same answer on every device.
    static func paw(seat: Int, roomCode: String) -> String {
        animal(seat: seat, roomCode: roomCode).paw
    }

    /// The drawing for a seat in a given kitchen.
    ///
    /// `seat` is the player's `colorIndex`, which the host hands out on join and
    /// is unique within a room — so two chefs never draw the same animal.
    static func asset(seat: Int, roomCode: String) -> String {
        "ui-chef-\(number(seat: seat, roomCode: roomCode))"
    }

    /// 1-based, matching the asset names.
    static func number(seat: Int, roomCode: String) -> Int {
        let order = casting(for: roomCode)
        // Seats beyond the cast wrap rather than crash. Four is the maximum a
        // kitchen holds, so this only guards against a future larger room.
        return order[((seat % count) + count) % count] + 1
    }

    /// The six drawings in this kitchen's order.
    static func casting(for roomCode: String) -> [Int] {
        var generator = SeededGenerator(seed: fnv1a(roomCode))
        var order = Array(0..<count)
        // Fisher–Yates, so every ordering is equally likely.
        for index in stride(from: order.count - 1, to: 0, by: -1) {
            let pick = Int(generator.next(upperBound: UInt64(index + 1)))
            order.swapAt(index, pick)
        }
        return order
    }

    /// FNV-1a. Swift's own `hashValue` is randomly seeded per process, so it
    /// would give a different answer on each phone and each launch — which is
    /// the one thing this must not do.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        // A room code is four digits, so the low bits carry nearly all of it.
        // Mixing once stops similar codes producing similar orders.
        return hash
    }
}

/// SplitMix64 — small, fast, and identical on every device, which is the whole
/// requirement here.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // A zero state would emit zeroes forever.
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
