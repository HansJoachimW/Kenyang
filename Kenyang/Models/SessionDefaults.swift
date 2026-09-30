import Foundation

/// Seed values for a meal, in one place.
///
/// These were literals repeated across the start screen, the App Intents and the
/// battery — `250_000` in three files, `90` in five, `maxSatiety: 9` in seven, some
/// written as `3 * CapacityEngine.platesToSatiety` and some as a bare `9`.
///
/// Price and seating come from `BuffetMenu.default`, the menu every session starts from.
enum SessionDefaults {
    /// Rupiah per head, from the default menu.
    static var pricePerHead: Double { BuffetMenu.default.pricePerHead }

    /// Minutes at the table, from the default menu.
    static var seatingMinutes: Int { BuffetMenu.default.seatingMinutes }

    /// Coarse onboarding prior — `BUFFET.md` §6 layer 0.
    static let plates: Double = 3

    /// The same prior in satiety units, so nothing has to spell out `3 * 3.0`.
    static var maxSatiety: Double { plates * CapacityEngine.platesToSatiety }
}
