import Foundation
import FoundationModels

/// What the framework underneath is willing to enforce.
///
/// The app is built against the iOS 26 baseline and every measurement in `TESTS.md` was
/// taken there. iOS 27 shipped an agentic layer that turns two of this app's written
/// promises into framework behaviour, so they are taken when the OS offers them and the
/// 26.5 path is left exactly as it was measured. Nothing here changes what the agent
/// decides — only what the runtime guarantees while it decides it.
///
/// Both are reported in the trace, because a guarantee the examiner cannot see is
/// indistinguishable from one that is not there.
enum AgentCapabilities {

    /// `ToolCallingMode.required`. Guardrail layer 2 says *"You must call the tools to
    /// find out what is true"* — on 26.5 that is an instruction and the model complies
    /// 8/8 in a logged run but is under no obligation to. On 27 the framework refuses
    /// to answer without a tool call, which is the difference between a measurement and
    /// a guarantee.
    static var enforcesToolCalling: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    /// `TranscriptErrorHandlingPolicy.revertTranscript`. `RoundDecision` decode-fails
    /// ~20% of the time and the fix is one retry. On 26.5 the failed turn stays in the
    /// transcript, so the retry pays for the wreckage of the attempt it is replacing —
    /// which is why the overflow path has to rebuild a fresh session to recover at all.
    /// On 27 the session rolls the failed turn back and the retry starts clean.
    static var revertsFailedTurns: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    static var summary: String {
        enforcesToolCalling
            ? "iOS 27 — tool calling enforced, failed turns reverted"
            : "iOS 26 — tool calling instructed, failed turns retained"
    }

    /// Every session the agent opens goes through here, so the policy is not something
    /// one call site remembers and another forgets.
    static func session(tools: [any Tool] = [], instructions: String) -> LanguageModelSession {
        let session = LanguageModelSession(tools: tools, instructions: instructions)
        if #available(iOS 27.0, *) {
            session.transcriptErrorHandlingPolicy = .revertTranscript
        }
        return session
    }

    /// Bounded output for a call that does not read tools.
    static func bounded(_ tokens: Int) -> GenerationOptions {
        GenerationOptions(maximumResponseTokens: tokens)
    }

    /// Bounded output for a call whose answer is only trustworthy if the tools were
    /// consulted first.
    static func toolBound(_ tokens: Int) -> GenerationOptions {
        if #available(iOS 27.0, *) {
            return GenerationOptions(maximumResponseTokens: tokens, toolCallingMode: .required)
        }
        return GenerationOptions(maximumResponseTokens: tokens)
    }
}
