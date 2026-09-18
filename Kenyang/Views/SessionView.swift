import SwiftUI

struct RootView: View {
    @Environment(\.kenyangStore) private var store
    @State private var model: SessionViewModel?
    @AppStorage("onboarding.completed") private var onboarded = false

    var body: some View {
        Group {
            if !onboarded {
                OnboardingView { onboarded = true }
            } else if let model {
                SessionView(model: model)
            } else {
                ProgressView().task { model = SessionViewModel(store: store) }
            }
        }
    }
}

struct SessionView: View {
    @Bindable var model: SessionViewModel
    @State private var showingVerification = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle:              StartView(model: model)
                case .planning:          PlanningView(model: model)
                case .awaitingApproval:  RoundPlanView(model: model)
                case .eating:            EatingView(model: model)
                case .stopped:           StopView(model: model)
                case .declined(let m):   DeclineView(model: model, message: m)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface)
            .navigationTitle("Kenyang")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Trace") { model.showTrace = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Verify") { showingVerification = true }
                }
            }
            .sheet(isPresented: $model.showTrace) {
                TraceView(trace: model.trace)
            }
            .sheet(isPresented: $showingVerification) {
                VerificationView(trace: model.trace)
            }
        }
        // Blue Slate is the only fill the design allows, so no control may fall back to
        // the system's blue.
        .tint(Palette.accent)
    }
}

struct StartView: View {
    @Environment(\.kenyangStore) private var store
    let model: SessionViewModel
    @State private var showingCapture = false
    @State private var tierVenue: Restaurant?
    @AppStorage("onboarding.plates") private var plates: Double = SessionDefaults.plates

    /// Screen 2 belongs to ARRIVAL, before a session exists. It only has something to
    /// say at a venue that prints more than one menu.
    private var laddered: [Restaurant] {
        store.allRestaurants().filter(\.hasTierLadder)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("The goal is kenyang, not maximum.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Kenyang plans a buffet as a sequence under a shrinking budget. It proposes; you decide.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Start a demo session") {
                model.startSession(restaurantName: "Demo Buffet",
                                   pricePerHead: SessionDefaults.pricePerHead,
                                   seatingLimit: SessionDefaults.seatingMinutes,
                                   plates: plates,
                                   spread: DemoSpread.standard)
            }
            .buttonStyle(.borderedProminent)

            Button("Capture a menu") { showingCapture = true }
                .font(.footnote)
                .tint(Palette.accent)

            ForEach(laddered, id: \.name) { venue in
                Button("Before you order at \(venue.name)") { tierVenue = venue }
                    .font(.footnote)
                    .tint(Palette.accent)
            }
        }
        .padding()
        .sheet(item: $tierVenue) { venue in
            TierRecommendationView(restaurant: venue) { rank in
                tierVenue = nil
                model.startSession(restaurantName: venue.name,
                                   pricePerHead: venue.tierPrice(rank: rank) ?? venue.pricePerHead,
                                   seatingLimit: SessionDefaults.seatingMinutes,
                                   plates: plates,
                                   spread: DemoSpread.standard)
            } onOverride: {
                tierVenue = nil
            }
        }
        .sheet(isPresented: $showingCapture) {
            MenuCaptureView { menu in
                model.startSession(restaurantName: menu.venueName,
                                   pricePerHead: menu.pricePerHead,
                                   seatingLimit: SessionDefaults.seatingMinutes,
                                   plates: plates,
                                   spread: menu.spread)
            }
        }
    }
}

/// Screen 4 — the wait.
///
/// A single indeterminate bar would misrepresent this by an order of magnitude: the
/// first stage is up to ten times the second. So each stage is named, states its own
/// question and reports its own measured ceiling, completed stages collapse to one line
/// and stay, and the escape sits in the same place throughout.
///
/// Three things move and nothing else: a tool line appearing when it returns, a stage
/// collapsing to a completed line, and the next question replacing the last. Each is
/// information arriving, not decoration.
struct PlanningView: View {
    let model: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(model.progress.completed) { done in
                HStack(spacing: 8) {
                    Text(done.stage.label)
                        .font(.caption.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(Palette.muted)
                    Text("✓ \(String(format: "%.1f", done.seconds)) s")
                        .font(.caption.monospaced())
                        .foregroundStyle(Palette.muted)
                }
            }

            if let stage = model.progress.current {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Circle().fill(Palette.accent).frame(width: 7, height: 7)
                        Text(stage.label)
                            .font(.caption.weight(.semibold)).tracking(0.6)
                            .foregroundStyle(Palette.accent)
                    }
                    Text(stage.question)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Palette.ink)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.progress.toolLines, id: \.self) { line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(line.hasSuffix("insufficient") ? Palette.unknown : Palette.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }
                    }

                    Divider().padding(.top, 4)
                    HStack {
                        Text("\(model.progress.stageNumber) OF \(model.progress.stageTotal)")
                        Spacer()
                        Text(stage.ceiling)
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(Palette.muted)
                }
                .animation(.easeOut(duration: 0.24), value: model.progress.toolLines)
            }

            Spacer()

            // Same place on every stage — the diner must be able to leave at any point
            // and still get a plan.
            Button("Skip and plan from priors") { model.skipToPriors() }
                .buttonStyle(.bordered)
                .tint(Palette.accent)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.24), value: model.progress.completed.count)
    }
}

