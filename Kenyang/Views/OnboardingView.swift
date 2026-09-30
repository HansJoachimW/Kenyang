import SwiftData
import SwiftUI

/// Shown once: what the app is for, the avoid list, and a rough size for a full meal.
struct OnboardingView: View {
    @AppStorage(DinerPreferences.platesKey) private var platesPerMeal = DinerPreferences.defaultPlates
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The goal is kenyang, not maximum.")
                        .font(.largeTitle.bold())
                    Text("Kenyang suggests what to order each round, learns what you like, and tells you when to stop. You decide.")
                        .font(.subheadline)
                }
                .foregroundStyle(Palette.ink)

                AvoidListEditor()

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("How much is a full meal for you?")
                    Picker("Plates in a full meal", selection: $platesPerMeal) {
                        ForEach(DinerPreferences.plateChoices, id: \.self) { plates in
                            Text(plates.formatted()).tag(plates)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Plates, roughly. It corrects itself as you eat.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(24)
        }
        .background(Palette.surface)
        .safeAreaInset(edge: .bottom) {
            Button(action: onDone) {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(24)
            .background(Palette.surface)
        }
        .tint(Palette.accent)
    }
}

/// Ingredients only, never a reason: allergy, diet and dislike are entered and enforced
/// the same way.
struct AvoidListEditor: View {
    @Environment(MealSession.self) private var session
    @Query(sort: \DietaryExclusion.createdAt) private var exclusions: [DietaryExclusion]
    @State private var draft = ""
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Anything you need to avoid?")
            FlowRow(spacing: 8) {
                ForEach(exclusions) { exclusion in
                    Button { session.store.removeExclusion(exclusion.term) } label: {
                        AvoidChip(term: exclusion.term, isRemovable: true)
                    }
                    .accessibilityLabel("Remove \(exclusion.term) from the avoid list")
                }
                Button { isAdding = true } label: {
                    Text("Add an ingredient")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().strokeBorder(Palette.muted, lineWidth: 1))
                }
            }
            Text("Ingredients only. Kenyang never asks why something is on this list.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .alert("Add an ingredient", isPresented: $isAdding) {
            TextField("shellfish", text: $draft)
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) { draft = "" }
            Button("Add", action: add)
        }
    }

    private func add() {
        session.store.addExclusion(draft)
        draft = ""
    }
}

/// Confirmed at the start of every meal, because nothing in the app overrides it.
struct AvoidListCheck: View {
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Still avoiding these?")
                .font(.title2.bold())
                .foregroundStyle(Palette.ink)
            AvoidListEditor()
            Spacer()
            Button(action: onConfirm) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .background(Palette.surface)
        .tint(Palette.accent)
        .presentationDetents([.medium, .large])
    }
}
