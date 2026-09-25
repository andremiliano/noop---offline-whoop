import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

/// #2463 Glance and the strap setup guide. The pure parts — what the guide tells each strap to turn on,
/// the Effort target and the usual-range reads — are pinned here rather than read off the screen.
final class GlanceTests: XCTestCase {

    // MARK: - StrapSetupGuide

    private func defaults() -> UserDefaults {
        let name = "GlanceTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testFamilyFromSelectedModel() {
        XCTAssertEqual(StrapSetupGuide.Family.forSelectedModel(WhoopModel.whoop5mg.rawValue), .whoop5)
        XCTAssertEqual(StrapSetupGuide.Family.forSelectedModel(WhoopModel.whoop4.rawValue), .whoop4)
        XCTAssertEqual(StrapSetupGuide.Family.forSelectedModel(""), .whoop4)
    }

    /// The finding behind #2464: on 5/MG the strap alarm needs Protocol probes in Test Centre; on 4.0 it
    /// needs nothing switched on.
    func testAlarmRequirementDiffersByGeneration() {
        let five = StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true).first { $0.id == "alarm" }
        let four = StrapSetupGuide.items(for: .whoop4, includesAppleHealth: true).first { $0.id == "alarm" }
        XCTAssertEqual(five?.requirement,
                       .toggle(key: PuffinExperiment.defaultsKey, place: .testCentre, control: "Protocol probes"))
        XCTAssertEqual(four?.requirement, .builtIn(place: .alarms))
    }

    func testBroadcastHeartRateOnlyForFiveSeries() {
        XCTAssertTrue(StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true).contains { $0.id == "broadcastHr" })
        XCTAssertFalse(StrapSetupGuide.items(for: .whoop4, includesAppleHealth: true).contains { $0.id == "broadcastHr" })
    }

    func testBloodOxygenIsUnavailableOnFiveSeriesAndBuiltInOnFour() {
        let five = StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true).first { $0.id == "bloodOxygen" }
        let four = StrapSetupGuide.items(for: .whoop4, includesAppleHealth: true).first { $0.id == "bloodOxygen" }
        if case .unavailable = five?.requirement {} else { XCTFail("5/MG SpO2 must read as unavailable") }
        XCTAssertEqual(four?.requirement, .builtIn(place: nil))
    }

    func testAppleHealthGoalOnlyWhereHealthExists() {
        XCTAssertTrue(StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true).contains { $0.id == "healthWater" })
        XCTAssertFalse(StrapSetupGuide.items(for: .whoop5, includesAppleHealth: false).contains { $0.id == "healthWater" })
    }

    func testStatusReadsTheControlsOwnKeys() {
        let d = defaults()
        let items = StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true)
        let hrv = items.first { $0.id == "overnightHrv" }!
        let scale = items.first { $0.id == "effortScale" }!

        XCTAssertEqual(StrapSetupGuide.status(of: hrv, defaults: d), .off)
        d.set(true, forKey: PuffinExperiment.keepRealtimeForDataKey)
        XCTAssertEqual(StrapSetupGuide.status(of: hrv, defaults: d), .on)

        XCTAssertEqual(StrapSetupGuide.status(of: scale, defaults: d), .off)
        d.set(EffortScale.whoop.rawValue, forKey: UnitPrefs.effortScaleKey)
        XCTAssertEqual(StrapSetupGuide.status(of: scale, defaults: d), .on)
    }

    /// Built-in and unavailable goals are not counted: the wearer has nothing to switch on for them.
    func testProgressCountsOnlySwitchableGoals() {
        let d = defaults()
        let items = StrapSetupGuide.items(for: .whoop5, includesAppleHealth: true)
        let switchable = items.filter {
            switch $0.requirement {
            case .toggle, .choice: return true
            default: return false
            }
        }.count
        XCTAssertEqual(StrapSetupGuide.progress(items, defaults: d).of, switchable)
        XCTAssertEqual(StrapSetupGuide.progress(items, defaults: d).on, 0)
        d.set(true, forKey: PuffinExperiment.defaultsKey)
        XCTAssertEqual(StrapSetupGuide.progress(items, defaults: d).on, 1)
    }

    // MARK: - EffortTarget

    func testTargetBandFollowsTheApprovedRecoveryMapping() {
        XCTAssertEqual(EffortTarget.band(charge: 80, scale: .whoop), 14...18)
        XCTAssertEqual(EffortTarget.band(charge: 50, scale: .whoop), 10...14)
        XCTAssertEqual(EffortTarget.band(charge: 20, scale: .whoop), 4...10)
        XCTAssertNil(EffortTarget.band(charge: nil, scale: .whoop))
    }

    /// The 0–100 band is the 0–21 band divided back out of the display factor, so a value shown on
    /// either scale sits at the same place against its band.
    func testHundredScaleBandIsTheExactInverseOfTheDisplayFactor() throws {
        let b = try XCTUnwrap(EffortTarget.band(charge: 80, scale: .hundred))
        XCTAssertEqual(b.lowerBound * UnitFormatter.effortScaleFactor, 14, accuracy: 1e-9)
        XCTAssertEqual(b.upperBound * UnitFormatter.effortScaleFactor, 18, accuracy: 1e-9)
    }

    func testStanding() {
        XCTAssertEqual(EffortTarget.standing(effort: 6, band: 10...14), .below(toGo: 4))
        XCTAssertEqual(EffortTarget.standing(effort: 10, band: 10...14), .within)
        XCTAssertEqual(EffortTarget.standing(effort: 14, band: 10...14), .within)
        XCTAssertEqual(EffortTarget.standing(effort: 15, band: 10...14), .above)
        XCTAssertNil(EffortTarget.standing(effort: nil, band: 10...14))
        XCTAssertNil(EffortTarget.standing(effort: 6, band: nil))
    }

    // MARK: - UsualRange

    func testNoBandWithLessThanAWeekOfHistory() {
        let r = UsualRange.evaluate(value: 50, history: [40, 45, 50, 55, 60, 65])
        XCTAssertNil(r.band)
        XCTAssertEqual(r.status, .notEnoughHistory)
    }

    /// The band is the middle 80% of the history: 1…11 gives 2…10.
    func testBandIsTheMiddleEightyPercent() throws {
        let b = try XCTUnwrap(UsualRange.band([9, 1, 8, 2, 7, 3, 6, 4, 5, 10, 11]))
        XCTAssertEqual(b.lowerBound, 2, accuracy: 1e-9)
        XCTAssertEqual(b.upperBound, 10, accuracy: 1e-9)
    }

    func testStatusAgainstTheBand() {
        let h: [Double] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
        XCTAssertEqual(UsualRange.evaluate(value: 5, history: h).status, .usual)
        XCTAssertEqual(UsualRange.evaluate(value: 2, history: h).status, .usual)
        XCTAssertEqual(UsualRange.evaluate(value: 10.5, history: h).status, .above)
        XCTAssertEqual(UsualRange.evaluate(value: 1.5, history: h).status, .below)
        XCTAssertEqual(UsualRange.evaluate(value: nil, history: h).status, .noData)
    }

    /// The displayed value ends the sparkline and is judged against the days BEFORE it only, so a day
    /// is never part of its own "usual".
    func testTrendEndsOnTheDisplayedValueAndExcludesItsOwnDay() {
        let pts: [(day: String, value: Double)] = (1...9).map { (String(format: "2026-09-%02d", $0), Double($0)) }
            + [("2026-09-10", 100)]
        let t = GlanceHistory.trend(pts, through: "2026-09-10", value: 5)
        XCTAssertEqual(t.values.last, 5)
        XCTAssertEqual(t.values.count, 10)
        XCTAssertEqual(t.result.status, .usual)
        XCTAssertEqual(t.result.band?.upperBound ?? 0, 8.2, accuracy: 1e-9)
    }
}