struct PlanView: View {
    let model: SessionViewModel

    var body: some View {
        List {
            if let message = model.degradedMessage {
                Section { Label(message, systemImage: "exclamationmark.triangle") }
            }
            if let hypothesis = model.hypothesis {
                Section("Hypothesis") {
                    Text(hypothesis.claim)
                    LabeledContent("Basis", value: hypothesis.basis.rawValue)
                    LabeledContent("Expects", value: hypothesis.expectedRating.rawValue)
                }
            }
            if let intent = model.intent {
                Section("This round is for") {
                    Text(intent.rationale)
                    LabeledContent("Recon share", value: intent.reconShare.rawValue)
                }
            }
            Section("Round \(model.roundIndex)") {
                ForEach(model.plan?.items ?? []) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.dishName)
                            Text("\(item.category.label) · \(item.portion.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        RoundRoleBadge(isRecon: item.isRecon)
                    }
                }
            }
            if !model.unknownDishes.isEmpty {
                Section {
                    ForEach(model.unknownDishes, id: \.name) { dish in
                        HeldBackRow(model: model, dish: dish)
                    }
                } header: {
                    Text("Held back")
                } footer: {
                    Text("Kenyang will not guess an ingredient list. Ask staff, then answer here and the dish rejoins the round.")
                }
            }
            Section {
                Button("Accept") { model.acceptPlan() }
                Button("Stop here") { model.endSession() }
            }
        }
    }
}

/// One undeterminable dish, with a yes/no per open exclusion term. The question is put
/// to the diner, never to the model — an ingredient list is a fact about a kitchen, and
/// the app has no way to observe one.
struct HeldBackRow: View {
    let model: SessionViewModel
    let dish: DishSighting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(dish.name, systemImage: "questionmark.circle").font(.subheadline)
            ForEach(model.openQuestions(for: dish), id: \.self) { term in
                HStack {
                    Text("Contains \(term)?").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("No")  { model.answer(term, contains: false, for: dish) }
                    Button("Yes") { model.answer(term, contains: true,  for: dish) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

struct EatingView: View {
    let model: SessionViewModel

    var body: some View {
        List {
            Section("Capacity") {
                ProgressView(value: model.capacity.fractionRemaining)
                Text("About \(String(format: "%.1f", model.capacity.plateEstimate)) plates left")
                    .font(.footnote).foregroundStyle(.secondary)
                if let minutes = model.minutesRemaining {
                    Text("\(minutes) minutes of seating left")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Rate what you ate") {
                ForEach(model.plan?.items ?? []) { item in
                    HStack {
                        Text(item.dishName)
                        Spacer()
                        ForEach(Rating.allCases, id: \.self) { rating in
                            Button(rating.rawValue) { model.rate(item, rating: rating) }
                                .buttonStyle(.bordered)
                                .font(.caption)
                        }
                    }
                }
            }
            Section {
                Button("Plan the next round") { model.nextRound() }
                Button("End the meal") { model.endSession() }
            }
        }
    }
}

struct TerminalView: View {
    let title: String
    let message: String
    let model: SessionViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.title2.bold())
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Done") { model.endSession() }.buttonStyle(.borderedProminent)
        }
        .padding()
    }
}


enum DemoSpread {
    static let tierNames = ["Standard", "Premium"]

    static let standard: [(name: String, category: MenuCategory, printed: String, tier: Int)] = [
        ("Wagyu Karubi", .meat, "PREMIUM MEAT", 1),
        ("Prime Rib Eye", .meat, "PREMIUM MEAT", 1),
        ("Gyu-Kaku Karubi", .meat, "STANDARD MEAT", 0),
        ("Beef Harami", .meat, "STANDARD MEAT", 0),
        ("Pork Belly Shio", .meat, "STANDARD MEAT", 0),
        ("Salmon Nigiri", .raw, "SUSHI", 0),
        ("Tuna Nigiri", .raw, "SUSHI", 0),
        ("Chicken Karaage", .fried, "APPETIZER & AGEMONO", 0),
        ("Ebi Fry", .fried, "APPETIZER & AGEMONO", 0),
        ("Garlic Rice", .starch, "RICE & NOODLE", 0),
        ("Yaki Udon", .starch, "RICE & NOODLE", 0),
        ("Miso Soup", .soup, "SOUP", 0),
        ("Kaisou Salad", .vegetable, "SALAD", 0),
        ("Grilled Corn", .vegetable, "GRILL APPETIZER", 0),
        ("Matcha Ice Cream", .dessert, "DESSERT", 0)
    ]
}
