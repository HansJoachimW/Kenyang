import Foundation

/// What the AI writes is checked before it is shown. Guided generation fixes the shape
/// of an answer, not its meaning.
enum OutputValidator {
    static let forbiddenPhrases = [
        "money's worth", "moneys worth", "get your money",
        "as much as possible", "unlimited", "maximise quantity",
        "maximize quantity", "eat more", "fill up on", "no limit",
        "stuff yourself", "worth the price by eating",
        "stuffed", "stuffing yourself", "stuff themselves",
        "keep eating", "keep going until", "until you are full", "until you're full",
        "eat as much", "as much as you can", "gorge yourself", "gorging", "pig out",
        "calorie", "for your money"
    ]

    static func isSafe(_ text: String) -> Bool {
        let lower = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return !forbiddenPhrases.contains { lower.contains($0) }
    }

    static func sanitised(_ text: String, fallback: String) -> String {
        isSafe(text) ? text : fallback
    }

    static func isSubstantive(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).count >= 4
    }
}

/// Catches a guess about a kind of food that isn't on tonight's menu.
enum GroundingGuard {
    static func missingCategory(namedIn claim: String, menu: [DishSighting]) -> MenuCategory? {
        category(namedIn: claim, menu: menu, onMenu: false)
    }

    static func menuCategory(namedIn claim: String, menu: [DishSighting]) -> MenuCategory? {
        category(namedIn: claim, menu: menu, onMenu: true)
    }

    private static func category(namedIn claim: String, menu: [DishSighting], onMenu: Bool) -> MenuCategory? {
        let present = Set(menu.map(\.category))
        let spoken = words(in: claim)
        return MenuCategory.allCases.first { category in
            category != .unknown
                && present.contains(category) == onMenu
                && !keywords(for: category).isDisjoint(with: spoken)
        }
    }

    private static func keywords(for category: MenuCategory) -> Set<String> {
        var keywords = words(in: category.label)
        keywords.insert(category.rawValue)
        keywords.remove("and")
        return keywords
    }

    private static func words(in text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 3 })
    }
}

/// Why the AI's guess was not shown, and what it wrote.
struct ClaimRejection: Sendable, Equatable {
    enum Reason: Sendable {
        case tooVague, notOnMenu, blockedWording

        var label: String {
            switch self {
            case .tooVague:       "GUESS TOO VAGUE"
            case .notOnMenu:      "NOT ON TONIGHT'S MENU"
            case .blockedWording: "HELD BACK BY THE FILTER"
            }
        }
    }

    let reason: Reason
    let wrote: String
    let explanation: String

    static func check(_ claim: String, menu: [DishSighting]) -> ClaimRejection? {
        if !OutputValidator.isSubstantive(claim) {
            return ClaimRejection(reason: .tooVague, wrote: claim,
                                  explanation: "The AI's guess was too vague to show, so this round is planned from your numbers alone.")
        }
        if let missing = GroundingGuard.missingCategory(namedIn: claim, menu: menu) {
            return ClaimRejection(reason: .notOnMenu, wrote: claim,
                                  explanation: "There is no \(missing.label.lowercased()) on tonight's menu, so Kenyang didn't show the AI's guess.")
        }
        if !OutputValidator.isSafe(claim) {
            return ClaimRejection(reason: .blockedWording, wrote: claim,
                                  explanation: "The AI's wording tripped Kenyang's filter, so it wasn't shown. The filter is strict on purpose.")
        }
        return nil
    }
}
