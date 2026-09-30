import SwiftUI

struct PastMealView: View {
    let visit: Visit

    private var rounds: [(round: Int, plates: [TasteEvent])] {
        Dictionary(grouping: visit.tasteEvents, by: \.roundIndex)
            .map { (round: $0.key, plates: $0.value.sorted { $0.at < $1.at }) }
            .sorted { $0.round < $1.round }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Venue", value: visit.venueName)
                LabeledContent("Ended", value: visit.endedBecause.label)
            }
            .listRowBackground(Palette.raised)

            ForEach(rounds, id: \.round) { round in
                Section("Round \(round.round)") {
                    ForEach(dishes(in: round.plates), id: \.name) { dish in
                        HStack {
                            Text(dish.name)
                            Spacer()
                            Text(dish.rating?.rawValue ?? "not rated")
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
                .listRowBackground(Palette.raised)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .navigationTitle(visit.startedAt.formatted(date: .abbreviated, time: .omitted))
    }

    private func dishes(in plates: [TasteEvent]) -> [(name: String, rating: Rating?)] {
        plates.reduce(into: []) { dishes, plate in
            let rating = plate.isRated ? plate.rating : nil
            if let index = dishes.firstIndex(where: { $0.name == plate.dishName }) {
                dishes[index].rating = dishes[index].rating ?? rating
            } else {
                dishes.append((plate.dishName, rating))
            }
        }
    }
}
