import SwiftUI

struct EatingView: View {
    let model: MealViewModel
    @ScaledMetric(relativeTo: .largeTitle) private var minutesSize: CGFloat = 44

    private var session: MealSession { model.session }

    var body: some View {
        List {
            Section { roomAndTime }
                .listRowBackground(Palette.raised)

            Section("Rate what you ate") {
                let items = session.isEating ? session.plan?.items ?? [] : []
                if items.isEmpty {
                    ContentUnavailableView("No dishes yet",
                                           systemImage: "fork.knife",
                                           description: Text("Plan a round and its dishes show up here."))
                }
                ForEach(items) { item in
                    PlateRow(session: session, item: item)
                }
            }
            .listRowBackground(Palette.raised)

            Section {
                Button("Plan the next round") { Task { await model.planNextRound() } }
                Button("End the meal") { model.askToStop() }
            }
            .listRowBackground(Palette.raised)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Round \(session.round)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var roomAndTime: some View {
        let capacity = session.visit.map(CapacityEngine.state(for:)) ?? CapacityState(maxSatiety: 0, spent: 0)
        return HStack(spacing: 24) {
            ZStack {
                CapacityRing(fraction: capacity.fractionRemaining, lineWidth: 22)
                VStack(spacing: 0) {
                    Text(capacity.plateEstimate.formatted(.number.precision(.fractionLength(1))))
                        .font(.title.weight(.semibold).monospacedDigit())
                    Text("plates left").font(.caption).foregroundStyle(Palette.muted)
                }
            }
            .frame(width: 130, height: 130)

            TimelineView(.everyMinute) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    if let minutes = session.visit?.minutesRemaining {
                        Text("\(minutes)")
                            .font(.system(size: minutesSize, weight: .semibold).monospacedDigit())
                        Text("min of seating left").font(.caption).foregroundStyle(Palette.muted)
                    } else {
                        Text("No time limit").font(.headline).foregroundStyle(Palette.muted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.ink)
        .padding(.vertical, 8)
    }
}

/// One dish: how many of its orders were eaten, its one rating for the round, and a way
/// to skip it that also takes back a plate or rating tapped by mistake.
struct PlateRow: View {
    let session: MealSession
    let item: PlannedItem

    var body: some View {
        let eaten = session.platesEaten(of: item)
        let isSkipped = session.isSkipped(item)
        VStack(alignment: .leading, spacing: 12) {
            Stepper(label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.dishName).foregroundStyle(isSkipped ? Palette.muted : Palette.ink)
                    Text(isSkipped ? "Skipped" : "\(eaten) of \(item.quantity) eaten")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                }
            }, onIncrement: eaten < item.quantity ? { session.logPlate(of: item) } : nil,
               onDecrement: eaten > 0 ? { session.removePlate(of: item) } : nil)

            Picker("Rating for \(item.dishName)", selection: ratingBinding) {
                ForEach(Rating.allCases, id: \.self) { rating in
                    Text(rating.label).tag(Optional(rating))
                }
            }
            .pickerStyle(.segmented)

            Button("Skip this dish") { session.skip(item) }
                .font(.subheadline)
                .buttonStyle(.borderless)
                .disabled(isSkipped)
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: eaten)
    }

    private var ratingBinding: Binding<Rating?> {
        Binding(get: { session.rating(of: item) },
                set: { rating in if let rating { session.rate(item, rating) } })
    }
}
