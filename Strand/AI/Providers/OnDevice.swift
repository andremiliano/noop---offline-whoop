import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - The model that ships with the device (Apple Intelligence)

/// The on-device language model: no key, no account, nothing sent anywhere. It runs only on hardware that
/// supports Apple Intelligence with it switched on, so every entry point asks `status` first.
enum OnDeviceAI {

    enum Status: Equatable {
        case available
        /// Why it cannot be used, in a sentence a wearer can act on.
        case unavailable(String)
    }

    /// The model's context window is small (a few thousand tokens, instructions and reply included), so
    /// everything sent to it is cut to fit this many characters first (`OnDevicePrompt.fit`).
    static let promptBudgetCharacters = 7_000

    static var status: Status {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable("This device does not support Apple Intelligence.")
                case .appleIntelligenceNotEnabled:
                    return .unavailable("Apple Intelligence is switched off. Turn it on in Settings to use the on-device coach.")
                case .modelNotReady:
                    return .unavailable("The on-device model is still downloading. Try again in a little while.")
                @unknown default:
                    return .unavailable("The on-device model is not available right now.")
                }
            }
        }
        #endif
        return .unavailable("The on-device model needs iOS 26 or macOS 26.")
    }

    static var isAvailable: Bool { status == .available }
}

// MARK: - Fitting a conversation into the small window

/// Pure: cuts a system prompt and a conversation to a character budget, newest turns kept. The first user
/// turn carries the metrics context and is the biggest, so it is trimmed from its end (older days go,
/// today's lines stay near the top) rather than dropped.
enum OnDevicePrompt {

    static func fit(system: String,
                    messages: [(role: ChatMessage.Role, content: String)],
                    budget: Int = OnDeviceAI.promptBudgetCharacters) -> (system: String, transcript: String) {
        let sys = String(system.prefix(2_000))
        var remaining = max(budget - sys.count, 500)
        var kept: [String] = []
        // Newest first, so what the wearer just said always survives.
        for m in messages.reversed() {
            let label = m.role == .user ? "User" : "Coach"
            var text = m.content
            let overhead = label.count + 3
            if text.count + overhead > remaining {
                // Only the oldest kept turn is ever cut mid-way: keep its head and say so.
                let room = remaining - overhead - 1
                guard room > 200 else { break }
                text = String(text.prefix(room)) + "…"
            }
            kept.append("\(label): \(text)")
            remaining -= text.count + overhead
            if remaining <= 0 { break }
        }
        return (sys, kept.reversed().joined(separator: "\n\n"))
    }
}

// MARK: - Provider client

/// `AIProviderClient` over the system model, so the chat, the scheduled brief and the fallback path use it
/// exactly like a network provider. Ignores `key`, `model` and `session`.
struct OnDeviceClient: AIProviderClient {

    func send(key: String, model: String, systemPrompt: String,
              messages: [(role: ChatMessage.Role, content: String)],
              session: URLSession) async throws -> String {
        var text = ""
        try await stream(key: key, model: model, systemPrompt: systemPrompt, messages: messages,
                         session: session) { text += $0 }
        return text
    }

    func fetchModels(key: String, session: URLSession) async throws -> [String] { [] }

    func stream(key: String, model: String, systemPrompt: String,
                messages: [(role: ChatMessage.Role, content: String)],
                session: URLSession, onDelta: (String) -> Void) async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .unavailable(let why) = OnDeviceAI.status { throw AICoachError.onDevice(why) }
            let fitted = OnDevicePrompt.fit(system: systemPrompt, messages: messages)
            let lm = LanguageModelSession(instructions: fitted.system)
            do {
                // The stream yields the whole text so far each time, so only the new tail is a delta.
                var emitted = 0
                for try await partial in lm.streamResponse(to: fitted.transcript) {
                    let full = partial.content
                    if full.count > emitted {
                        onDelta(String(full.dropFirst(emitted)))
                        emitted = full.count
                    }
                }
            } catch {
                throw AICoachError.onDevice(Self.describe(error))
            }
            return
        }
        #endif
        throw AICoachError.onDevice("The on-device model needs iOS 26 or macOS 26.")
    }

    /// A failure in a wearer's words. The framework's own errors say "guardrail violation" and
    /// "exceeded context window"; neither helps, and neither is the wearer's doing.
    private static func describe(_ error: Error) -> String {
        let raw = String(describing: error).lowercased()
        if raw.contains("guardrail") { return "The on-device model declined that question. Try rephrasing it." }
        if raw.contains("context") { return "That was too long for the on-device model. Ask it more briefly." }
        if raw.contains("language") { return "The on-device model does not support your language yet." }
        return "The on-device model could not answer: \(error.localizedDescription)"
    }
}

// MARK: - Guided generation of the brief

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct GeneratedBriefAction {
    @Guide(description: "One to three words naming the action, such as Train, Recover or Fuel.")
    var title: String
    @Guide(description: "One short sentence with a concrete action for today, citing a number from the data.")
    var detail: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct GeneratedBrief {
    @Guide(description: "The one thing to know today, under ten words.")
    var headline: String
    @Guide(description: "One or two sentences on readiness that cite charge, HRV and rest from the data.")
    var readiness: String
    @Guide(description: "Two or three actions for today.", .count(2...3))
    var today: [GeneratedBriefAction]
    @Guide(description: "Up to three short things to watch, each under twelve words.", .count(0...3))
    var watch: [String]
    @Guide(description: "One sentence about tonight's sleep.")
    var tonight: String
}
#endif

enum OnDeviceBrief {
    /// Writes the brief from `context` with the system model. Throws `AICoachError.onDevice` with a reason.
    static func generate(context: String, systemPrompt: String) async throws -> CoachBriefContent {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .unavailable(let why) = OnDeviceAI.status { throw AICoachError.onDevice(why) }
            let fitted = OnDevicePrompt.fit(system: systemPrompt, messages: [(.user, context)],
                                            budget: OnDeviceAI.promptBudgetCharacters - 600)
            let session = LanguageModelSession(instructions: fitted.system)
            do {
                let reply = try await session.respond(
                    to: fitted.transcript + "\n\nWrite today's coaching brief from this data.",
                    generating: GeneratedBrief.self)
                let g = reply.content
                return CoachBriefContent(
                    headline: g.headline, readiness: g.readiness,
                    today: g.today.map { .init(title: $0.title, detail: $0.detail) },
                    watch: g.watch, tonight: g.tonight)
            } catch {
                throw AICoachError.onDevice("The on-device model could not write the brief: \(error.localizedDescription)")
            }
        }
        #endif
        throw AICoachError.onDevice("The on-device model needs iOS 26 or macOS 26.")
    }
}
