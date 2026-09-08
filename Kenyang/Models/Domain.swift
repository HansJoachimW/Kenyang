import Foundation
import FoundationModels

@Generable
enum MenuCategory: String, Codable, CaseIterable, Sendable {
    case starch, fried, soup, dessert, meat, vegetable, raw, unknown

    var satietyDensity: Double {
        switch self {
        case .starch:    1.6
        case .fried:     1.3
        case .soup:      1.2
        case .dessert:   1.0
        case .unknown:   1.0
        case .meat:      0.9
        case .vegetable: 0.6
        case .raw:       0.5
        }
    }

    var priorValue: Double {
        switch self {
        case .meat:      0.80
        case .raw:       0.75
        case .unknown:   0.50
        case .vegetable: 0.45
        case .soup:      0.40
        case .dessert:   0.40
        case .fried:     0.35
        case .starch:    0.20
        }
    }

    var label: String {
        switch self {
        case .starch:    "Rice & noodles"
        case .fried:     "Fried"
        case .soup:      "Soup & broth"
        case .dessert:   "Dessert"
        case .meat:      "Meat"
        case .vegetable: "Vegetables"
        case .raw:       "Raw & sashimi"
        case .unknown:   "Unknown"
        }
    }
}

@Generable
enum Rating: String, Codable, CaseIterable, Sendable {
    case skip, fine, good

    var score: Double {
        switch self {
        case .skip: 0.0
        case .fine: 0.5
        case .good: 1.0
        }
    }
}

@Generable
enum PortionBucket: String, Codable, CaseIterable, Sendable {
    case taste, normal, lots

    var multiplier: Double {
        switch self {
        case .taste:  0.4
        case .normal: 1.0
        case .lots:   1.8
        }
    }
}

@Generable
enum ValueBasis: String, Codable, CaseIterable, Sendable {
    case tierExclusivity, costDensity, preparation, preference
}

@Generable
enum ConfidenceBand: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

@Generable
enum ReconShare: String, Codable, CaseIterable, Sendable {
    case none, quarter, half, most

    var fraction: Double {
        switch self {
        case .none:    0.0
        case .quarter: 0.25
        case .half:    0.5
        case .most:    0.75
        }
    }
}

@Generable
enum Posture: String, Codable, CaseIterable, Sendable {
    case conservative, balanced, aggressive

    var uncertaintyWeight: Double {
        switch self {
        case .conservative: 0.0
        case .balanced:     0.3
        case .aggressive:   0.7
        }
    }
}

@Generable
enum FlavourAxis: String, Codable, CaseIterable, Sendable {
    case rich, fresh, spicy, sweet, savoury, fried
}

enum HypothesisVerdict: String, Codable, Sendable {
    case supported, contradicted, insufficient
}

enum CapacityVerdict: String, Codable, Sendable {
    case consistent, overestimating, underestimating, insufficient
}

enum ExclusionVerdict: String, Codable, Sendable {
    case safe, excluded, unknown
}

@Generable
enum RoundMove: String, Codable, CaseIterable, Sendable {
    case exploit, pivot
}

enum SessionOutcome: String, Codable, Sendable {
    case planning, running, stopped, declined
}

struct FlavourProfile: Codable, Hashable, Sendable {
    var axes: Set<FlavourAxis>
    var temperatureHot: Bool

    static let neutral = FlavourProfile(axes: [], temperatureHot: false)

    func similarity(to other: FlavourProfile) -> Double {
        guard !axes.isEmpty || !other.axes.isEmpty else { return 0 }
        let shared = Double(axes.intersection(other.axes).count)
        let total = Double(axes.union(other.axes).count)
        let axisPart = total > 0 ? shared / total : 0
        let tempPart = temperatureHot == other.temperatureHot ? 0.2 : 0.0
        return min(1.0, axisPart * 0.8 + tempPart)
    }

    static func prior(for category: MenuCategory) -> FlavourProfile {
        switch category {
        case .meat:      FlavourProfile(axes: [.rich, .savoury], temperatureHot: true)
        case .fried:     FlavourProfile(axes: [.fried, .savoury], temperatureHot: true)
        case .starch:    FlavourProfile(axes: [.savoury], temperatureHot: true)
        case .soup:      FlavourProfile(axes: [.savoury], temperatureHot: true)
        case .vegetable: FlavourProfile(axes: [.fresh], temperatureHot: false)
        case .raw:       FlavourProfile(axes: [.fresh], temperatureHot: false)
        case .dessert:   FlavourProfile(axes: [.sweet], temperatureHot: false)
        case .unknown:   .neutral
        }
    }
}

struct CapacityState: Sendable {
    var maxSatiety: Double
    var spent: Double

    var remaining: Double { max(0, maxSatiety - spent) }
    var fractionRemaining: Double { maxSatiety > 0 ? remaining / maxSatiety : 0 }

    var plateEstimate: Double { remaining / 3.0 }

    var isExhausted: Bool { fractionRemaining <= 0.12 }
}
