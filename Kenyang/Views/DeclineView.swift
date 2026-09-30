import SwiftUI

/// Declining to plan is a result in its own right, shown with the same weight as a plan.
struct DeclineView: View {
    let model: MealViewModel
    let message: String
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 38

    private var menu: [DishSighting] { model.session.visit?.sightings ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel("Worked out from the menu, not the AI")
                    Text("No plan needed here.")
                        .font(.system(size: headlineSize, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(message).foregroundStyle(Palette.ink)
                    Divider()
                    VStack(spacing: 8) {
                        LabeledContent("Dishes on your menu", value: "\(menu.count)")
                        LabeledContent("Worth planning from", value: "\(TriageGuard.minimumDishes)")
                        LabeledContent("Price tiers", value: "\(Set(menu.map(\.tierRank)).count)")
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    Text("When there's room for everything, there's nothing to choose between. Log what you eat and Kenyang still learns how much you can eat.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                .padding(24)
            }
            actions
        }
        .background(Palette.surface)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: model.logAsIGo) {
                Text("Log as I go").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            HStack {
                Button("Plan anyway") { Task { await model.planAnyway() } }
                Spacer()
                Button("See why") { model.isShowingTrace = true }
            }
            .font(.subheadline)
        }
        .padding(24)
        .background(Palette.surface)
    }
}
