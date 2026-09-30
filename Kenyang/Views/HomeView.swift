import SwiftData
import SwiftUI

struct HomeView: View {
    let model: MealViewModel
    @AppStorage(DinerPreferences.platesKey) private var platesPerMeal = DinerPreferences.defaultPlates
    @Query(sort: \DietaryExclusion.createdAt) private var exclusions: [DietaryExclusion]
    @State private var isCheckingAvoidList = false
    @State private var isEditingAvoidList = false
    @State private var tierVenue: Restaurant?
    @State private var isProactiveOn = ProactiveTrigger.shared.isEnabled

    private var store: KenyangStore { model.session.store }
    private let menu = BuffetMenu.default

    var body: some View {
        List {
            startSection
            avoidSection
            pastMealsSection
            tierSection
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Kenyang")
        .sheet(isPresented: $isCheckingAvoidList) {
            AvoidListCheck {
                isCheckingAvoidList = false
                Task { await model.startMeal() }
            }
        }
        .sheet(isPresented: $isEditingAvoidList) {
            NavigationStack {
                ScrollView { AvoidListEditor().padding(24) }
                    .background(Palette.surface)
                    .navigationTitle("Avoid list")
                    .toolbar { Button("Done") { isEditingAvoidList = false } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $tierVenue) { venue in
            TierRecommendationView(restaurant: venue) { rank in
                tierVenue = nil
                Task { await model.startMeal(at: venue.name, pricePerHead: venue.tierPrice(rank: rank) ?? venue.pricePerHead) }
            } onOverride: {
                tierVenue = nil
            }
        }
    }

    private var startSection: some View {
        Section {
            VStack(spacing: 16) {
                ZStack {
                    CapacityRing(fraction: 1, lineWidth: 18)
                    VStack(spacing: 0) {
                        Text(platesPerMeal.formatted())
                            .font(.largeTitle.weight(.semibold).monospacedDigit())
                        Text("plates").font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                .frame(width: 140, height: 140)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Room for about \(platesPerMeal.formatted()) plates")

                Picker("Your usual meal", selection: $platesPerMeal) {
                    ForEach(DinerPreferences.plateChoices, id: \.self) { plates in
                        Text("\(plates.formatted()) plates").tag(plates)
                    }
                }
                .pickerStyle(.menu)

                VStack(spacing: 4) {
                    Text("\(menu.venueName) · \(menu.tierName)").font(.headline)
                    Text("\(menu.seatingMinutes) min · \(menu.dishes.count) dishes")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }

                Button { isCheckingAvoidList = true } label: {
                    Text("Start a meal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Palette.raised)
        }
    }

    private var avoidSection: some View {
        Section {
            if exclusions.isEmpty {
                Text("Nothing on your list").foregroundStyle(Palette.muted)
            } else {
                FlowRow(spacing: 8) {
                    ForEach(exclusions) { AvoidChip(term: $0.term) }
                }
                .padding(.vertical, 4)
            }
        } header: {
            HStack {
                Text("Avoiding")
                Spacer()
                Button("Edit") { isEditingAvoidList = true }.font(.subheadline)
            }
        }
        .listRowBackground(Palette.raised)
    }

    private var pastMealsSection: some View {
        Section("Past meals") {
            let visits = store.pastVisits()
            if visits.isEmpty {
                Text("Your meals will show up here.").foregroundStyle(Palette.muted)
            }
            ForEach(visits.prefix(10)) { visit in
                NavigationLink {
                    PastMealView(visit: visit)
                } label: {
                    PastMealRow(visit: visit)
                }
            }
        }
        .listRowBackground(Palette.raised)
    }

    @ViewBuilder
    private var tierSection: some View {
        let laddered = store.allRestaurants().filter(\.hasTierLadder)
        if !laddered.isEmpty {
            Section("Before you order") {
                ForEach(laddered) { venue in
                    Button("Which tier at \(venue.name)?") { tierVenue = venue }
                }
                Toggle("Tell me when I arrive", isOn: $isProactiveOn)
                    .onChange(of: isProactiveOn) { _, isOn in
                        if isOn {
                            Task { await ProactiveTrigger.shared.enable(store: store) }
                        } else {
                            ProactiveTrigger.shared.disable()
                        }
                    }
            }
            .listRowBackground(Palette.raised)
        }
    }
}

struct PastMealRow: View {
    let visit: Visit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(visit.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month())) · \(visit.venueName)")
                .font(.body)
            Text(summary).font(.caption).foregroundStyle(Palette.muted)
        }
    }

    private var summary: String {
        var parts = ["\(visit.roundsPlayed) round\(visit.roundsPlayed == 1 ? "" : "s")",
                     visit.endedBecause.label.lowercased()]
        if let favourite = visit.likedDishes.first { parts.append("liked \(favourite)") }
        return parts.joined(separator: " · ")
    }
}
