import Foundation

/// Where a value sits against the wearer's own recent history — the "Typical for you" / "Higher than
/// usual" read on Glance trend rows (#2463).
///
/// Descriptive only. The band is the middle half (25th–75th percentile) of the prior days, so "usual"
/// means "like half of your recent days", not "healthy". It is used for scores and durations, which have
/// no personal baseline of their own; vitals keep `VitalBands`, the baseline the Health tab bands them
/// against, so a vital never reads one way here and another way there.
enum UsualRange {

    enum Status: Equatable {
        case usual
        case above
        case below
        /// Fewer than `minimumHistory` prior values: no band is claimed.
        case notEnoughHistory
        case noData
    }

    struct Result: Equatable {
        /// The 25th–75th percentile band of the history, or nil without enough of it.
        let band: ClosedRange<Double>?
        let status: Status
    }

    /// Prior values needed before a band is drawn — a week of history.
    static let minimumHistory = 7

    /// `value` against `history`, the prior values oldest → newest (the value's own day excluded).
    static func evaluate(value: Double?, history: [Double]) -> Result {
        let band = self.band(history)
        guard let value else { return Result(band: band, status: .noData) }
        guard let band else { return Result(band: nil, status: .notEnoughHistory) }
        if value > band.upperBound { return Result(band: band, status: .above) }
        if value < band.lowerBound { return Result(band: band, status: .below) }
        return Result(band: band, status: .usual)
    }

    /// The 25th–75th percentile band of `history`, or nil with fewer than `minimumHistory` values.
    static func band(_ history: [Double]) -> ClosedRange<Double>? {
        let sorted = history.filter(\.isFinite).sorted()
        guard sorted.count >= minimumHistory else { return nil }
        return percentile(sorted, 0.25)...percentile(sorted, 0.75)
    }

    /// Linear-interpolated percentile of an ascending, non-empty array.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let pos = p * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }
}
