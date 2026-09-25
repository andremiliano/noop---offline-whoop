import Foundation

/// Today's Effort target (#2463 Simple view): the range of Effort worth aiming for given today's Charge,
/// so the day has a sensible goal rather than "as high as possible".
///
/// The band itself is NOOP's existing, approved recovery → optimal-strain mapping
/// (`CoupledView.optimalStrainRange`, #43), the same one the Coupled view shows and the target
/// notification fires on. This only converts it to the Effort scale the wearer reads and says where
/// today's Effort stands against it; it defines no band of its own.
enum EffortTarget {

    /// Where today's Effort sits against the target band.
    enum Standing: Equatable {
        /// Below the band; `toGo` is the distance to its lower edge, on the display scale.
        case below(toGo: Double)
        case within
        case above
    }

    /// Top of the Effort axis on `scale`.
    static func axisMax(_ scale: EffortScale) -> Double {
        scale == .whoop ? 21 : 100
    }

    /// The target band on `scale`, or nil when Charge is unknown (calibrating / unscored), in which case
    /// no target is shown rather than a guessed one — the same rule the band itself follows.
    static func band(charge: Double?, scale: EffortScale) -> ClosedRange<Double>? {
        guard let b = CoupledView.optimalStrainRange(recovery: charge) else { return nil }
        let lo = Double(b.lowerBound), hi = Double(b.upperBound)
        switch scale {
        case .whoop:   return lo...hi
        // The band is defined on the 0–21 axis; the 0–100 display is the same value divided back out of
        // `UnitFormatter.effortScaleFactor`, the exact inverse of how the 0–21 display is produced.
        case .hundred: return (lo / UnitFormatter.effortScaleFactor)...(hi / UnitFormatter.effortScaleFactor)
        }
    }

    /// Today's standing, with `effort` already on the same scale as `band`. Nil without both.
    static func standing(effort: Double?, band: ClosedRange<Double>?) -> Standing? {
        guard let effort, let band else { return nil }
        if effort < band.lowerBound { return .below(toGo: band.lowerBound - effort) }
        if effort > band.upperBound { return .above }
        return .within
    }
}
