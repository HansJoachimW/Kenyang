import CoreGraphics
import Foundation

/// Layer 0 of the capture path — refuse an image the app cannot read, and say what
/// to do about it.
///
/// The alternative is what the app did until now: hand the parser 33 characters and
/// let guided generation invent a menu out of them. That is T77 one stage earlier.
/// Under pressure to fill a `ParsedMenu` the model does not abstain, so the
/// abstention has to happen here, deterministically, before the model is asked
/// anything at all (Principle 10, and the same relationship `StopGuard` has with the
/// agent).
///
/// Principle 27: a validator with no way to say *I could not determine this* fails
/// open. This one fails closed, and it refuses **against the app's own interest** —
/// it would rather produce nothing than a plausible menu nobody printed.
enum CaptureQualityGuard {
    /// Measured, not guessed. A 224×224 share-sheet copy of a menu yields 33
    /// characters and four fabricated items; the same menu at 1024×724 yields 2,207
    /// characters and 71 real ones. The floor sits below anything that has worked.
    static let minimumMegapixels = 0.15
    static let minimumCharacters = 200
    static let minimumConfidence: Float = 0.45

    enum Complaint: LocalizedError, Equatable {
        case tooFewPixels(megapixels: Double)
        case tooLittleText(characters: Int)
        case unreliableText(confidence: Float)

        var errorDescription: String? {
            switch self {
            case .tooFewPixels(let megapixels):
                """
                This image is only \(String(format: "%.2f", megapixels)) MP — too small for the item names to survive \
                recognition. Photograph the menu itself rather than sharing a copy: chat apps, \
                previews and screenshots usually shrink an image to a fraction of its size.
                """
            case .tooLittleText(let characters):
                """
                Only \(characters) characters could be read, which is not a menu. Move closer and \
                capture one section at a time — you can read several photos in before finding \
                the items.
                """
            case .unreliableText(let confidence):
                """
                The text came back unreliable — \(Int(confidence * 100))% average confidence, which usually means \
                glare or a steep angle. Shoot square-on to the menu and keep reflections off \
                the laminate.
                """
            }
        }
    }

    /// Before recognition, so a hopeless image fails in milliseconds rather than after
    /// nine tiled Vision passes.
    static func inspect(_ image: CGImage) -> Complaint? {
        let megapixels = Double(image.width * image.height) / 1_000_000
        guard megapixels < minimumMegapixels else { return nil }
        return .tooFewPixels(megapixels: megapixels)
    }

    /// After recognition. Resolution is necessary and not sufficient — a 12 MP photo
    /// through glare reads no better than a thumbnail, and only the output shows it.
    static func inspect(text: String, confidence: Float?) -> Complaint? {
        let characters = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if characters < minimumCharacters { return .tooLittleText(characters: characters) }
        if let confidence, confidence < minimumConfidence {
            return .unreliableText(confidence: confidence)
        }
        return nil
    }
}
