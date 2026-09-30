import FoundationModels

/// The one place that branches on iOS 27, where the framework enforces tool calls and
/// rolls back failed turns. On iOS 26 both are instructions and retries instead.
enum AgentCapabilities {
    static var summary: String {
        if #available(iOS 27.0, *) {
            return "iOS 27 — tool calling enforced, failed turns reverted"
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

    static func toolBound(_ tokens: Int) -> GenerationOptions {
        if #available(iOS 27.0, *) {
            return GenerationOptions(maximumResponseTokens: tokens, toolCallingMode: .required)
        }
        return GenerationOptions(maximumResponseTokens: tokens)
    }
}
