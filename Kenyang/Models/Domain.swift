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

    var label: String {
        switch self {
        case .tierExclusivity: "only on this tier"
        case .costDensity:     "most value for the room it takes"
        case .preparation:     "how it's made"
        case .preference:      "what you've liked"
        }
    }
}

@Generable
enum ConfidenceBand: String, Codable, CaseIterable, Sendable {
    case low, medium, high

    var label: String {
        switch self {
        case .low:    "not sure yet"
        case .medium: "fairly sure"
        case .high:   "sure"
        }
    }
}

/// How much of a round goes to dishes the diner hasn't tried.
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

    var label: String {
        switch self {
        case .none:    "only dishes you've tried"
        case .quarter: "mostly tried, one new"
        case .half:    "half new dishes"
        case .most:    "mostly new dishes"
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

    var label: String {
        switch self {
        case .conservative: "playing it safe"
        case .balanced:     "balanced"
        case .aggressive:   "taking a chance"
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

    var label: String {
        switch self {
        case .exploit: "stay with the guess"
        case .pivot:   "change course"
        }
    }
}

/// Why the meal ended. Only a `fullness` ending measures capacity; the rest say
/// "at least this much".
@Generable
enum MealEnding: String, Codable, CaseIterable, Sendable {
    case fullness, clock, closing, left, unknown

    static let offered: [MealEnding] = [.fullness, .clock, .closing, .left]

    var measuresCapacity: Bool { self == .fullness }

    var label: String {
        switch self {
        case .fullness: "I'm full"
        case .clock:    "Seating time ran out"
        case .closing:  "The place is closing"
        case .left:     "The group left"
        case .unknown:  "Some other reason"
        }
    }
}

@Generable
enum Fullness: String, Codable, CaseIterable, Sendable {
    case empty, light, comfortable, full, stuffed

    var level: Int {
        switch self {
        case .empty:       1
        case .light:       2
        case .comfortable: 3
        case .full:        4
        case .stuffed:     5
        }
    }
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
        let temperaturePart = temperatureHot == other.temperatureHot ? 0.2 : 0.0
        return min(1.0, axisPart * 0.8 + temperaturePart)
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
    static let exhaustionThreshold = 0.12

    var maxSatiety: Double
    var spent: Double
    /// The prior before any fullness correction, so the capacity check tests the prior
    /// and not the figure derived from the reading it is checking.
    var declaredMax: Double

    init(maxSatiety: Double, spent: Double, declaredMax: Double? = nil) {
        self.maxSatiety = maxSatiety
        self.spent = spent
        self.declaredMax = declaredMax ?? maxSatiety
    }

    var remaining: Double { max(0, maxSatiety - spent) }
    var fractionRemaining: Double { maxSatiety > 0 ? remaining / maxSatiety : 0 }
    var plateEstimate: Double { remaining / CapacityEngine.platesToSatiety }
    var isExhausted: Bool { fractionRemaining <= Self.exhaustionThreshold }

    var platesLeftSentence: String {
        plateEstimate < 0.75
            ? "About half a plate left."
            : "About \(plateEstimate.formatted(.number.precision(.fractionLength(1)))) plates left."
    }
}
