import Foundation

enum SectionClassifier {
    private static let rules: [(terms: [String], category: MenuCategory)] = [
        (["dessert", "ice cream", "mochi", "pudding", "sweet", "fruit"], .dessert),
        (["sushi", "sashimi", "nigiri", "maki", "hoe", "raw"], .raw),
        (["rice", "noodle", "udon", "ramen", "soba", "bibimbap", "naengmyeon"], .starch),
        (["soup", "broth", "jjigae", "nabe", "stew"], .soup),
        (["salad", "vegetable", "veggie", "banchan", "namul", "greens"], .vegetable),
        (["agemono", "fried", "karaage", "tempura", "twigim", "gorengan"], .fried),
        (["meat", "beef", "pork", "chicken", "karubi", "wagyu", "yakiniku", "bbq", "grill"], .meat)
    ]

    static func category(forSection section: String) -> MenuCategory? {
        let text = section.lowercased()
        guard !text.isEmpty else { return nil }
        for rule in rules where rule.terms.contains(where: text.contains) {
            return rule.category
        }
        return nil
    }

    static func isLikelyHeading(_ item: MenuItemDraft) -> Bool {
        let name = normalised(item.name)
        guard !name.isEmpty else { return true }
        if name.count < 3 { return true }
        if name == normalised(item.printedSection) { return true }
        return rules.contains { $0.terms.contains(name) }
    }

    struct Refinement: Sendable {
        var kept: [MenuItemDraft] = []
        var droppedAsHeading = 0
        var raw = 0

        var looksLikeContentsPage: Bool {
            raw >= 3 && Double(droppedAsHeading) / Double(raw) >= 0.6
        }
    }

    static func refined(_ items: [MenuItemDraft]) -> Refinement {
        var result = Refinement(raw: items.count)
        for item in items {
            guard !isLikelyHeading(item) else {
                result.droppedAsHeading += 1
                CaptureLog.line("  dropped as heading: \"\(item.name)\" ‹\(item.printedSection)›")
                continue
            }
            var refined = item
            if let fromSection = category(forSection: item.printedSection),
               fromSection != item.category {
                CaptureLog.line("  recategorised: \"\(item.name)\" \(item.category.rawValue) → \(fromSection.rawValue) (heading ‹\(item.printedSection)›)")
                refined.category = fromSection
            }
            result.kept.append(refined)
        }
        return result
    }

    static func refine(_ items: [MenuItemDraft]) -> [MenuItemDraft] {
        var kept: [MenuItemDraft] = []
        for item in items {
            guard !isLikelyHeading(item) else {
                CaptureLog.line("  dropped as heading: \"\(item.name)\" ‹\(item.printedSection)›")
                continue
            }
            var refined = item
            if let fromSection = category(forSection: item.printedSection),
               fromSection != item.category {
                CaptureLog.line("  recategorised: \"\(item.name)\" \(item.category.rawValue) → \(fromSection.rawValue) (heading ‹\(item.printedSection)›)")
                refined.category = fromSection
            }
            kept.append(refined)
        }
        return kept
    }

    private static func normalised(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
