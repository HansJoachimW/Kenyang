import Foundation

/// Safe, excluded or unknown per dish. Unknown is never treated as safe: a dish stays
/// unknown until its printed name, its ingredient list, or the diner (after asking
/// staff) settles every term on the avoid list.
enum ExclusionValidator {
    struct Partition {
        var safe: [DishSighting] = []
        var excluded: [DishSighting] = []
        var unknown: [DishSighting] = []
    }

    static func verdict(for sighting: DishSighting, avoiding exclusions: [String]) -> ExclusionVerdict {
        let terms = normalised(exclusions)
        guard !terms.isEmpty else { return .safe }

        let name = sighting.name.lowercased()
        let ingredients = sighting.ingredients.map { $0.lowercased() }
        let cleared = Set(normalised(sighting.clearedTerms))

        var isSettled = true
        for term in terms {
            if name.contains(term) || ingredients.contains(where: { $0.contains(term) }) { return .excluded }
            if !sighting.ingredientsKnown && !cleared.contains(term) { isSettled = false }
        }
        return isSettled ? .safe : .unknown
    }

    static func openQuestions(for sighting: DishSighting, avoiding exclusions: [String]) -> [String] {
        guard verdict(for: sighting, avoiding: exclusions) == .unknown else { return [] }
        let cleared = Set(normalised(sighting.clearedTerms))
        let name = sighting.name.lowercased()
        return normalised(exclusions).filter { !cleared.contains($0) && !name.contains($0) }
    }

    static func partition(_ sightings: [DishSighting], exclusions: [String]) -> Partition {
        sightings.reduce(into: Partition()) { partition, sighting in
            switch verdict(for: sighting, avoiding: exclusions) {
            case .safe:     partition.safe.append(sighting)
            case .excluded: partition.excluded.append(sighting)
            case .unknown:  partition.unknown.append(sighting)
            }
        }
    }

    private static func normalised(_ terms: [String]) -> [String] {
        terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
    }
}
