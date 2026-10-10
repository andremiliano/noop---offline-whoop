import Foundation

/// Today's coaching brief as a page's worth of parts, not a block of chat: one headline, a readiness line,
/// up to three things to do today, up to three things to watch, and tonight.
///
/// The on-device model fills it through guided generation (`OnDeviceBrief`); a network provider is asked for
/// JSON and read through `parse`, which never fails: anything that is not the JSON becomes the readiness line.
struct CoachBriefContent: Codable, Equatable {
    struct Action: Codable, Equatable, Identifiable {
        var title: String
        var detail: String
        var id: String { title + "|" + detail }
    }

    var headline: String
    var readiness: String
    var today: [Action]
    var watch: [String]
    var tonight: String

    /// Asked of a network provider after the data context.
    static let jsonInstruction = """
    Write today's coaching brief as ONE JSON object and nothing else (no Markdown, no code fence), with \
    exactly these keys: "headline" (under 10 words, the one thing to know today), "readiness" (one or two \
    sentences citing my charge, HRV and rest), "today" (an array of 2 or 3 objects, each with "title" of \
    one to three words such as "Train", "Recover" or "Fuel" and "detail" of one short sentence with a \
    concrete action), "watch" (an array of up to 3 short strings), and "tonight" (one sentence about \
    tonight's sleep). Cite my actual numbers; a dash in the data means not measured, not zero.
    """

    /// Reads a provider's reply. Tolerates prose or a code fence around the object.
    static func parse(_ raw: String) -> CoachBriefContent {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
           let data = String(text[open...close]).data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let today: [Action] = (obj["today"] as? [[String: Any]] ?? []).compactMap {
                guard let detail = ($0["detail"] as? String)?.trimmed, !detail.isEmpty else { return nil }
                return Action(title: ($0["title"] as? String)?.trimmed ?? "", detail: detail)
            }
            let content = CoachBriefContent(
                headline: (obj["headline"] as? String)?.trimmed ?? "",
                readiness: (obj["readiness"] as? String)?.trimmed ?? "",
                today: Array(today.prefix(3)),
                watch: Array((obj["watch"] as? [String] ?? []).map(\.trimmed).filter { !$0.isEmpty }.prefix(3)),
                tonight: (obj["tonight"] as? String)?.trimmed ?? "")
            if !content.headline.isEmpty || !content.readiness.isEmpty || !content.today.isEmpty { return content }
        }
        // Not the object: keep the words, as the readiness line under a headline cut from their start.
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let headline = String(firstLine.prefix(70))
        return CoachBriefContent(headline: headline, readiness: text, today: [], watch: [], tonight: "")
    }

    var isEmpty: Bool { headline.isEmpty && readiness.isEmpty && today.isEmpty }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The brief as it was last generated, kept so the page opens at once and only regenerates when the data
/// it was written from has changed or the wearer asks.
struct CoachBriefCache: Codable, Equatable {
    var fingerprint: String
    var source: String
    var generatedAt: Date
    var content: CoachBriefContent

    static let key = "coach.pageBrief.v1"

    static func load() -> CoachBriefCache? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CoachBriefCache.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
