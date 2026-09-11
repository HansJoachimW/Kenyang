import Foundation

/// Seed values for a meal, in one place.
///
/// These were literals repeated across the start screen, the App Intents and the
/// battery — `250_000` in three files, `90` in five, `maxSatiety: 9` in seven, some
/// written as `3 * CapacityEngine.platesToSatiety` and some as a bare `9`.
///
/// They are **defaults, not constants**: price and tier are captured per venue and
/// already persist on `Restaurant`, and the diner can change any of them before the
/// meal starts. Seating limit is the exception — it is printed on the menu ("Table 90
/// minutes") and so is a property of the venue that the schema does not yet hold.
enum SessionDefaults {
    /// Rupiah per head. A Gyu-Kaku Standard adult cover, used only until a captured
    /// menu supplies the real figure.
    static let pricePerHead: Double = 250_000

    /// Minutes at the table. Both venues in scope print 90.
    static let seatingMinutes = 90

    /// Coarse onboarding prior — `BUFFET.md` §6 layer 0.
    static let plates: Double = 3

    /// The same prior in satiety units, so nothing has to spell out `3 * 3.0`.
    static var maxSatiety: Double { plates * CapacityEngine.platesToSatiety }
}
