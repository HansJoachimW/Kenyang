import SwiftUI

/// Screen 4 — the round plan. The agentic core.
///
/// Four things the design binds, and each is the difference between an agent and a
/// suggestion engine:
///
/// **Every item carries its reason.** One line under each dish, badged `COMPUTED`,
/// naming the arithmetic that put it there. The model contributes the claim and the
/// objective; beam search does the ordering, and the screen says which is which.
///
/// **The pre-registered expectation is on screen.** *"Committed before tasting: expects
/// good."* Stating it before the plate arrives is what makes the diner's rating a
/// falsification rather than feedback.
///
/// **The pivot shows its author.** `exploit` is chosen ~92% of the time, so the
/// branching a diner sees is produced by the guards, not by the model choosing well.
/// A guard that fires gets a bordered block naming itself. Concealing that would be the
/// dishonest choice and the less impressive one.
///
/// **Stop is always plain text**, beside Adjust, at the same weight, on every round —
/// never a warning, never a nudge, never absent.
struct RoundPlanView: View {
    let model: SessionViewModel

    private var plan: RoundPlan? { model.plan }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let rejection = model.claimRejection { struck(rejection) }
                    hypothesis
                    if let message = model.degradedMessage { degraded(message) }
                    if let guardEntry = model.lastGuardThisRound { guardBlock(guardEntry) }
                    objective
                    items
                    footer
                }
                .padding(24)
            }
            actions
        }
        .background(Palette.surface)
    }

    // MARK: -

    private var header: some View {
        HStack {
            Text("ROUND \(model.roundIndex)\(model.didPivot ? " · PIVOT" : "")")
                .font(.caption.weight(.semibold)).tracking(0.6)
                .foregroundStyle(Palette.accent)
            Spacer()
            if let minutes = model.minutesRemaining {
                Text("\(minutes) min").font(.caption.monospaced()).foregroundStyle(Palette.muted)
            }
            CapacityDots(fraction: model.capacity.fractionRemaining)
        }
    }

    @ViewBuilder
    private var hypothesis: some View {
        if let hypothesis = model.hypothesis {
            VStack(alignment: .leading, spacing: 10) {
                Text(hypothesis.claim)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    AttributionBadge(isDeterministic: model.claimRejection != nil)
                    Text(model.claimRejection == nil
                         ? "basis: \(hypothesis.basis.rawValue) · confidence \(hypothesis.confidence.rawValue)"
                         : "planned on the arithmetic alone")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                // The claim is falsifiable by the diner within three minutes, and only
                // because the expectation is stated before the plate arrives.
                (Text("Committed before tasting: expects ")
                    + Text(hypothesis.expectedRating.rawValue).bold())
                    .font(.footnote)
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    /// The stress test: three degenerate outputs, three treatments.
    ///
    /// A thin claim is demoted quietly in grey. A hallucination is a guardrail firing,
    /// so it is amber and the sentence is struck through. A false positive from the
    /// blunt stance filter is grey — the filter is coarse, and saying so is more honest
    /// than hiding it.
    private func struck(_ rejection: ClaimRejection) -> some View {
        let isGuard = rejection.layer == .grounding
        let tint = isGuard ? Palette.unknown : Palette.muted
        return VStack(alignment: .leading, spacing: 6) {
            Text(rejection.layer.rawValue)
                .font(.caption.weight(.semibold)).tracking(0.6)
                .foregroundStyle(tint)
            if rejection.layer != .thin {
                Text(rejection.wrote)
                    .font(.footnote.italic())
                    .strikethrough()
                    .foregroundStyle(tint)
            }
            Text(rejection.explanation)
                .font(.footnote)
                .foregroundStyle(isGuard ? Palette.unknown : Palette.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tint.opacity(isGuard ? 0.9 : 0.4), lineWidth: 1)
        }
    }

    private func degraded(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Palette.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.unknown.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func guardBlock(_ entry: TraceEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title.uppercased() + " FIRED")
                .font(.caption.weight(.semibold)).tracking(0.6)
                .foregroundStyle(Palette.ink)
            Text(entry.detail)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
            Button("SEE IT IN THE TRACE →") { model.showTrace = true }
                .font(.caption.weight(.semibold))
                .tint(Palette.accent)
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.muted.opacity(0.5), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var objective: some View {
        if let intent = model.intent {
            VStack(alignment: .leading, spacing: 6) {
                Text("THIS ROUND IS FOR")
                    .font(.caption.weight(.semibold)).tracking(0.6)
                    .foregroundStyle(Palette.muted)
                Text(intent.rationale).font(.subheadline).foregroundStyle(Palette.ink)
                Text("recon share: \(intent.reconShare.rawValue) · posture: \(intent.riskPosture.rawValue)")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.muted.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var items: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(plan?.items ?? []) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.dishName).font(.headline).foregroundStyle(Palette.ink)
                        if item.portion == .taste {
                            Text("taste").font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        RoundRoleBadge(isRecon: item.isRecon)
                    }
                    HStack(spacing: 8) {
                        Text(item.reason).font(.caption).foregroundStyle(Palette.muted)
                        AttributionBadge(isDeterministic: true)
                    }
                }
            }

            // Held back, not hidden. Amber, because amber only ever means uncertainty.
            ForEach(model.unknownDishes, id: \.name) { dish in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(dish.name).font(.headline).foregroundStyle(Palette.unknown)
                        Spacer()
                        VerdictBadge(verdict: .unknown)
                    }
                    Text("Ingredients not printed. Held back, not hidden.")
                        .font(.caption).foregroundStyle(Palette.unknown)
                    ForEach(model.openQuestions(for: dish), id: \.self) { term in
                        HStack(spacing: 8) {
                            Text("Contains \(term)?").font(.caption).foregroundStyle(Palette.muted)
                            Spacer()
                            Button("No")  { model.answer(term, contains: false, for: dish) }
                            Button("Yes") { model.answer(term, contains: true,  for: dish) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(Palette.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let plan, !plan.isEmpty {
            Divider()
            Text(fitLine(plan))
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    private func fitLine(_ plan: RoundPlan) -> String {
        let planned = plan.totalSatietyCost / CapacityEngine.platesToSatiety
        let left = model.capacity.plateEstimate
        var line = "Fits about \(String(format: "%.1f", planned)) plates of the \(String(format: "%.1f", left)) you have left."
        if plan.excludedCount > 0 {
            line += " \(plan.excludedCount) ruled out by your avoid list."
        }
        return line
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button { model.acceptPlan() } label: {
                Text("Accept").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .controlSize(.large)
            HStack {
                Button("Adjust") { model.adjustRound() }
                Spacer()
                // Never a warning, never a nudge, never absent.
                Button("Stop here") { model.endSession() }
            }
            .font(.subheadline)
            .tint(Palette.accent)
        }
        .padding(24)
        .background(Palette.surface)
    }
}

/// Capacity as filled dots. The ring is the glyph everywhere else; in a header row this
/// is the same information at the size a glance affords.
struct CapacityDots: View {
    let fraction: Double
    private let total = 3

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(Double(index) < fraction * Double(total) ? Palette.accent : Palette.muted.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Capacity remaining")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
