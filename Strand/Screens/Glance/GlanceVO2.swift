import Foundation
import StrandDesign

/// VO₂ max for Glance's Health Monitor (#2463): the cardio-fitness figure and where it sits against the
/// wearer's own history. NOOP's own estimate from the strap (`vo2max_est`, heart-rate based) leads, since
/// this is the WHOOP wearer's number; Apple Health's measured value (the Watch's) is the fallback when the
/// strap has produced none. Both are read through the series the metric pages already use, so the tile and
/// its page agree. WHOOP's own VO₂ max is not available to NOOP: the strap does not send one.
struct GlanceVO2 {
    /// Oldest first, one value per day.
    let points: [(day: String, value: Double)]
    /// The catalog key whose full page the tile's "All details" opens.
    let metricKey: String
    let latest: Double
    /// True for NOOP's strap-based estimate, false for Apple Health's measured value.
    let isEstimate: Bool
    /// The middle 80% of the earlier readings, or nil without enough of them.
    let range: ClosedRange<Double>?

    /// The tile and page title: says "estimate" when it is NOOP's own figure.
    var title: String { isEstimate ? String(localized: "VO₂ Max (estimate)") : String(localized: "VO₂ Max") }
    let status: GlanceStatus

    static func text(_ v: Double) -> String { String(format: "%.1f ml/kg", locale: AppLanguage.activeLocale, v) }

    @MainActor
    static func load(_ repo: Repository) async -> GlanceVO2? {
        let estimate = await repo.exploreSeries(key: "vo2max_est", source: "my-whoop").map { ($0.day, $0.value) }
        let (key, raw): (String, [(day: String, value: Double)]) = !estimate.isEmpty
            ? ("vo2max_est", estimate)
            : ("vo2max", await repo.series(key: "vo2max", source: "apple-health", days: 400))
        let points = raw.filter { $0.value.isFinite && $0.value > 0 }.sorted { $0.day < $1.day }
        guard let last = points.last else { return nil }
        let prior = points.dropLast().map(\.value)
        let result = UsualRange.evaluate(value: last.value, history: Array(prior))
        return GlanceVO2(points: points, metricKey: key, latest: last.value, isEstimate: key == "vo2max_est",
                         range: result.band, status: .usual(result))
    }
}
