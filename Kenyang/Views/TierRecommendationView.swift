import SwiftUI

/// Screen 2 — the tier recommendation, before you order.
///
/// The verdict is the headline, because it is the whole output. Evidence sits below it
/// in reading order so the decision is glanceable and the argument is available, never
/// the other way round.
///
/// **The refusal is the same screen, not an empty state.** Below three visits it says so,
/// states the threshold and names what it would need — same layout, same weight, same
/// confidence. *"I don't know yet, and here is what I'd need"* is the product working.
///
/// Never said here: "you wasted money on Premium six times." The rows report what
/// happened; they never grade the diner for it. Opinionated about the food, neutral
/// about the person.
struct TierRecommendationView: View {
    let restaurant: Restaurant
    let onAccept: (Int) -> Void
    let onOverride: () -> Void

    private var verdict: TierEngine.Verdict { TierEngine.verdict(for: restaurant) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("\(restaurant.name.uppercased()) · BEFORE YOU ORDER")
                        .font(.caption.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(Palette.accent)

                    switch verdict {
                    case .recommend(let tier, _, let habitual, let saving, let evidence):
                        confident(tier: tier, habitual: habitual, saving: saving, evidence: evidence)
                    case .insufficient(let visits, let needed, let cheapest, let missing):
                        refusal(visits: visits, needed: needed, cheapest: cheapest, missing: missing)
                    case .noLadder:
                        noLadder
                    }
                }
                .padding(24)
            }
            actions
        }
        .background(Palette.surface)
    }

    // MARK: - It can argue

    private func confident(tier: String, habitual: String, saving: Double?, evidence: [TierEngine.Evidence]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Go \(tier).")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Palette.ink)

            Text(sentence(tier: tier, habitual: habitual, saving: saving))
                .font(.body)
                .foregroundStyle(Palette.ink)

            // Money is stated once, before the meal — the one place the design allows it.
            HStack(spacing: 8) {
                AttributionBadge(isDeterministic: false)
                Text("one sentence · everything below is arithmetic")
                    .font(.caption).foregroundStyle(Palette.muted)
            }

            Divider()

            ForEach(evidence) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.headline).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    HStack(spacing: 8) {
                        Text("\(row.tool) · \(row.detail)")
                            .font(.caption.monospaced())
                            .foregroundStyle(Palette.muted)
                        AttributionBadge(isDeterministic: true)
                    }
                }
            }

            if restaurant.hasTierLadder { ladder }
        }
    }

    private func sentence(tier: String, habitual: String, saving: Double?) -> String {
        guard let saving, tier != habitual else {
            return "\(tier) carries what you actually finish. The rungs above it have not earned their place in your ratings yet."
        }
        return "\(tier), plus the cuts you actually eat, is \(rupiah(saving)) less than the \(habitual) tier you have been buying."
    }

    private var ladder: some View {
        VStack(spacing: 6) {
            ForEach(Array(restaurant.tierNames.enumerated()), id: \.offset) { index, name in
                HStack {
                    Text(name)
                        .font(.subheadline.weight(isRecommended(index) ? .semibold : .regular))
                        .foregroundStyle(isRecommended(index) ? Palette.accent : Palette.ink)
                    Spacer()
                    Text(restaurant.tierPrice(rank: index).map { "\(rupiah($0))++" } ?? "—")
                        .font(.subheadline.monospaced().weight(isRecommended(index) ? .semibold : .regular))
                        .foregroundStyle(isRecommended(index) ? Palette.accent : Palette.ink)
                }
            }
        }
        .padding(.top, 4)
    }

    private func isRecommended(_ index: Int) -> Bool {
        if case .recommend(_, let rank, _, _, _) = verdict { return rank == index }
        return false
    }

    // MARK: - It cannot argue yet

    private func refusal(visits: Int, needed: Int, cheapest: String, missing: [String]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(visits == 1 ? "One visit isn't enough to argue with."
                             : "\(visits) visits isn't enough to argue with.")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Palette.ink)

            Text("The cheapest tier that has what you came for is \(cheapest). That is the default, not a recommendation.")
                .font(.body)
                .foregroundStyle(Palette.ink)

            VStack(alignment: .leading, spacing: 8) {
                Text("INSUFFICIENT · n = \(visits), NEEDS \(needed)")
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(Palette.unknown)
                Text("After a \(ordinal(needed)) visit here it can compare what you ordered against what you finished. Until then it defaults down the ladder, because guessing high creates a cost you would try to eat your way out of.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.unknown.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT IT WOULD NEED")
                    .font(.caption.weight(.semibold)).tracking(0.6)
                    .foregroundStyle(Palette.accent)
                ForEach(missing, id: \.self) { item in
                    Text("— \(item)").font(.caption.monospaced()).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private var noLadder: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("One tier, nothing to choose.")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text("This venue prints a single menu, so there is no tier decision to make. Kenyang will plan the rounds instead.")
                .font(.body).foregroundStyle(Palette.ink)
        }
    }

    // MARK: -

    private var actions: some View {
        HStack(spacing: 12) {
            Button(acceptTitle) { onAccept(acceptRank) }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            Button(isRefusing ? "Choose" : "Override") { onOverride() }
                .buttonStyle(.bordered)
                .tint(Palette.accent)
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Palette.surface)
    }

    private var isRefusing: Bool {
        if case .recommend = verdict { return false }
        return true
    }

    private var acceptRank: Int {
        if case .recommend(_, let rank, _, _, _) = verdict { return rank }
        return 0
    }

    private var acceptTitle: String {
        switch verdict {
        case .recommend(let tier, _, _, _, _): "Accept \(tier)"
        case .insufficient(_, _, let cheapest, _): "Start with \(cheapest)"
        case .noLadder: "Start"
        }
    }

    private func rupiah(_ value: Double) -> String {
        "Rp \(value.formatted(.number.grouping(.automatic).precision(.fractionLength(0))))"
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 3: "third"
        case 4: "fourth"
        default: "\(n)th"
        }
    }
}
