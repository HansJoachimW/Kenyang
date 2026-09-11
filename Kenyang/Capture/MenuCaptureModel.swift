import Foundation
import PDFKit
import PhotosUI
import SwiftUI

/// The capture flow's state. `CapturedMenu` in particular is an input to
/// `MenuTextExtractor`, so a Capture type declared inside a View file had the
/// dependency pointing the wrong way.

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
    var items: [MenuDraftItem] = []
    var failure: String?
    var isLoading = false
    var isReading = false
    var parseProgress: (done: Int, total: Int)?

    var venueName = ""
    var pricePerHead = SessionDefaults.pricePerHead
    var tierName = ""

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
        isReading = true
        defer { isReading = false }
        do {
            let page = try await MenuTextExtractor.extract(from: captured)
            extracted = extracted?.appending(page) ?? page
            items = []
            self.captured = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    func parse() async {
        guard let extracted else { return }
        failure = nil
        items = []
        parseProgress = (0, 1)
        defer { parseProgress = nil }
        do {
            items = try await MenuParser.parse(extracted) { [weak self] done, total in
                self?.parseProgress = (done, total)
            }
            .map(MenuDraftItem.init)
            .sorted { ($0.printedSection, $0.name) < ($1.printedSection, $1.name) }
        } catch {
            failure = error.localizedDescription
        }
    }

    var unknownCount: Int { items.filter { $0.category == .unknown }.count }

    func addItem() {
        items.append(MenuDraftItem(printedSection: items.last?.printedSection ?? ""))
    }

    func deleteItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    var namedItems: [MenuDraftItem] { items.filter(\.isNamed) }

    var canConfirm: Bool {
        !venueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !tierName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !namedItems.isEmpty
    }

    /// The single write path. Everything before this is a draft the diner can still change.
    func confirm(using store: KenyangStore) -> ConfirmedMenu {
        let venue = venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        let tier = tierName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rank = store.tierRank(of: tier, venue: venue, pricePerHead: pricePerHead)
        CaptureLog.rule("CONFIRMED — \(namedItems.count) item(s) at \(venue), tier \"\(tier)\" (rank \(rank))")
        return ConfirmedMenu(
            venueName: venue,
            pricePerHead: pricePerHead,
            tierName: tier,
            spread: namedItems.map {
                (name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                 category: $0.category,
                 printed: $0.printedSection,
                 tier: rank)
            }
        )
    }

    /// The venue's ladder so far, so the rank this import will take is visible before it is taken.
    func knownTiers(in store: KenyangStore) -> [String] {
        let venue = venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !venue.isEmpty else { return [] }
        return store.restaurant(named: venue)?.tierNames ?? []
    }

    func clear() {
        captured = nil
        extracted = nil
        items = []
        failure = nil
    }
}
