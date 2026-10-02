import FoundationModels

/// The one place that branches on iOS 27, where the framework rolls back failed turns.
/// Tool calling stays an instruction on both: `ToolCallingMode.required` kept the model
/// calling tools until the context overflowed.
enum AgentCapabilities {
    static var summary: String {
        if #available(iOS 27.0, *) {
            return "iOS 27 — tool calling instructed, failed turns reverted"
        }
        return "iOS 26 — tool calling instructed, failed turns retained"
    }

    static func session(tools: [any Tool] = [], instructions: String) -> LanguageModelSession {
        let session = LanguageModelSession(tools: tools, instructions: instructions)
        if #available(iOS 27.0, *) {
            session.transcriptErrorHandlingPolicy = .revertTranscript
        }
        return session
    }

    static func bounded(_ tokens: Int) -> GenerationOptions {
        GenerationOptions(maximumResponseTokens: tokens)
    }

    /// iOS 27 reports model failures as `LanguageModelError`; the agent's retry rules are
    /// written against `GenerationError`, so the cases they act on are mapped across.
    static func generationError(from error: Error) -> LanguageModelSession.GenerationError? {
        if let generation = error as? LanguageModelSession.GenerationError { return generation }
        guard #available(iOS 27.0, *), let modelError = error as? LanguageModelError else { return nil }
        switch modelError {
        case .contextSizeExceeded(let overflow):
            return .exceededContextWindowSize(.init(debugDescription: overflow.debugDescription))
        case .guardrailViolation(let violation):
            return .guardrailViolation(.init(debugDescription: violation.debugDescription))
        default:
            return nil
        }
    }
}
