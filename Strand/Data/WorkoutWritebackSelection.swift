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

    /// One row per start time. A row the wearer or an import named (anything but an auto-detected bout)
    /// beats a detected one; then the longer session wins; on a tie the later row in `rows` wins, which
    /// is the order the caller already used (computed first, then the store's own rows).
    static func onePerStart(_ rows: [WorkoutRow]) -> [WorkoutRow] {
        var byStart: [Int: WorkoutRow] = [:]
        for row in rows {
            if let current = byStart[row.startTs], !prefers(row, over: current) { continue }
            byStart[row.startTs] = row
        }
        return byStart.values.sorted { $0.startTs < $1.startTs }
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
    }

    /// One of our workouts already in Health. `signature` is nil for a copy written before signatures existed.
    struct Existing: Equatable {
        let id: UUID
        let key: String
        let signature: String?
        let startTs: Double
        let endTs: Double
    }

    /// An end time this close to the stored one is the same session.
    static let endTolerance = 60.0
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
            let pending = row.endTs > now - settleSeconds
            let match = existing.first { w in
                guard !kept.contains(w.id), w.key == row.key else { return false }
                // A running workout keeps whatever copy it has (nothing is written until it settles), so
                // its moving end time and growing totals never cost a new Health object per sync.
                if pending { return true }
                return abs(w.startTs - Double(row.startTs)) < 1
                    && abs(w.endTs - Double(row.endTs)) < endTolerance
                    && (w.signature == nil || w.signature == row.signature)
            }
            if let match { kept.insert(match.id) } else if !pending { toWrite.append(i) }
        }
        return WorkoutWritebackPlan(kept: kept, toWrite: toWrite,
                                    stale: existing.map(\.id).filter { !kept.contains($0) })
    }
}
