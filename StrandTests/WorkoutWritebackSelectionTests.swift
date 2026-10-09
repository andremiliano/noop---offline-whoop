import XCTest
import WhoopStore
@testable import Strand

/// One session held under several sport labels must reach Apple Health once: its Health key is the start
/// time alone, so every extra row would be saved under the same key.
final class WorkoutWritebackSelectionTests: XCTestCase {

    private func row(_ start: Int, _ end: Int, sport: String, source: String) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: end, sport: sport, source: source, durationS: Double(end - start),
                   energyKcal: 492, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                   zonesJSON: nil, notes: nil, steps: nil)
    }

    func testSameStartUnderThreeLabelsIsWrittenOnce() {
        let rows = WorkoutWritebackSelection.onePerStart([
            row(1000, 4360, sport: "detected", source: "my-whoop-noop"),
            row(1000, 4360, sport: "Activity", source: "my-whoop"),
            row(1000, 4360, sport: "Running", source: "manual"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].sport, "Running", "a named row beats a detected bout")
    }

    func testDistinctStartsAreAllKeptInOrder() {
        let rows = WorkoutWritebackSelection.onePerStart([
            row(5000, 6000, sport: "Cycling", source: "manual"),
            row(1000, 2000, sport: "Running", source: "manual"),
        ])
        XCTAssertEqual(rows.map(\.startTs), [1000, 5000])
    }

    func testLongerSessionWinsBetweenTwoNamedRows() {
        let rows = WorkoutWritebackSelection.onePerStart([
            row(1000, 1200, sport: "Running", source: "manual"),
            row(1000, 4000, sport: "Activity", source: "my-whoop"),
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].endTs, 4000)
    }
}

final class WorkoutWritebackPlanTests: XCTestCase {
    private typealias P = WorkoutWritebackPlan
    private let now = 1_000_000

    private func row(_ start: Int, _ end: Int, sig: String = "run|500|0") -> P.Row {
        .init(key: "noop:workout:\(start)", signature: sig, startTs: start, endTs: end)
    }
    private func copy(_ start: Int, _ end: Int, sig: String? = "run|500|0", id: UUID = UUID()) -> P.Existing {
        .init(id: id, key: "noop:workout:\(start)", signature: sig, startTs: Double(start), endTs: Double(end))
    }

    func testUnchangedWorkoutIsLeftAlone() {
        let c = copy(1000, 4000)
        let plan = P.plan(rows: [row(1000, 4000)], existing: [c], now: now)
        XCTAssertEqual(plan.toWrite, [])
        XCTAssertEqual(plan.stale, [])
        XCTAssertEqual(plan.kept, [c.id])
    }

    func testChangedContentIsRewrittenAndTheOldCopyDropped() {
        let c = copy(1000, 4000, sig: "run|500|0")
        let plan = P.plan(rows: [row(1000, 4000, sig: "cycling|520|8000")], existing: [c], now: now)
        XCTAssertEqual(plan.toWrite, [0])
        XCTAssertEqual(plan.stale, [c.id])
    }

    func testCopyWithoutSignatureMatchesOnTimes() {
        let c = copy(1000, 4000, sig: nil)
        XCTAssertEqual(P.plan(rows: [row(1000, 4000)], existing: [c], now: now).toWrite, [])
    }

    func testEndShiftedPastToleranceRewrites() {
        let c = copy(1000, 4000)
        XCTAssertEqual(P.plan(rows: [row(1000, 4030)], existing: [c], now: now).toWrite, [])
        XCTAssertEqual(P.plan(rows: [row(1000, 4100)], existing: [c], now: now).toWrite, [0])
    }

    func testExtraCopiesOfOneSessionAreStale() {
        let a = copy(1000, 4000), b = copy(1000, 4000), c = copy(1000, 4000)
        let plan = P.plan(rows: [row(1000, 4000)], existing: [a, b, c], now: now)
        XCTAssertEqual(plan.kept, [a.id])
        XCTAssertEqual(plan.stale, [b.id, c.id])
    }

    func testRowGoneFromTheStoreLeavesItsCopyStale() {
        let c = copy(1000, 4000)
        XCTAssertEqual(P.plan(rows: [], existing: [c], now: now).stale, [c.id])
    }

    /// A workout that may still be running is neither written nor rewritten, and keeps the copy it has.
    func testRunningWorkoutIsDeferred() {
        let recent = now - 100
        XCTAssertEqual(P.plan(rows: [row(now - 3000, recent)], existing: [], now: now).toWrite, [])
        let c = copy(now - 3000, recent - 500)
        let plan = P.plan(rows: [row(now - 3000, recent, sig: "run|900|0")], existing: [c], now: now)
        XCTAssertEqual(plan.toWrite, [])
        XCTAssertEqual(plan.stale, [])
    }
}
