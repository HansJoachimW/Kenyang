import Foundation
import PDFKit
import UIKit
import Vision

struct ExtractedText: Sendable {
    enum Source: String, Sendable {
        case pdfTextLayer = "PDF text layer"
        case visionOCR = "on-device text recognition"
        case mixed = "both PDF text and recognition"
    }

    var text: String
    var source: Source
    var pages: Int

    var characterCount: Int { text.count }

    var summary: String {
        "\(characterCount) characters from \(pages) page\(pages == 1 ? "" : "s") · \(source.rawValue)"
    }

    /// One poster is rarely one photo. Successive imports accumulate into a single
    /// body of text so the parse sees the whole menu at once.
    func appending(_ other: ExtractedText) -> ExtractedText {
        ExtractedText(text: text + "\n" + other.text,
                      source: source == other.source ? source : .mixed,
                      pages: pages + other.pages)
    }
}

enum MenuTextExtractor {
    static let minimumUsefulCharacters = 200

    enum Failure: LocalizedError {
        case unreadablePDF
        case unreadableImage
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .unreadablePDF:
                "That PDF could not be opened."
            case .unreadableImage:
                "That image could not be read."
            case .noTextFound:
                "No text was found. Try a sharper photo, or the venue's menu PDF if it has one."
            }
        }
    }

    static func extract(from captured: CapturedMenu) async throws -> ExtractedText {
        CaptureLog.rule("TEXT EXTRACTION — \(captured.filename) (\(captured.detail))")
        do {
            let result: ExtractedText = switch captured.kind {
            case .pdf:   try await fromPDF(captured.data)
            case .image: try await fromImage(captured.data)
            }
            CaptureLog.line("source: \(result.source.rawValue)")
            CaptureLog.line("\(result.characterCount) characters over \(result.pages) page(s)")
            CaptureLog.line("")
            CaptureLog.numbered(result.text)
            CaptureLog.line("")
            return result
        } catch {
            CaptureLog.line("FAILED — \(error.localizedDescription)")
            throw error
        }
    }

    private static func fromPDF(_ data: Data) async throws -> ExtractedText {
        guard let document = PDFDocument(data: data) else { throw Failure.unreadablePDF }

        let layer = (document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if layer.count >= minimumUsefulCharacters {
            return ExtractedText(text: layer, source: .pdfTextLayer, pages: document.pageCount)
        }

        var recognised: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let image = render(page) else { continue }
            let read = try await recognise(image)
            if !read.text.isEmpty { recognised.append(read.text) }
        }

        let joined = recognised.joined(separator: "\n")
        guard !joined.isEmpty else { throw Failure.noTextFound }
        return ExtractedText(text: joined, source: .visionOCR, pages: document.pageCount)
    }

    private static func fromImage(_ data: Data) async throws -> ExtractedText {
        guard let uiImage = UIImage(data: data), let image = uiImage.cgImage else {
            throw Failure.unreadableImage
        }
        if let complaint = CaptureQualityGuard.inspect(image) {
            CaptureLog.line("REFUSED before recognition — \(complaint)")
            throw complaint
        }
        let read = try await recognise(image, orientation: uiImage.cgOrientation)
        guard !read.text.isEmpty else { throw Failure.noTextFound }
        if let complaint = CaptureQualityGuard.inspect(text: read.text, confidence: read.confidence) {
            CaptureLog.line("REFUSED after recognition — \(complaint)")
            throw complaint
        }
        return ExtractedText(text: read.text, source: .visionOCR, pages: 1)
    }

    static let preferredLanguageCodes: Set<String> = ["en", "ja", "ko", "zh"]

    /// Vision's default is 1/32 of image height. An item name on a menu poster is ~18 px
    /// on a 3,000 px page — under the default, so the names die before recognition.
    static let minimumTextHeightFraction: Float = 0.005

    struct Reading {
        var text: String
        /// Mean of Vision's own top-candidate confidence across every recognised line.
        /// `nil` when nothing was recognised at all.
        var confidence: Float?
    }

    private static func recognise(_ image: CGImage,
                                  orientation: CGImagePropertyOrientation = .up) async throws -> Reading {
        // RecognizeDocumentsRequest, not RecognizeTextRequest. A menu poster is a
        // structured document, and this returns paragraphs — text already grouped by
        // the block it was printed in — instead of one flat transcript that loses
        // which heading an item sat under. It reads barcodes in the same pass.
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.minimumTextHeightFraction = minimumTextHeightFraction

        let usable = request.supportedRecognitionLanguages.filter {
            guard let code = $0.languageCode?.identifier else { return false }
            return preferredLanguageCodes.contains(code)
        }
        if !usable.isEmpty {
            request.textRecognitionOptions.recognitionLanguages = usable
            CaptureLog.line("OCR languages: \(usable.map(\.maximalIdentifier).joined(separator: ", "))")
        } else {
            CaptureLog.line("OCR languages: none of en/ja/ko/zh supported — using the model default")
        }

        let pixels = image.width * image.height
        CaptureLog.line("image: \(image.width)×\(image.height) px (\(String(format: "%.1f", Double(pixels) / 1_000_000)) MP)")

        var lines: [String] = []
        var confidences: [Float] = []
        // A paragraph is one printed block, so keeping paragraph boundaries is what
        // preserves "these items sit under this heading" through the flattening.
        func collect(_ observations: [DocumentObservation]) -> Int {
            var added = 0
            for document in observations {
                confidences += document.document.text.lines.compactMap {
                    $0.topCandidates(1).first?.confidence
                }
                let blocks = document.document.paragraphs.map(\.transcript)
                for block in blocks.isEmpty ? [document.document.text.transcript] : blocks {
                    let text = block.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    // Tiles overlap, so a name straddling a boundary is read twice — once
                    // whole, once truncated ("Tuna Nigiri" and "na Nigiri"). Exact-match
                    // dedupe keeps both and the parser then invents an item from the
                    // fragment, so fold one into the other and keep the longer reading.
                    if lines.contains(where: { $0.localizedCaseInsensitiveContains(text) }) { continue }
                    if let stale = lines.firstIndex(where: { text.localizedCaseInsensitiveContains($0) }) {
                        lines[stale] = text
                        continue
                    }
                    lines.append(text)
                    added += 1
                }
            }
            return added
        }

        // Tiles first, in reading order, so the flattened string keeps roughly the
        // order of the page. The whole-image pass runs last and only contributes
        // text no tile caught — in practice the large headings.
        if pixels >= tilingThreshold {
            for row in 0..<tileGrid {
                for column in 0..<tileGrid {
                    var tiled = request
                    tiled.regionOfInterest = tile(row: row, column: column)
                    let found = collect(try await tiled.perform(on: image, orientation: orientation))
                    CaptureLog.line("  tile r\(row)c\(column): +\(found) line(s)")
                }
            }
        } else {
            CaptureLog.line("  under \(tilingThreshold / 1_000_000) MP — not tiled. Small item names may be unrecoverable at this size.")
        }

        let whole = collect(try await request.perform(on: image, orientation: orientation))
        CaptureLog.line("  whole image: +\(whole) line(s) not seen in any tile")

        let mean = confidences.isEmpty ? nil : confidences.reduce(0, +) / Float(confidences.count)
        if let mean {
            CaptureLog.line("  confidence: \(Int(mean * 100))% mean over \(confidences.count) line(s)")
        }
        return Reading(text: lines.joined(separator: "\n"), confidence: mean)
    }

    /// Vision downsamples a large image before recognition, so an item name that is
    /// legible at native size dies before it is ever read. Recognising a grid of
    /// regions puts each pass back at native scale; the overlap catches names that
    /// straddle a boundary. This is cropping, not image processing — see §3g.1 step 3.
    static let tileGrid = 3
    static let tileOverlap = 0.08
    static let tilingThreshold = 1_000_000

    private static func tile(row: Int, column: Int) -> NormalizedRect {
        let step = 1.0 / Double(tileGrid)
        let pad = step * tileOverlap
        let x = max(0, Double(column) * step - pad)
        // Vision's origin is lower-left, so row 0 is the top of the image.
        let y = max(0, 1.0 - Double(row + 1) * step - pad)
        return NormalizedRect(x: x,
                              y: y,
                              width: min(1.0 - x, step + pad * 2),
                              height: min(1.0 - y, step + pad * 2))
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return rendered.cgImage
    }
}


private extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:            .up
        case .down:          .down
        case .left:          .left
        case .right:         .right
        case .upMirrored:    .upMirrored
        case .downMirrored:  .downMirrored
        case .leftMirrored:  .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default:    .up
        }
    }
}
