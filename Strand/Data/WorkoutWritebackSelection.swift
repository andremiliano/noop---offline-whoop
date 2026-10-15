import Foundation
import WhoopStore

/// Which rows the Apple Health workout write-back writes.
///
/// Health's copy of a workout is keyed by its START time alone (`HealthWriteback.appleHealthWorkoutKey`),
/// but the rows were de-duplicated on start AND sport. The same session held under two or three sport
/// labels (a detected bout, a relabelled manual row, an import) therefore produced several rows sharing
/// one Health key: the delete-then-write cleared the old copies once and then saved every row, so Health
/// held the same session two or three times and any reader that lists workouts (Bevel) showed it that
/// many times. One session, one Health workout.
enum WorkoutWritebackSelection {

    /// One row per session. Rows that overlap by at least half of the shorter one are the same session
    /// (an in-app row and a strap-detected bout seconds apart, a relabelled copy), whatever their start
    /// times. A row the wearer or an import named (anything but an auto-detected bout) beats a detected
    /// one; then the longer session wins; on a tie the later row in `rows` wins, which is the order the
    /// caller already used (computed first, then the store's own rows).
    static func onePerStart(_ rows: [WorkoutRow]) -> [WorkoutRow] {
        var clusters: [WorkoutRow] = []   // the winner so far of each cluster
        for row in rows.sorted(by: { $0.startTs < $1.startTs }) {
            if let i = clusters.firstIndex(where: { sameSession($0, row) }) {
                if prefers(row, over: clusters[i]) { clusters[i] = row }
            } else {
                clusters.append(row)
            }
        }
        return clusters.sorted { $0.startTs < $1.startTs }
    }

    private static func sameSession(_ a: WorkoutRow, _ b: WorkoutRow) -> Bool {
        if a.startTs == b.startTs { return true }
        let overlap = min(a.endTs, b.endTs) - max(a.startTs, b.startTs)
        let shorter = min(a.endTs - a.startTs, b.endTs - b.startTs)
        return overlap > 0 && shorter > 0 && Double(overlap) >= 0.5 * Double(shorter)
    }

    private static func prefers(_ a: WorkoutRow, over b: WorkoutRow) -> Bool {
        let aDetected = WorkoutSource.classify(a.source) == .detected
        let bDetected = WorkoutSource.classify(b.source) == .detected
        if aDetected != bDetected { return !aDetected }
        let aLen = a.endTs - a.startTs, bLen = b.endTs - b.startTs
        if aLen != bLen { return aLen > bLen }
        return true
    }
}

/// What the Apple Health workout write-back does with the copies already in Health.
///
/// A Health workout is immutable and every write is a NEW object that readers such as Bevel import as a
/// new activity, so a workout is written once and then left alone. It is rewritten only when its content
/// changed (the signature differs) or its end time moved, and not at all while it may still be running.
struct WorkoutWritebackPlan: Equatable {
    /// What the store holds for one session, reduced to what the plan compares.
    struct Row: Equatable {
        let key: String
        /// Sport, energy and distance as written; a change in any of them means the Health copy is stale.
        let signature: String
        let startTs: Int
        let endTs: Int
        /// Whether the row may still be growing. Nil asks the plan to judge from the end time alone.
        var maybeRunning: Bool? = nil
    }

    /// One of our workouts already in Health. `signature` is nil for a copy written before signatures existed.
    struct Existing: Equatable {
        let id: UUID
        let key: String
        let signature: String?
        let startTs: Double
        let endTs: Double
    }

    /// Start and end times this close to the stored ones are the same session: a detected bout's edges move
    /// by seconds as more data arrives, and that alone must not cost a new Health object.
    static let timeTolerance = 120.0
    /// A workout that ended less than this long before the write is treated as possibly still running.
    static let settleSeconds = 600

    /// Existing copies to keep.
    let kept: Set<UUID>
    /// Indices into `rows` that need a new Health workout.
    let toWrite: [Int]
    /// Existing copies that match no row, or are extra copies of one.
    let stale: [UUID]

    static func plan(rows: [Row], existing: [Existing], now: Int) -> WorkoutWritebackPlan {
        var kept = Set<UUID>()
        var toWrite: [Int] = []
        for (i, row) in rows.enumerated() {
            let pending = row.maybeRunning ?? (row.endTs > now - settleSeconds)
            let match = existing.first { w in
                guard !kept.contains(w.id) else { return false }
                let sameStart = abs(w.startTs - Double(row.startTs)) < timeTolerance
                // A running workout keeps whatever copy it has (nothing is written until it settles), so
                // its moving end time and growing totals never cost a new Health object per sync.
                if pending { return w.key == row.key || sameStart }
                return sameStart && abs(w.endTs - Double(row.endTs)) < timeTolerance
                    && (w.signature == nil || w.signature == row.signature)
            }
            if let match { kept.insert(match.id) } else if !pending { toWrite.append(i) }
        }
        return WorkoutWritebackPlan(kept: kept, toWrite: toWrite,
                                    stale: existing.map(\.id).filter { !kept.contains($0) })
    }
}
