import Foundation

/// Energy (#2463 Glance, EXPERIMENTAL): a rough "how much is left in the tank" read for the rest of today.
///
/// NOT validated. It is a transparent rule of thumb over signals NOOP already scores, shown only behind
/// the default-off Glance experimental switch and always labelled as an estimate:
///
/// - the day starts at this morning's Charge;
/// - every waking hour since you woke drains `hourlyDrain` points;
/// - each scored hour whose stress sits above the Stress tab's baseline (1.5 on its 0–3 scale) drains
///   `stressDrainPerLevel` points per level above it, and each calm hour (below 1.0) gives back
///   `calmRefillPerLevel` points per level below it;
/// - today's Effort drains `effortDrainPerPoint` points per Effort point on the 0–100 scale.
///
/// The result is clamped to 0–100. Every term is returned so the card can show what moved it, and no
/// term is stored or fed into another score.
enum EnergyEstimate {

    static let hourlyDrain = 2.0
    static let stressBaseline = 1.5
    static let stressDrainPerLevel = 2.0
    static let calmLevel = 1.0
    static let calmRefillPerLevel = 1.0
    static let effortDrainPerPoint = 0.3

    struct Result: Equatable {
        /// The estimate, 0–100.
        let energy: Double
        /// This morning's Charge, where the day started.
        let start: Double
        /// Points taken by time awake.
        let awake: Double
        /// Points taken by stressful hours, net of what calm hours gave back (negative = net refill).
        let stress: Double
        /// Points taken by today's Effort.
        let effort: Double
        /// Whole hours awake so far.
        let hoursAwake: Double
    }

    /// The estimate at `now`, or nil without this morning's Charge or a wake time.
    ///
    /// - Parameters:
    ///   - charge: this morning's Charge, 0–100.
    ///   - wakeTs: when last night's sleep ended, unix seconds.
    ///   - stressLevels: the scored hours' stress levels on the Stress tab's 0–3 scale (nil = unscored).
    ///   - effort: today's Effort on the 0–100 scale.
    static func estimate(charge: Double?, wakeTs: Int?, stressLevels: [Double?], effort: Double?,
                         now: Date) -> Result? {
        guard let charge, let wakeTs else { return nil }
        let hours = max(0, now.timeIntervalSince1970 - TimeInterval(wakeTs)) / 3600
        let awake = hours * hourlyDrain
        var stress = 0.0
        for level in stressLevels.compactMap({ $0 }) {
            if level > stressBaseline { stress += (level - stressBaseline) * stressDrainPerLevel }
            if level < calmLevel { stress -= (calmLevel - level) * calmRefillPerLevel }
        }
        let effortDrain = max(0, effort ?? 0) * effortDrainPerPoint
        let energy = max(0, min(100, charge - awake - stress - effortDrain))
        return Result(energy: energy, start: charge, awake: awake, stress: stress, effort: effortDrain,
                      hoursAwake: hours)
    }
}
