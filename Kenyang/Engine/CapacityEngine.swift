import Foundation

enum CapacityEngine {
    static let platesToSatiety: Double = 3.0
    static let minimumFittedMeals = 3
    static let correctionGain = 0.5
    static let correctionClamp = 0.2

    static func state(for visit: Visit) -> CapacityState {
        CapacityState(maxSatiety: correctedMax(for: visit),
                      spent: totalSatiety(of: visit),
                      declaredMax: visit.declaredMaxSatiety)
    }

    static func totalSatiety(of visit: Visit) -> Double {
        visit.tasteEvents.reduce(0) { $0 + $1.satietyCost }
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

    /// The middle of each band `predictedFullness` reports, so the two are inverses.
    static func fractionUsed(atFullness fullness: Int) -> Double? {
        switch fullness {
        case 1: 0.10
        case 2: 0.325
        case 3: 0.575
        case 4: 0.80
        case 5: 0.95
        default: nil
        }
    }

    static func impliedMax(for reading: FullnessReading) -> Double? {
        guard reading.cumulativeSatiety > 0,
              let fraction = fractionUsed(atFullness: reading.value) else { return nil }
        return reading.cumulativeSatiety / fraction
    }

    /// Moves the declared capacity part of the way toward what the diner's fullness
    /// readings imply, never more than `correctionClamp` of it in one meal.
    static func correctedMax(for visit: Visit) -> Double {
        let declared = visit.declaredMaxSatiety
        let implied = visit.fullnessReadings.compactMap(impliedMax(for:))
        guard declared > 0, !implied.isEmpty else { return declared }

        let mean = implied.reduce(0, +) / Double(implied.count)
        let limit = declared * correctionClamp
        return declared + min(max(correctionGain * (mean - declared), -limit), limit)
    }

    /// Tests the declared capacity, not the corrected one: the corrected figure already
    /// leans toward the reading, so it would always look consistent.
    static func verdict(declaredMax: Double, readings: [FullnessReading]) -> CapacityVerdict {
        guard let latest = readings.max(by: { $0.at < $1.at }) else { return .insufficient }
        let predicted = predictedFullness(CapacityState(maxSatiety: declaredMax, spent: latest.cumulativeSatiety))
        switch latest.value - predicted {
        case 2...:    return .overestimating
        case ...(-2): return .underestimating
        default:      return .consistent
        }
    }

    /// Only meals that ended with the diner full measure capacity. Every other ending is
    /// a lower bound, so it can raise the estimate but never lower it.
    static func fittedMax(from visits: [Visit], fallback: Double) -> Double {
        let completed = visits.filter { !$0.isActive && !$0.tasteEvents.isEmpty }
        let measured = completed.filter { $0.endedBecause.measuresCapacity }
        let floor = completed
            .filter { !$0.endedBecause.measuresCapacity }
            .map(totalSatiety(of:))
            .max() ?? 0

        guard measured.count >= minimumFittedMeals else { return max(fallback, floor) }
        let mean = measured.map(totalSatiety(of:)).reduce(0, +) / Double(measured.count)
        return max(mean, floor)
    }
}
