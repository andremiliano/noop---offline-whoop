import Foundation
import StrandDesign

/// VO₂ max for Glance's Health Monitor (#2463): the cardio-fitness figure and where it sits against the
/// wearer's own history. Apple Health's measured value (the Watch's) wins when it exists; otherwise NOOP's
/// own estimate (`vo2max_est`, from heart rate), which is labelled as an estimate by the metric page it
/// opens. Both are read through the series the metric pages already use, so the tile and its page agree.
struct GlanceVO2 {
    /// Oldest first, one value per day.
    let points: [(day: String, value: Double)]
    /// The catalog key whose full page the tile's "All details" opens.
    let metricKey: String
    let latest: Double
    /// The middle 80% of the earlier readings, or nil without enough of them.
    let range: ClosedRange<Double>?
    let status: GlanceStatus

    static func text(_ v: Double) -> String { String(format: "%.1f ml/kg", locale: AppLanguage.activeLocale, v) }

    @MainActor
    static func load(_ repo: Repository) async -> GlanceVO2? {
        let measured = await repo.series(key: "vo2max", source: "apple-health", days: 400)
        let (key, raw): (String, [(day: String, value: Double)]) = !measured.isEmpty
            ? ("vo2max", measured)
            : ("vo2max_est", await repo.exploreSeries(key: "vo2max_est", source: "my-whoop").map { ($0.day, $0.value) })
        let points = raw.filter { $0.value.isFinite && $0.value > 0 }.sorted { $0.day < $1.day }
        guard let last = points.last else { return nil }
        let prior = points.dropLast().map(\.value)
        let result = UsualRange.evaluate(value: last.value, history: Array(prior))
        return GlanceVO2(points: points, metricKey: key, latest: last.value, range: result.band,
                         status: .usual(result))
    }
}