extension GlanceTests {
    /// The marker sits inside the shaded band exactly when the value is inside the range.
    func testMonitorGaugePlacesValueAndRangeOnOneAxis() throws {
        let g = try XCTUnwrap(GlanceMonitorTile.gauge(value: 60, values: [50, 70, 55], range: 55...65))
        XCTAssertEqual(g.marker, 0.5, accuracy: 1e-9)
        XCTAssertEqual(g.band?.lowerBound ?? -1, 0.25, accuracy: 1e-9)
        XCTAssertEqual(g.band?.upperBound ?? -1, 0.75, accuracy: 1e-9)
        let out = try XCTUnwrap(GlanceMonitorTile.gauge(value: 80, values: [50, 70], range: 55...65))
        XCTAssertFalse(out.band!.contains(out.marker))
        XCTAssertNil(GlanceMonitorTile.gauge(value: nil, values: [50, 70], range: nil))
        XCTAssertNil(GlanceMonitorTile.gauge(value: 60, values: [60], range: nil))
    }

    /// The range the Glance words cite and the banding the Health tab shows come from the same inputs:
    /// across a trusted personal baseline and a cold start, a plausible value is inside
    /// `BodyVitalSigns.normalRange` exactly when `VitalBands.band` calls it in range.
    func testNormalRangeAgreesWithVitalBandsEverywhere() {
        let trusted: [Double?] = (0..<40).map { 50 + Double($0 % 5) }
        let cold: [Double?] = [50, 52, 51]
        for history in [trusted, cold] {
            let range = BodyVitalSigns.normalRange(history: history, populationRange: 40...60, cfg: Baselines.restingHRCfg)
            for v in stride(from: 30.0, through: 80.0, by: 0.25) {
                let band = VitalBands.band(value: v, history: history, populationRange: 40...60, cfg: Baselines.restingHRCfg)
                XCTAssertEqual(band.band == .inRange, range.contains(v), "value \(v)")
            }
        }
    }
}

