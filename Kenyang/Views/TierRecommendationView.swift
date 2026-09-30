import SwiftUI

/// Which tier to buy, before ordering. Below three visits it refuses in the same layout,
/// and says what it would need.
struct TierRecommendationView: View {
    let restaurant: Restaurant
    let onAccept: (Int) -> Void
    let onOverride: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40

    private var verdict: TierEngine.Verdict { TierEngine.verdict(for: restaurant) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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

    private func confident(tier: String, habitual: String, saving: Double?, evidence: [TierEngine.Evidence]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Go \(tier).")
                .font(.system(size: heroSize, weight: .bold))
                .foregroundStyle(Palette.ink)

            Text(sentence(tier: tier, habitual: habitual, saving: saving))
                .font(.body)
                .foregroundStyle(Palette.ink)

            HStack(spacing: 8) {
                AttributionBadge(isCalculated: false)
                Text("the sentence above · everything below is calculated")
                    .font(.caption).foregroundStyle(Palette.muted)
            }

            Divider()

            ForEach(evidence) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.headline).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    HStack(spacing: 8) {
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                        AttributionBadge(isCalculated: true)
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
        VStack(spacing: 4) {
            ForEach(Array(restaurant.tierNames.enumerated()), id: \.offset) { index, name in
                HStack {
                    Text(name)
                        .font(.subheadline.weight(isRecommended(index) ? .semibold : .regular))
                        .foregroundStyle(isRecommended(index) ? Palette.accent : Palette.ink)
                    Spacer()
                    Text(restaurant.tierPrice(rank: index).map { "\(rupiah($0))++" } ?? "n/a")
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

    private func refusal(visits: Int, needed: Int, cheapest: String, missing: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(visits == 1 ? "One visit isn't enough to argue with."
                             : "\(visits) visits isn't enough to argue with.")
                .font(.system(size: heroSize, weight: .bold))
                .foregroundStyle(Palette.ink)

            Text("The cheapest tier that has what you came for is \(cheapest). That is the default, not a recommendation.")
                .font(.body)
                .foregroundStyle(Palette.ink)

            VStack(alignment: .leading, spacing: 8) {
                Text("NOT ENOUGH VISITS YET · \(visits) OF \(needed)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.unknown)
                Text("After a \(ordinal(needed)) visit here it can compare what you ordered with what you finished. Until then it suggests the cheaper tier, because paying for more than you'll eat makes you want to eat more.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.unknown.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text("WHAT IT WOULD NEED")
                    .font(.caption.weight(.semibold)).tracking(0.6)
                    .foregroundStyle(Palette.accent)
                ForEach(missing, id: \.self) { item in
                    Text("· \(item)").font(.caption).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private var noLadder: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("One tier, nothing to choose.")
                .font(.system(size: heroSize, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text("This place has one menu, so there's no tier to choose. Kenyang will plan your rounds instead.")
                .font(.body).foregroundStyle(Palette.ink)
        }
    }

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
