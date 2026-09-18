import SwiftUI

/// Screen 8 — `declineToOptimise`. There is no decision problem here worth solving.
///
/// **An agent that cannot decline is a suggestion engine.** Refusing is a first-class
/// output, so it gets a first-class screen: the same headline weight, the same evidence
/// table and the same confidence as a plan. Nothing is greyed and nothing apologises.
///
/// The primary action is **outlined, not filled** — the app is not recommending
/// anything, and a filled button would say otherwise. The capacity model still gets its
/// observations, so a declined meal is not a wasted one.
struct DeclineView: View {
    let model: SessionViewModel
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("TRIAGE GUARD · COMPUTED, NOT CHOSEN")
                        .font(.caption.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(Palette.accent)

                    Text("Nothing here needs sequencing.")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Palette.ink)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(Palette.ink)

                    Divider()
                    evidence

                    Text("A knapsack with room for everything is not a knapsack. Kenyang will keep logging what you eat, so the capacity model still learns from tonight.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                .padding(24)
            }
            actions
        }
        .background(Palette.surface)
    }

    private var evidence: some View {
        VStack(spacing: 8) {
            row("Items in your tier", "\(model.visit?.sightings.count ?? 0)")
            row("Minimum worth planning", "\(TriageGuard.minimumDishes)")
            row("Rationed or made-to-order", tierSpread)
            row("Capacity", "enough for all \(model.visit?.sightings.count ?? 0)")
        }
    }

    /// What the guard actually looked at: one price tier and no spread means there is
    /// nothing to sequence, whatever the item count.
    private var tierSpread: String {
        let ranks = Set((model.visit?.sightings ?? []).map(\.tierRank))
        return ranks.count > 1 ? "\(ranks.count) tiers" : "none"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Palette.ink)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold).monospaced()).foregroundStyle(Palette.ink)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            // Outlined, not filled. The app is not recommending anything.
            Button { model.logAsIGo() } label: {
                Text("Log as I go").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Palette.accent)
            .controlSize(.large)

            HStack {
                // The override is data, not an error. Same treatment as "keep going
                // anyway" on the stop screen — plain text, no friction, no lecture.
                Button("Plan anyway") { model.planAnyway() }
                Spacer()
                Button("Why this fired") { model.showTrace = true }
            }
            .font(.subheadline)
            .tint(Palette.accent)
        }
        .padding(24)
        .background(Palette.surface)
    }
}
