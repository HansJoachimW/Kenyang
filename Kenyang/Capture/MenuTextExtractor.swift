import Foundation
import PDFKit
import UIKit
import Vision

struct ExtractedText: Sendable {
    enum Source: String, Sendable {
        case pdfTextLayer = "PDF text layer"
        case visionOCR = "on-device text recognition"
    }

    var text: String
    var source: Source
    var pages: Int

    var characterCount: Int { text.count }

    var summary: String {
        "\(characterCount) characters from \(pages) page\(pages == 1 ? "" : "s") · \(source.rawValue)"
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
            let text = try await recognise(image)
            if !text.isEmpty { recognised.append(text) }
        }

        let joined = recognised.joined(separator: "\n")
        guard !joined.isEmpty else { throw Failure.noTextFound }
        return ExtractedText(text: joined, source: .visionOCR, pages: document.pageCount)
    }

    private static func fromImage(_ data: Data) async throws -> ExtractedText {
        guard let uiImage = UIImage(data: data), let image = uiImage.cgImage else {
            throw Failure.unreadableImage
        }
        let text = try await recognise(image, orientation: uiImage.cgOrientation)
        guard !text.isEmpty else { throw Failure.noTextFound }
        return ExtractedText(text: text, source: .visionOCR, pages: 1)
    }

    static let preferredLanguageCodes: Set<String> = ["en", "ja", "ko", "zh"]

    private static func recognise(_ image: CGImage,
                                  orientation: CGImagePropertyOrientation = .up) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false

        let usable = request.supportedRecognitionLanguages.filter {
            guard let code = $0.languageCode?.identifier else { return false }
            return preferredLanguageCodes.contains(code)
        }
        if !usable.isEmpty {
            request.recognitionLanguages = usable
            CaptureLog.line("OCR languages: \(usable.map(\.maximalIdentifier).joined(separator: ", "))")
        } else {
            CaptureLog.line("OCR languages: none of en/ja/ko/zh supported — using the model default")
        }

        let observations = try await request.perform(on: image, orientation: orientation)
        return observations.map(\.transcript).joined(separator: "\n")
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
