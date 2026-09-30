import SwiftUI

/// The round's plan: the AI's guess, the goal it set, and the dishes with the reason for
/// each. When a guard overruled the AI, the screen says so.
struct RoundPlanView: View {
    let model: MealViewModel
    @State private var isChoosingAdjustment = false

    private var session: MealSession { model.session }
    private var plan: RoundPlan? { session.plan }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let rejection = model.coordinator.claimRejection { RejectedGuess(rejection: rejection) }
                    guess
                    if let note = session.note { NoteBox(text: note) }
                    if let entry = session.trace.lastGuard { guardBox(entry) }
                    goal
                    ForEach(plan?.items ?? []) { PlannedDishCard(model: model, item: $0) }
                    uncheckedElsewhere
                    footer
                }
                .padding(24)
            }
            actions
        }
        .background(Palette.surface)
    }

    private var header: some View {
        HStack {
            SectionLabel("Round \(session.round)\(session.trace.changedCourse ? " · new direction" : "")")
            Spacer()
            if let minutes = session.visit?.minutesRemaining {
                Text("\(minutes) min").font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)
            }
        }
    }

    @ViewBuilder
    private var guess: some View {
        if let hypothesis = session.hypothesis {
            let wasRejected = model.coordinator.claimRejection != nil
            VStack(alignment: .leading, spacing: 8) {
                Text(hypothesis.claim)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    AttributionBadge(isCalculated: wasRejected)
                    Text(wasRejected ? "planned from your numbers alone"
                                     : "\(hypothesis.basis.label) · \(hypothesis.confidence.label)")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                Text("Guessed before you taste: you'll rate it \(Text(hypothesis.expectedRating.rawValue).bold())")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    private func guardBox(_ entry: TraceEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(entry.heading, tint: Palette.ink)
            Text(entry.guardExplanation).font(.footnote).foregroundStyle(Palette.ink)
            Button("See why") { model.isShowingTrace = true }
                .font(.caption.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.muted.opacity(0.5)))
    }

    @ViewBuilder
    private var goal: some View {
        if let intent = session.intent {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("This round is for", tint: Palette.muted)
                Text(intent.rationale).font(.subheadline).foregroundStyle(Palette.ink)
                Text("\(intent.reconShare.label) · \(intent.riskPosture.label)")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.muted.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var uncheckedElsewhere: some View {
        let planned = Set(plan?.items.map(\.dishName) ?? [])
        let count = session.visit.map {
            ExclusionValidator.partition($0.sightings, exclusions: session.store.exclusions())
                .unknown.filter { !planned.contains($0.name) }.count
        } ?? 0
        if count > 0 {
            Text("\(count) other dish\(count == 1 ? "" : "es") can't be checked against your avoid list. You'll be asked about one only if a round plans it.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let plan, !plan.isEmpty, let visit = session.visit {
            let planned = (plan.totalSatietyCost / CapacityEngine.platesToSatiety).formatted(.number.precision(.fractionLength(1)))
            let left = CapacityEngine.state(for: visit).plateEstimate.formatted(.number.precision(.fractionLength(1)))
            Divider()
            Text("Fits about \(planned) plates of the \(left) you have left."
                 + (plan.excludedCount > 0 ? " \(plan.excludedCount) ruled out by your avoid list." : ""))
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if plan?.needsAnswers == true {
                Text("Ask staff about the dishes marked below, then answer, to accept this round.")
                    .font(.caption)
                    .foregroundStyle(Palette.unknown)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: model.acceptPlan) {
                Text("Accept").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(plan?.needsAnswers ?? true)

            HStack {
                Button("Adjust") { isChoosingAdjustment = true }
                    .confirmationDialog("Adjust this round", isPresented: $isChoosingAdjustment, titleVisibility: .visible) {
                        ForEach(AdjustDirection.allCases, id: \.self) { direction in
                            Button(direction.label) { Task { await model.adjust(toward: direction) } }
                        }
                    }
                Spacer()
                Button("Stop here", action: model.askToStop)
            }
            .font(.subheadline)
        }
        .padding(24)
        .background(Palette.surface)
    }
}

/// The AI's guess that wasn't shown, struck through, and why.
private struct RejectedGuess: View {
    let rejection: ClaimRejection

    private var isGuardFiring: Bool { rejection.reason == .notOnMenu }
    private var tint: Color { isGuardFiring ? Palette.unknown : Palette.muted }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(rejection.reason.label, tint: tint)
            if rejection.reason != .tooVague {
                Text(rejection.wrote).font(.footnote.italic()).strikethrough().foregroundStyle(tint)
            }
            Text(rejection.explanation).font(.footnote).foregroundStyle(isGuardFiring ? Palette.unknown : Palette.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(isGuardFiring ? 0.9 : 0.4)))
    }
}

private struct NoteBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Palette.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.unknown.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// One planned dish: why it's here, whether the avoid list clears it, and how many orders.
private struct PlannedDishCard: View {
    let model: MealViewModel
    let item: PlannedItem

    private var session: MealSession { model.session }

    var body: some View {
        let sighting = session.visit?.sighting(named: item.dishName)
        let questions = sighting.map(session.openQuestions(for:)) ?? []

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.dishName)
                    .font(.headline)
                    .foregroundStyle(questions.isEmpty ? Palette.ink : Palette.unknown)
                Spacer()
                RoundRoleBadge(isNew: item.isRecon)
                if !session.store.exclusions().isEmpty {
                    VerdictBadge(verdict: questions.isEmpty ? .safe : .unknown)
                }
            }

            HStack(spacing: 8) {
                Text(item.reason).font(.caption).foregroundStyle(Palette.muted)
                AttributionBadge(isCalculated: true)
            }

            if !questions.isEmpty {
                Text("Ingredients not printed. Ask staff before ordering.")
                    .font(.caption)
                    .foregroundStyle(Palette.unknown)
                ForEach(questions, id: \.self) { ingredient in
                    HStack(spacing: 8) {
                        Text("Contains \(ingredient)?").font(.caption).foregroundStyle(Palette.ink)
                        Spacer()
                        Button("No") { model.coordinator.answer(ingredient, contains: false, for: item.dishName) }
                        Button("Yes") { model.coordinator.answer(ingredient, contains: true, for: item.dishName) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()
            Stepper(value: Binding(get: { item.quantity }, set: { session.setOrders(for: item, to: $0) }),
                    in: 1...RoundPlanner.maxOrdersPerDish) {
                Text(item.quantity == 1 ? "1 order" : "\(item.quantity) orders")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.ink)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
    }
}
