import Foundation

/// Where a VO₂ max sits for the wearer's age and sex (#2463 Glance): five categories cut at the 40th, 60th,
/// 80th and 95th percentile of the Cooper Institute's reference table for adults, in ml/kg/min.
///
/// A population comparison, not a health verdict: the percentiles describe a reference group, and a
/// watch or strap ESTIMATE of VO₂ max reads differently from a lab test, so the categories say where a
/// figure sits among people of the same age and sex, nothing about the wearer's health.
enum Vo2MaxNorms {

    enum Category: Int, CaseIterable, Comparable {
        case low, fair, good, excellent, superior
        static func < (a: Category, b: Category) -> Bool { a.rawValue < b.rawValue }
    }

    /// The lower edge of Fair, Good, Excellent and Superior (the 40th, 60th, 80th and 95th percentiles).
    struct Cutoffs: Equatable {
        let fair: Double, good: Double, excellent: Double, superior: Double

        /// The lower edge of `category`; Low has none.
        func lowerEdge(_ category: Category) -> Double? {
            switch category {
            case .low: return nil
            case .fair: return fair
            case .good: return good
            case .excellent: return excellent
            case .superior: return superior
            }
        }
    }

    /// Age bands, in years: 20-29 … 70-79. Younger adults read against the first, older against the last.
    static let bands: [ClosedRange<Int>] = [20...29, 30...39, 40...49, 50...59, 60...69, 70...79]

    // Rows follow `bands`; columns are fair, good, excellent, superior.
    private static let men: [[Double]] = [
        [41.7, 45.4, 51.1, 55.4], [40.5, 44.0, 48.3, 54.0], [38.5, 42.4, 46.4, 52.5],
        [35.6, 39.2, 43.4, 48.9], [32.3, 35.5, 39.5, 45.7], [29.4, 32.3, 36.7, 42.1],
    ]
    private static let women: [[Double]] = [
        [36.1, 39.5, 43.9, 49.6], [34.4, 37.8, 42.4, 47.4], [33.0, 36.3, 39.7, 45.3],
        [30.1, 33.0, 36.7, 41.1], [27.5, 30.0, 33.0, 37.8], [25.9, 28.1, 30.9, 36.7],
    ]

    /// The band index for `age`, clamped to the table's ends.
    static func bandIndex(age: Int) -> Int {
        bands.firstIndex { $0.contains(age) } ?? (age < 20 ? 0 : bands.count - 1)
    }

    /// The cutoffs for this age and sex, or nil when the sex is neither "male" nor "female" (the table has
    /// no other column, and mixing the two would be a guess).
    static func cutoffs(age: Int, sex: String) -> Cutoffs? {
        let rows: [[Double]]
        switch sex.lowercased() {
        case "male": rows = men
        case "female": rows = women
        default: return nil
        }
        let r = rows[bandIndex(age: age)]
        return Cutoffs(fair: r[0], good: r[1], excellent: r[2], superior: r[3])
    }

    static func category(_ vo2: Double, cutoffs c: Cutoffs) -> Category {
        if vo2 >= c.superior { return .superior }
        if vo2 >= c.excellent { return .excellent }
        if vo2 >= c.good { return .good }
        if vo2 >= c.fair { return .fair }
        return .low
    }

    /// The band as the table prints it, "30-39"; "70-79" for anyone older, "20-29" for anyone younger.
    static func bandLabel(age: Int) -> String {
        let b = bands[bandIndex(age: age)]
        return "\(b.lowerBound)-\(b.upperBound)"
    }
}
