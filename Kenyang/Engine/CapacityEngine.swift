import Foundation

struct CapacityEngine {
    static let platesToSatiety: Double = 3.0

    /// How many **fullness-terminated** meals the across-meal fit needs before it will
    /// speak. Censored meals do not count toward it — see `fittedMax`.
    static let minimumFittedMeals = 3

    /// The within-meal correction takes half the residual and never moves the estimate
    /// by more than a fifth in one meal. The gain is there because a single mid-meal
    /// reading on a 1–5 scale is a coarse instrument; the clamp is there because the
    /// figure it moves is the budget every round is planned against.
    static let correctionGain = 0.5
    static let correctionClamp = 0.2

    /// The live capacity, corrected by anything the diner has said this meal.
    ///
    /// `maxSatiety` is the best current estimate and `declaredMax` is the prior it was
    /// corrected from, so the falsification tools can test the prior rather than the
    /// answer derived from them.
    static func state(for visit: Visit) -> CapacityState {
        let spent = visit.tasteEvents.reduce(0.0) { $0 + $1.satietyCost }
        return CapacityState(maxSatiety: correctedMax(for: visit),
                             spent: spent,
                             declaredMax: visit.declaredMaxSatiety)
    }

    static func cumulativeSatiety(for visit: Visit, upTo date: Date = .now) -> Double {
        visit.tasteEvents.filter { $0.at <= date }.reduce(0.0) { $0 + $1.satietyCost }
    }

    static func predictedFullness(_ state: CapacityState) -> Int {
        let used = state.maxSatiety > 0 ? state.spent / state.maxSatiety : 0
        switch used {
        case ..<0.2:  return 1
        case ..<0.45: return 2
        case ..<0.7:  return 3
        case ..<0.9:  return 4
        default:      return 5
        }
    }

    /// The midpoint of each band `predictedFullness` reports, so the two are inverses.
    /// `nil` for anything off the 1–5 scale rather than a clamp, because a reading the
    /// app did not offer is a bug and should not quietly become a correction.
    static func fractionAt(_ fullness: Int) -> Double? {
        switch fullness {
        case 1: 0.10
        case 2: 0.325
        case 3: 0.575
        case 4: 0.80
        case 5: 0.95
        default: nil
        }
    }

    /// What one reading says `S_max` must be. *"I'm at 4 of 5 having eaten 6.2"* puts the
    /// meal's ceiling near 6.2 / 0.8. A reading taken before anything was eaten carries
    /// no information and returns `nil` rather than dividing into zero.
    static func impliedMax(for reading: FullnessReading) -> Double? {
        guard reading.cumulativeSatiety > 0,
              let fraction = fractionAt(reading.value) else { return nil }
        return reading.cumulativeSatiety / fraction
    }

    // MARK: - Layer 1, within-meal

    /// **A clamped residual update, not a flat step.** The old rule moved the estimate by
    /// ±20% off a ternary verdict: the same jump whether the diner was one point out or
    /// three, in the same direction however far off it was, and read only the latest
    /// reading. It was also never called — layer 1 was declared and dead, which is why
    /// the ±20% never showed up in anything.
    ///
    /// Now every reading in the meal implies a ceiling, and the estimate moves a fraction
    /// of the distance to their mean. Say *"three of five"* at 3.0 satiety and the implied
    /// ceiling is 5.2 against a declared 9 — the estimate comes down, by as much as the
    /// error justifies and no further than the clamp allows.
    static func correctedMax(for visit: Visit) -> Double {
        let declared = visit.declaredMaxSatiety
        guard declared > 0 else { return declared }

        let implied = visit.fullnessReadings.compactMap(impliedMax(for:))
        guard !implied.isEmpty else { return declared }

        let mean = implied.reduce(0, +) / Double(implied.count)
        let limit = declared * correctionClamp
        return declared + min(max(correctionGain * (mean - declared), -limit), limit)
    }

    /// Whether the capacity model is currently trustworthy. One rule, two callers — this
    /// and `checkCapacityModel`, which is the tool that reports it to the model.
    ///
    /// It tests `declaredMax`, never the corrected figure. Testing the correction against
    /// the reading that produced it would return `consistent` by construction.
    static func verdict(maxSatiety: Double, readings: [FullnessReading]) -> CapacityVerdict {
        guard let latest = readings.sorted(by: { $0.at < $1.at }).last else { return .insufficient }
        let predicted = predictedFullness(
            CapacityState(maxSatiety: maxSatiety, spent: latest.cumulativeSatiety)
        )
        switch latest.value - predicted {
        case 2...:    return .overestimating
        case ...(-2): return .underestimating
        default:      return .consistent
        }
    }

