import Foundation

/// Simple view (#2463): an opt-in presentation of Today that keeps the three scores, the one-line
/// synthesis, the recovery vitals and today's workouts, and makes each score open the wearer's own data
/// behind it.
///
/// Presentation only. It filters which sections render and where a score tap goes; it never computes a
/// figure of its own, so a number shown in Simple view is the same resolver's output the full view shows.
enum SimpleViewPrefs {
    /// `@AppStorage` key for the toggle. Default OFF: the full Today is unchanged unless a wearer opts in.
    static let enabledKey = "noop.simpleView"

    /// The sections Simple view keeps, in no particular order — the wearer's saved order decides that.
    static let keptSections: Set<TodaySection> = [.hero, .synthesis, .recoveryVitals, .workouts]

    /// The Today sections to render in Simple view, in the wearer's saved order.
    ///
    /// `fullOrder` is the order WITHOUT the hidden filter applied: Simple view is a fixed, minimal layout,
    /// so a section the wearer hid in the full view (the hero, say) still appears here rather than
    /// leaving Simple view with nothing to show. Any kept section missing from `fullOrder` — a saved order
    /// from before it existed — is appended in the canonical order below, so the result always carries
    /// all of them.
    static func order(fullOrder: [TodaySection]) -> [TodaySection] {
        var out = fullOrder.filter { keptSections.contains($0) }
        for section in [TodaySection.hero, .synthesis, .recoveryVitals, .workouts] where !out.contains(section) {
            out.append(section)
        }
        return out
    }
}
