import AppIntents
import SwiftUI

struct PlanSnippet: View {
    let plan: RoundPlan
    let capacity: CapacityState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.rationale).font(.footnote).foregroundStyle(Palette.muted)
            ForEach(plan.items) { item in
                HStack {
                    Text(item.orderLabel).font(.subheadline)
                    Spacer()
                    RoundRoleBadge(isNew: item.isRecon)
                }
            }
            AskStaffNote(plan: plan)
            Text(capacity.platesLeftSentence).font(.caption).foregroundStyle(Palette.muted)
            HStack {
                Button(intent: AcceptRoundIntent()) { Text("Accept") }
                Button(intent: AdjustRoundIntent()) { Text("Adjust") }
                Button(intent: RequestStopIntent()) { Text("Stop") }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct ReceiptSnippet: View {
    let plan: RoundPlan?
    let capacity: CapacityState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eating this round").font(.subheadline.weight(.medium))
            ForEach(plan?.items ?? []) { item in
                HStack {
                    Text(item.dishName).font(.footnote)
                    Spacer()
                    Text(item.quantity == 1 ? "1 order" : "\(item.quantity) orders")
                        .font(.caption2).foregroundStyle(Palette.muted)
                }
            }
            HStack(spacing: 8) {
                CapacityRing(fraction: capacity.fractionRemaining, lineWidth: 4).frame(width: 20, height: 20)
                Text(capacity.platesLeftSentence).font(.caption).foregroundStyle(Palette.muted)
            }
            Button(intent: RequestStopIntent()) { Text("Stop") }.buttonStyle(.bordered)
        }
        .padding()
    }
}

struct StopReasonSnippet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why are you stopping?").font(.subheadline.weight(.medium))
            Text("Only \u{201C}I'm full\u{201D} tells Kenyang how much you can eat.")
                .font(.caption).foregroundStyle(Palette.muted)
            ForEach(MealEnding.allCases, id: \.self) { ending in
                Button(intent: EndMealIntent(reason: ending)) {
                    Text(ending.label).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button(intent: ResumeRoundIntent()) { Text("Keep eating") }
        }
        .buttonStyle(.bordered)
        .padding()
    }
}

struct MealOverSnippet: View {
    let headline: String
    var detail: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline).font(.subheadline.weight(.medium))
            if !detail.isEmpty {
                Text(detail).font(.footnote).foregroundStyle(Palette.muted)
            }
        }
        .padding()
    }
}

struct AskStaffNote: View {
    let plan: RoundPlan

    var body: some View {
        if plan.needsAnswers {
            Text("Ask staff about: \(plan.dishesToAskAbout.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(Palette.unknown)
        }
    }
}