    static func verdict(for visit: Visit) -> CapacityVerdict {
        verdict(maxSatiety: visit.declaredMaxSatiety, readings: visit.fullnessReadings)
    }

    // MARK: - Layer 2, across-meal

    /// **Only a `fullness` meal measures capacity.** Every other ending — the clock, the
    /// venue closing, simply leaving — says `S_max >= this total` and nothing more.
    ///
    /// Averaging those lower bounds in with real observations is what biased `S_max`
    /// downward, and did it *worse the more the app was used* while every screen kept
    /// looking correct. They are not discarded, because a lower bound is still evidence
    /// in one direction: **a censored meal can raise the estimate and can never lower
    /// it.** If you once ate 11 and left with room, no number of short meals makes 9
    /// the answer.
    static func fittedMax(from visits: [Visit], fallback: Double) -> Double {
        let completed = visits.filter { $0.endedAt != nil && !$0.tasteEvents.isEmpty }
        let measured = completed.filter { $0.endedBecause.measuresCapacity }
        let censored = completed.filter { !$0.endedBecause.measuresCapacity }

        // The largest lower bound is the only thing the censored meals say.
        let floor = censored.map(total(of:)).max() ?? 0

        guard measured.count >= minimumFittedMeals else { return max(fallback, floor) }
        let mean = measured.map(total(of:)).reduce(0, +) / Double(measured.count)
        return max(mean, floor)
    }

    private static func total(of visit: Visit) -> Double {
        visit.tasteEvents.reduce(0.0) { $0 + $1.satietyCost }
    }

    // MARK: - Layer 3, per-category density

    /// Readings needed before a category's density will be fitted at all.
    static let minimumDensitySamples = 8

    /// How much of the satiety eaten before a reading must belong to one category before
    /// that reading is allowed to say anything about it.
    static let dominanceShare = 0.5

    /// **Shipped silenced** — `BUFFET.md` Principle 30: ship the mechanism and let the
    /// guardrail keep it quiet until the samples exist.
    ///
    /// Nothing reads this. `ValueEngine.satietyCost` still uses
    /// `MenuCategory.satietyDensity`, the prior table in §6b.1 that **has never been
    /// checked against real eating** — and T64, the test that would say whether the
    /// continuous model deserves this much precision, needs a real meal and has not run.
    /// Wiring it in before then would be fitting a refinement on top of a curve nobody
    /// has validated.
    ///
    /// The estimate is deliberately coarse. A reading only speaks about a category that
    /// made up most of what was eaten before it, and the coefficient is the ratio the
    /// diner's own report implies: report fuller than predicted and the food was denser
    /// than the table said.
    static func fittedDensity(for category: MenuCategory, from visits: [Visit]) -> Double? {
        let samples: [Double] = visits.flatMap { visit -> [Double] in
            let declared = visit.declaredMaxSatiety
            guard declared > 0 else { return [] }
            return visit.fullnessReadings.compactMap { reading -> Double? in
                guard let implied = impliedMax(for: reading), implied > 0 else { return nil }
                let eaten = visit.tasteEvents.filter { $0.at <= reading.at }
                let spent = eaten.reduce(0.0) { $0 + $1.satietyCost }
                guard spent > 0 else { return nil }
                let here = eaten.filter { $0.category == category }
                    .reduce(0.0) { $0 + $1.satietyCost }
                guard here / spent >= dominanceShare else { return nil }
                return declared / implied
            }
        }
        guard samples.count >= minimumDensitySamples else { return nil }
        let mean = samples.reduce(0, +) / Double(samples.count)
        return category.satietyDensity * mean
    }

    // MARK: - The ordinal fallback

    /// Capacity remaining expressed in the five coarse states rather than as a number —
    /// `TESTS.md` T65.
    ///
    /// T64 decides whether this is needed and it takes a real meal: if `predictedFullness`
    /// does not track what the diner reports, `S_max` is not accurate enough to knapsack
    /// against and a continuous budget is false precision. This is the budget the beam
    /// search runs on instead, and it is built now so the fallback is **proven runnable
    /// before layer 3 is built** — layer 3 being the part it throws away.
    static func ordinalRemaining(_ state: CapacityState) -> Double {
        let stepsLeft = max(0, 5 - predictedFullness(state))
        return Double(stepsLeft) * state.maxSatiety / 5.0
    }
}
