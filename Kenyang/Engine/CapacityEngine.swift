import Foundation

struct CapacityEngine {
    static let platesToSatiety: Double = 3.0

    static func state(for visit: Visit) -> CapacityState {
        let spent = visit.tasteEvents.reduce(0.0) { $0 + $1.satietyCost }
        return CapacityState(maxSatiety: visit.declaredMaxSatiety, spent: spent)
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

    static func verdict(for visit: Visit) -> CapacityVerdict {
        let readings = visit.fullnessReadings.sorted { $0.at < $1.at }
        guard readings.count >= 1 else { return .insufficient }

        let state = state(for: visit)
        guard let latest = readings.last else { return .insufficient }

        let predicted = predictedFullness(
            CapacityState(maxSatiety: state.maxSatiety, spent: latest.cumulativeSatiety)
        )
        let delta = latest.value - predicted

        switch delta {
        case 2...:      return .overestimating
        case ...(-2):   return .underestimating
        default:        return .consistent
        }
    }

    static func correctedMax(for visit: Visit) -> Double {
        switch verdict(for: visit) {
        case .overestimating:  visit.declaredMaxSatiety * 0.8
        case .underestimating: visit.declaredMaxSatiety * 1.2
        default:               visit.declaredMaxSatiety
        }
    }

    static func fittedMax(from visits: [Visit], fallback: Double) -> Double {
        let completed = visits.filter { $0.endedAt != nil && !$0.tasteEvents.isEmpty }
        guard completed.count >= 3 else { return fallback }
        let totals = completed.map { v in v.tasteEvents.reduce(0.0) { $0 + $1.satietyCost } }
        return totals.reduce(0, +) / Double(totals.count)
    }
}
