import FoundationModels

enum ModelAvailability {
    case ready, downloading, notEnabled, unsupported

    static var current: ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .downloading
        case .unavailable:
            return .unsupported
        }
    }

    var isReady: Bool { self == .ready }

    var explanation: String {
        switch self {
        case .ready:       ""
        case .downloading: "Apple Intelligence is still downloading. Until it finishes, rounds are planned from typical ratings."
        case .notEnabled:  "Apple Intelligence is off, so rounds are planned from typical ratings. Turn it on in Settings to get the AI's reasoning."
        case .unsupported: "This iPhone can't run Apple Intelligence. Kenyang still plans rounds from typical ratings and the room you have left."
        }
    }
}
