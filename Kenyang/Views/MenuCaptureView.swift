import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MenuCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.kenyangStore) private var store
    @State private var model = MenuCaptureViewModel()
    @State private var showingFileImporter = false
    @State private var photoItem: PhotosPickerItem?

    /// Called once, with what the diner confirmed. Until it fires nothing has been written.
    var onConfirm: (ConfirmedMenu) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if model.items.isEmpty { importStage } else { confirmStage }
            }
            .background(Palette.surface)
            .scrollContentBackground(.hidden)
            .navigationTitle(model.items.isEmpty ? "Capture a menu" : "Confirm the menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.tint(Palette.accent)
                }
            }
            .fileImporter(isPresented: $showingFileImporter,
                          allowedContentTypes: [.pdf, .image]) { result in
                model.accept(fileResult: result)
            }
            .onChange(of: photoItem) { _, item in
                Task { await model.accept(photo: item) }
            }
        }
    }

    private var importStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                pickers
                if model.isLoading { ProgressView().tint(Palette.accent) }
                if let captured = model.captured { summary(captured) }
                if model.isReading {
                    HStack(spacing: 8) {
                        ProgressView().tint(Palette.accent)
                        Text("Reading the menu…")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                }
                if let extracted = model.extracted { extractedRow(extracted) }
                if let progress = model.parseProgress {
                    HStack(spacing: 8) {
                        ProgressView().tint(Palette.accent)
                        Text("Reading items… \(progress.done) of \(progress.total)")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                }
                if let failure = model.failure { failureRow(failure) }
            }
            .padding()
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Read the menu once per venue.")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("A PDF is read directly. A photo is read with on-device text recognition. Read several pages one after another to cover a whole menu. Nothing is written until you confirm it.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
    }

    private var pickers: some View {
        VStack(spacing: 12) {
            Button {
                showingFileImporter = true
            } label: {
                Label("Choose a file", systemImage: "doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose a photo", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Palette.accent)
        }
    }

    private func summary(_ captured: CapturedMenu) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(captured.filename)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Text(captured.detail)
                .font(.caption)
                .foregroundStyle(Palette.muted)
            HStack(spacing: 16) {
                Button("Read the menu") { Task { await model.read() } }
                    .font(.caption.weight(.medium))
                    .tint(Palette.accent)
                    .disabled(model.isReading)
                Button("Choose something else") { model.clear() }
                    .font(.caption)
                    .tint(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func extractedRow(_ extracted: ExtractedText) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(extracted.summary)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.accent)
            Text(extracted.text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Add another page above to read more of the menu into this text.")
                .font(.caption2)
                .foregroundStyle(Palette.muted)
            HStack(spacing: 16) {
                Button("Find the items") { Task { await model.parse() } }
                    .font(.caption.weight(.medium))
                    .tint(Palette.accent)
                    .disabled(model.parseProgress != nil)
                Button("Start over") { model.clear() }
                    .font(.caption)
                    .tint(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Palette.safe.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private var confirmStage: some View {
        Form {
            Section {
                TextField("Venue", text: $model.venueName)
                LabeledContent("Price per head") {
                    TextField("Price per head", value: $model.pricePerHead, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Menu tier — Standard, Premium…", text: $model.tierName)
            } header: {
                Text("Where this menu is from")
            } footer: {
                let known = model.knownTiers(in: store)
                Text(known.isEmpty
                     ? "Which menu you import is the tier, so every item takes it. Import the base menu first — tiers rank in the order you add them."
                     : "Tiers already known here: \(known.joined(separator: " · ")). A new name is added after these.")
            }

            Section {
                ForEach($model.items) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Item name", text: $item.name)
                            .font(.footnote)
                        HStack {
                            TextField("Printed heading", text: $item.printedSection)
                                .font(.caption2)
                                .foregroundStyle(Palette.muted)
                            Spacer(minLength: 12)
                            Picker("", selection: $item.category) {
                                ForEach(MenuCategory.allCases, id: \.self) { category in
                                    Text(category.label).tag(category)
                                }
                            }
                            .labelsHidden()
                            .tint(item.category == .unknown ? Palette.unknown : Palette.accent)
                        }
                    }
                }
                .onDelete(perform: model.deleteItems)

                Button {
                    model.addItem()
                } label: {
                    Label("Add an item", systemImage: "plus")
                        .font(.footnote)
                }
                .tint(Palette.accent)
            } header: {
                HStack {
                    Text("\(model.namedItems.count) items")
                    Spacer()
                    if model.unknownCount > 0 {
                        Text("\(model.unknownCount) uncategorised")
                            .foregroundStyle(Palette.unknown)
                    }
                }
            } footer: {
                Text("Swipe to remove anything the reader invented, and correct what it misread. Nothing is written until you save.")
            }

            Section {
                Button("Save and start the meal") {
                    onConfirm(model.confirm(using: store))
                    dismiss()
                }
                .disabled(!model.canConfirm)
                .tint(Palette.accent)

                Button("Discard and start over", role: .destructive) { model.clear() }
                    .font(.footnote)
            }
        }
    }

    private func failureRow(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Palette.excluded)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Palette.excluded.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}
