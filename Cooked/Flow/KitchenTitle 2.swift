//
//  KitchenTitle.swift
//  Cooked
//
//  A kitchen is named after whoever opened it, so there is no separate name to
//  type and nothing to keep in sync. The host's chef name is what travels over
//  Bonjour and sits in `KitchenSession.kitchenName`; the possessive is put back
//  on at the point of drawing, so the raw name stays usable on its own.
//

import Foundation

enum KitchenTitle {

    /// "Bambi" -> "Bambi's Kitchen". Used in the list of active kitchens.
    static func readable(_ host: String) -> String {
        let name = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "A Kitchen" }
        return "\(possessive(name)) Kitchen"
    }

    /// The lettering on the rock, which the design sets in capitals.
    static func banner(_ host: String) -> String {
        readable(host).uppercased()
    }

    /// "Bambi" -> "Bambi's", but "Charles" -> "Charles'". Worth the four lines:
    /// chef names are typed by players, and "Charles's Kitchen" reads wrong
    /// enough to notice on a screen this size.
    static func possessive(_ name: String) -> String {
        guard let last = name.last else { return name }
        return last == "s" || last == "S" ? "\(name)'" : "\(name)'s"
    }
}
