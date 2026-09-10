import Foundation

/// One reviewable row in the confirmation step.
///
/// `MenuItemDraft` is the model's own output and identifies itself by its name,
/// which cannot survive a rename or two items printed with the same name. This
/// carries a stable identity instead, so the list can be edited before it is written.
struct MenuDraftItem: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var printedSection: String
    var category: MenuCategory

    init(name: String = "", printedSection: String = "", category: MenuCategory = .unknown) {
        self.name = name
        self.printedSection = printedSection
        self.category = category
    }

    init(_ draft: MenuItemDraft) {
        self.init(name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                  printedSection: draft.printedSection.trimmingCharacters(in: .whitespacesAndNewlines),
                  category: draft.category)
    }

    var isNamed: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// What the confirmation step hands back. Nothing reaches the store until this exists.
struct ConfirmedMenu: Sendable {
    var venueName: String
    var pricePerHead: Double
    var tierName: String
    var spread: [(name: String, category: MenuCategory, printed: String, tier: Int)]
}
