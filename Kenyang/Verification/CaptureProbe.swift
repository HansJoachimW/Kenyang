import Foundation

/// T53 — run the capture pipeline against a real menu file without the UI.
///
/// The capture path could only be exercised by importing a photo by hand on a
/// physical device, which made every OCR question a round trip. This runs the same
/// extractor and parser from a launch argument, so settings can be tried in minutes:
///
///     xcrun simctl launch --console-pty <device> com.hansjoachim.Kenyang \
///         --capture-probe menu.jpg
///
/// The file is looked up as given, then in the app's Documents directory — copy it
/// there with `xcrun simctl get_app_container <device> com.hansjoachim.Kenyang data`.
///
/// ⚠️ The Simulator is not the device. It reads the Mac's locale, so the
/// `Locale not supported: id` failure cannot reproduce here, and Apple Intelligence
/// may be unavailable, in which case only the extraction half runs. Recognition
/// quality is representative; confirm anything that matters on the phone.
enum CaptureProbe {
    static func run(path: String) async {
        CaptureLog.rule("CAPTURE PROBE — \(path)")

        guard let url = locate(path) else {
            CaptureLog.line("FAILED — no file at \"\(path)\", and none in Documents")
            CaptureLog.line("Documents is: \(documentsDirectory?.path ?? "unavailable")")
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            CaptureLog.line("FAILED — could not read \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }

        let isPDF = url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
        let captured = CapturedMenu(kind: isPDF ? .pdf : .image,
                                    filename: url.lastPathComponent,
                                    data: data,
                                    pageCount: nil)

        let extracted: ExtractedText
        do {
            extracted = try await MenuTextExtractor.extract(from: captured)
        } catch {
            CaptureLog.line("EXTRACTION FAILED — \(error.localizedDescription)")
            return
        }

        CaptureLog.rule("PARSE")
        do {
            let drafts = try await MenuParser.parse(extracted)
            CaptureLog.line("")
            CaptureLog.line("\(drafts.count) item(s) kept:")
            for draft in drafts {
                CaptureLog.line("  \(draft.name) ‹\(draft.printedSection)› → \(draft.category.rawValue)")
            }
            let uncategorised = drafts.filter { $0.category == .unknown }.count
            CaptureLog.line("")
            CaptureLog.line("PROBE: \(drafts.count) item(s), \(uncategorised) uncategorised, from \(extracted.characterCount) characters")
        } catch {
            CaptureLog.line("PARSE FAILED — \(error.localizedDescription)")
            CaptureLog.line("PROBE: extraction only — \(extracted.characterCount) characters recovered")
        }
    }

    private static var documentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private static func locate(_ path: String) -> URL? {
        let direct = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        guard let inDocuments = documentsDirectory?.appendingPathComponent(direct.lastPathComponent),
              FileManager.default.fileExists(atPath: inDocuments.path) else { return nil }
        return inDocuments
    }
}
