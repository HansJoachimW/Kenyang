import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

struct CapturedMenu: Sendable {
    enum Kind: String, Sendable {
        case pdf = "PDF"
        case image = "Image"
    }

    var kind: Kind
    var filename: String
    var data: Data
    var pageCount: Int?

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    var detail: String {
        var parts = [kind.rawValue, sizeDescription]
        if let pageCount { parts.insert("\(pageCount) page\(pageCount == 1 ? "" : "s")", at: 1) }
        return parts.joined(separator: " · ")
    }
}

@MainActor
@Observable
final class MenuCaptureViewModel {
    var captured: CapturedMenu?
    var extracted: ExtractedText?
    var drafts: [MenuItemDraft] = []
    var failure: String?
    var isLoading = false
    var isReading = false
    var parseProgress: (done: Int, total: Int)?

    func accept(fileResult result: Result<URL, Error>) {
        failure = nil
        switch result {
        case .failure(let error):
            failure = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let isPDF = url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
                captured = CapturedMenu(kind: isPDF ? .pdf : .image,
                                        filename: url.lastPathComponent,
                                        data: data,
                                        pageCount: isPDF ? PDFDocument(data: data)?.pageCount : nil)
            } catch {
                failure = "Could not read \(url.lastPathComponent). \(error.localizedDescription)"
            }
        }
    }

    func accept(photo item: PhotosPickerItem?) async {
        guard let item else { return }
        failure = nil
        isLoading = true
        defer { isLoading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                failure = "That photo could not be loaded."
                return
            }
            captured = CapturedMenu(kind: .image, filename: "Photo", data: data, pageCount: nil)
        } catch {
            failure = error.localizedDescription
        }
    }

    func read() async {
        guard let captured else { return }
        failure = nil
        extracted = nil
        isReading = true
        defer { isReading = false }
        do {
            extracted = try await MenuTextExtractor.extract(from: captured)
        } catch {
            failure = error.localizedDescription
        }
    }

    func parse() async {
        guard let extracted else { return }
        failure = nil
        drafts = []
        parseProgress = (0, 1)
        defer { parseProgress = nil }
        do {
            drafts = try await MenuParser.parse(extracted) { [weak self] done, total in
                self?.parseProgress = (done, total)
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    var draftsBySection: [(section: String, items: [MenuItemDraft])] {
        Dictionary(grouping: drafts) { $0.printedSection.isEmpty ? "No heading" : $0.printedSection }
            .map { (section: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.section < $1.section }
    }

    var unknownCount: Int { drafts.filter { $0.category == .unknown }.count }

    func clear() {
        captured = nil
        extracted = nil
        drafts = []
        failure = nil
    }
}

struct MenuCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = MenuCaptureViewModel()
    @State private var showingFileImporter = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
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
                        if !model.drafts.isEmpty { draftList }
                        if let failure = model.failure { failureRow(failure) }
                    }
                .padding()
            }
            .background(Palette.surface)
            .scrollContentBackground(.hidden)
            .navigationTitle("Capture a menu")
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

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Read the menu once per venue.")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("A PDF is read directly. A photo is read with on-device text recognition. Nothing is written until you confirm it.")
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
            Button("Find the items") { Task { await model.parse() } }
                .font(.caption.weight(.medium))
                .tint(Palette.accent)
                .disabled(model.parseProgress != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Palette.safe.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private var draftList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(model.drafts.count) items")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Spacer()
                if model.unknownCount > 0 {
                    Text("\(model.unknownCount) uncategorised")
                        .font(.caption)
                        .foregroundStyle(Palette.unknown)
                }
            }

            Text("Check these before anything is saved. Headings are shown exactly as printed.")
                .font(.caption)
                .foregroundStyle(Palette.muted)

            ForEach(model.draftsBySection, id: \.section) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.section)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.accent)
                    ForEach(group.items) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.name)
                                .font(.footnote)
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 12)
                            Text(item.category.label)
                                .font(.caption2)
                                .foregroundStyle(item.category == .unknown ? Palette.unknown : Palette.muted)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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
