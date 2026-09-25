import Foundation

/// The numbers behind a Glance trend page (#2463): the chosen window of a day series, its average, how
/// the recent days compare with the days before them, and the average for each weekday.
///
/// Descriptive only: averages and differences of the wearer's own stored values, nothing modelled.
enum TrendAnalysis {

    typealias Point = (day: String, value: Double)

    /// A change over one period: the average of the last `days` days minus the average of the `days`
    /// days before them, or nil when either stretch has no value.
    struct Change: Equatable {
        let days: Int
        let delta: Double?
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// A day key as a date (UTC midnight), or nil when malformed.
    static func date(_ day: String) -> Date? { dayParser.date(from: day) }

    /// `day` moved by `by` calendar days.
    static func shift(_ day: String, by: Int) -> String? {
        guard let d = date(day), let moved = utc.date(byAdding: .day, value: by, to: d) else { return nil }
        return dayParser.string(from: moved)
    }

    /// The points in the `days` calendar days ending on the newest point, oldest first.
    static func window(_ points: [Point], days: Int) -> [Point] {
        let sorted = points.sorted { $0.day < $1.day }
        guard let last = sorted.last?.day, let start = shift(last, by: -(days - 1)) else { return sorted }
        return sorted.filter { $0.day >= start }
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// For each period: the last `n` calendar days (ending on the newest point) against the `n` before.
    static func changes(_ points: [Point], periods: [Int] = [3, 7, 14, 30]) -> [Change] {
        guard let last = points.map(\.day).max() else { return periods.map { Change(days: $0, delta: nil) } }
        return periods.map { n in
            guard let recentStart = shift(last, by: -(n - 1)), let priorStart = shift(last, by: -(2 * n - 1)) else {
                return Change(days: n, delta: nil)
            }
            let recent = points.filter { $0.day >= recentStart && $0.day <= last }.map(\.value)
            let prior = points.filter { $0.day >= priorStart && $0.day < recentStart }.map(\.value)
            guard let a = mean(recent), let b = mean(prior) else { return Change(days: n, delta: nil) }
            return Change(days: n, delta: a - b)
        }
    }

    /// The average for each weekday, ordered from `firstWeekday` (1 = Sunday … 7 = Saturday); nil for a
    /// weekday with no value.
    static func weekdayMeans(_ points: [Point], firstWeekday: Int = Calendar.current.firstWeekday) -> [Double?] {
        var buckets = Array(repeating: [Double](), count: 7)
        for p in points {
            guard let d = date(p.day) else { continue }
            let wd = utc.component(.weekday, from: d)   // 1 = Sunday
            buckets[(wd - firstWeekday + 7) % 7].append(p.value)
        }
        return buckets.map(mean)
    }
}