// MARK: - ActivityConsistency

extension GlanceTests {
    private func utcMonday() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    private func ts(_ y: Int, _ m: Int, _ d: Int, _ cal: Calendar) -> Int {
        Int(cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!.timeIntervalSince1970)
    }

    func testMonthsCountWorkoutsPerDayAndPlaceDayOneUnderItsWeekday() {
        let cal = utcMonday()
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 16))!
        let months = ActivityConsistency.months(
            workoutStarts: [ts(2026, 9, 1, cal), ts(2026, 9, 1, cal), ts(2026, 8, 31, cal)], now: now, calendar: cal)
        XCTAssertEqual(months.count, 2)
        let (aug, sep) = (months[0], months[1])
        XCTAssertEqual(aug.cells.count, 31)
        XCTAssertEqual(aug.cells[30].workouts, 1)
        XCTAssertEqual(sep.cells.count, 30)
        XCTAssertEqual(sep.cells[0].workouts, 2)
        // 1 September 2026 is a Tuesday: one blank under a Monday-first header.
        XCTAssertEqual(sep.leadingBlanks, 1)
        XCTAssertTrue(sep.cells[24].isToday)
        XCTAssertTrue(sep.cells[25].isFuture)
        XCTAssertFalse(aug.cells.contains { $0.isFuture })
    }

    private func scored(_ key: String, charge: Double?, strain: Double?) -> DailyMetric {
        DailyMetric(day: key, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil,
                    recovery: charge, strain: strain, exerciseCount: nil)
    }

    /// Charge 80 sets 14–18 on the 0–21 axis, so stored Effort 70 (14.7) is within, 50 (10.5) below and
    /// 95 (19.95) above. Today and half-scored days are not counted.
    func testTargetDaysJudgeEachDayAgainstItsOwnCharge() {
        let days = [
            scored("2026-09-20", charge: 80, strain: 70),
            scored("2026-09-21", charge: 80, strain: 50),
            scored("2026-09-22", charge: 80, strain: 95),
            scored("2026-09-23", charge: nil, strain: 60),
            scored("2026-09-24", charge: 20, strain: 30),   // 4–10 band, 6.3 → within
            scored("2026-09-25", charge: 80, strain: 10),   // today: still accruing
        ]
        let t = ActivityConsistency.targetDays(days, before: "2026-09-25")
        XCTAssertEqual(t, ActivityConsistency.TargetDays(below: 1, within: 2, above: 1))
        XCTAssertEqual(t.total, 4)
    }
}

// MARK: - EnergyEstimate (experimental)

extension GlanceTests {
    /// Charge 80, 5 h awake (−10), one hour at stress 2.5 (−2), one calm hour at 0.5 (+0.5), Effort 20
    /// (−6): 62.5.
    func testEnergyAddsUpItsStatedTerms() throws {
        let now = Date(timeIntervalSince1970: 1_000_000 + 5 * 3600)
        let r = try XCTUnwrap(EnergyEstimate.estimate(charge: 80, wakeTs: 1_000_000,
                                                      stressLevels: [2.5, 0.5, nil, 1.2], effort: 20, now: now))
        XCTAssertEqual(r.awake, 10, accuracy: 1e-9)
        XCTAssertEqual(r.stress, 1.5, accuracy: 1e-9)
        XCTAssertEqual(r.effort, 6, accuracy: 1e-9)
        XCTAssertEqual(r.energy, 62.5, accuracy: 1e-9)
    }

    func testEnergyNeedsAChargeAndAWakeTimeAndStaysInBounds() {
        let now = Date(timeIntervalSince1970: 1_000_000 + 30 * 3600)
        XCTAssertNil(EnergyEstimate.estimate(charge: nil, wakeTs: 1_000_000, stressLevels: [], effort: nil, now: now))
        XCTAssertNil(EnergyEstimate.estimate(charge: 80, wakeTs: nil, stressLevels: [], effort: nil, now: now))
        XCTAssertEqual(EnergyEstimate.estimate(charge: 20, wakeTs: 1_000_000, stressLevels: [3, 3],
                                               effort: 100, now: now)?.energy, 0)
    }
}
