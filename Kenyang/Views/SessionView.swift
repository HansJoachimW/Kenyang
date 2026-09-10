import SwiftUI

struct RootView: View {
    @Environment(\.kenyangStore) private var store
    @State private var model: SessionViewModel?

    var body: some View {
        Group {
            if let model {
                SessionView(model: model)
            } else {
                ProgressView().task { model = SessionViewModel(store: store) }
            }
        }
    }
}

struct SessionView: View {
    @Bindable var model: SessionViewModel
    @State private var showingTrace = false
    @State private var showingVerification = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle:              StartView(model: model)
                case .planning:          PlanningView()
                case .awaitingApproval:  PlanView(model: model)
                case .eating:            EatingView(model: model)
                case .stopped(let m):    TerminalView(title: "Stop here", message: m, model: model)
                case .declined(let m):   TerminalView(title: "Nothing to optimise", message: m, model: model)
                }
            }
            .navigationTitle("Kenyang")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Trace") { showingTrace = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Verify") { showingVerification = true }
                }
            }
            .sheet(isPresented: $showingTrace) {
                TraceView(trace: model.trace)
            }
            .sheet(isPresented: $showingVerification) {
                VerificationView()
            }
        }
    }
}

struct StartView: View {
    let model: SessionViewModel
    @State private var showingCapture = false

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
                                   pricePerHead: 250_000,
                                   seatingLimit: 90,
                                   plates: 3,
                                   spread: DemoSpread.standard)
            }
            .buttonStyle(.borderedProminent)

            Button("Capture a menu") { showingCapture = true }
                .font(.footnote)
                .tint(Palette.accent)
        }
        .padding()
        .sheet(isPresented: $showingCapture) {
            MenuCaptureView { menu in
                model.startSession(restaurantName: menu.venueName,
                                   pricePerHead: menu.pricePerHead,
                                   seatingLimit: 90,
                                   plates: 3,
                                   spread: menu.spread)
            }
        }
    }
}

struct PlanningView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Working out where the value is").font(.footnote).foregroundStyle(.secondary)
        }
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
                        Text(item.isRecon ? "recon" : "exploit")
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(item.isRecon ? .orange.opacity(0.2) : .green.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }
            if !model.unknownDishes.isEmpty {
                Section("Held back") {
                    ForEach(model.unknownDishes, id: \.name) { dish in
                        Label("\(dish.name) — ingredients unknown, ask staff",
                              systemImage: "questionmark.circle")
                            .font(.footnote)
                    }
                }
            }
            Section {
                Button("Accept") { model.acceptPlan() }
                Button("Stop here") { model.endSession() }
            }
        }
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
                Button("Plan the next round") { Task { await model.nextRound() } }
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

struct TraceView: View {
    let trace: TraceLog

    var body: some View {
        NavigationStack {
            List(trace.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.title).font(.subheadline.bold())
                        Spacer()
                        Text(entry.isDeterministic ? "computed" : "model")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(entry.isDeterministic ? .blue.opacity(0.15) : .purple.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Trace")
        }
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
