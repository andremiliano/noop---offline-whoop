import XCTest
import WhoopStore
@testable import Strand

final class CoachBriefTests: XCTestCase {

    // MARK: Reading a provider's reply

    func testParsesTheJSONObject() {
        let raw = """
        {"headline":"Green light","readiness":"Charge 82, HRV 64.","today":[{"title":"Train","detail":"Intervals."},{"title":"Fuel","detail":"Eat well."}],"watch":["Sleep debt"],"tonight":"Bed by 22:30."}
        """
        let b = CoachBriefContent.parse(raw)
        XCTAssertEqual(b.headline, "Green light")
        XCTAssertEqual(b.today.map(\.title), ["Train", "Fuel"])
        XCTAssertEqual(b.watch, ["Sleep debt"])
        XCTAssertEqual(b.tonight, "Bed by 22:30.")
    }

    func testToleratesACodeFenceAndProse() {
        let raw = "Here you go:\n```json\n{\"headline\":\"Easy day\",\"readiness\":\"Low charge.\",\"today\":[],\"watch\":[],\"tonight\":\"\"}\n```"
        XCTAssertEqual(CoachBriefContent.parse(raw).headline, "Easy day")
    }

    func testPlainTextBecomesTheReadinessLine() {
        let b = CoachBriefContent.parse("Your charge is 40.\nTake it easy.")
        XCTAssertEqual(b.headline, "Your charge is 40.")
        XCTAssertTrue(b.readiness.contains("Take it easy."))
        XCTAssertTrue(b.today.isEmpty)
    }

    func testMoreThanThreeActionsAreCut() {
        let raw = "{\"headline\":\"h\",\"readiness\":\"r\",\"today\":[{\"title\":\"a\",\"detail\":\"1\"},{\"title\":\"b\",\"detail\":\"2\"},{\"title\":\"c\",\"detail\":\"3\"},{\"title\":\"d\",\"detail\":\"4\"}],\"watch\":[],\"tonight\":\"\"}"
        XCTAssertEqual(CoachBriefContent.parse(raw).today.count, 3)
    }

    // MARK: Fitting the small window

    func testFitKeepsTheNewestTurnAndCutsTheOldest() {
        let big = String(repeating: "x", count: 20_000)
        let fitted = OnDevicePrompt.fit(system: "sys", messages: [(.user, big), (.assistant, "earlier"), (.user, "latest question")],
                                        budget: 1_000)
        XCTAssertTrue(fitted.transcript.contains("latest question"))
        XCTAssertLessThanOrEqual(fitted.transcript.count, 1_000)
    }

    func testFitLeavesAShortConversationWhole() {
        let fitted = OnDevicePrompt.fit(system: "sys", messages: [(.user, "hi"), (.assistant, "hello")])
        XCTAssertEqual(fitted.transcript, "User: hi\n\nCoach: hello")
    }

    // MARK: When the chosen provider cannot answer

    func testOnlyAProviderFailureFallsBack() {
        XCTAssertTrue(AICoachEngine.shouldFallBack(to: .badKey))
        XCTAssertTrue(AICoachEngine.shouldFallBack(to: .network("offline")))
        XCTAssertTrue(AICoachEngine.shouldFallBack(to: .rateLimited("")))
        XCTAssertTrue(AICoachEngine.shouldFallBack(to: .server(500, "")))
        XCTAssertFalse(AICoachEngine.shouldFallBack(to: .noKey))
        XCTAssertFalse(AICoachEngine.shouldFallBack(to: .emptyQuestion))
        XCTAssertFalse(AICoachEngine.shouldFallBack(to: .badCustomURL("x")))
        XCTAssertFalse(AICoachEngine.shouldFallBack(to: .onDevice("x")))
    }

    func testTheFallbackSaysWhyAndNamesTheProvider() {
        let text = AICoachEngine.fallbackExplanation(for: .badKey, providerName: "OpenAI")
        XCTAssertTrue(text.contains("OpenAI"))
        XCTAssertTrue(text.contains("rejected your key"))
    }

    // MARK: The page's own numbers

    private func day(_ d: String, recovery: Double?, strain: Double? = nil, sleepMin: Double? = nil,
                     hrv: Double? = nil, rhr: Int? = nil) -> DailyMetric {
        DailyMetric(day: d, totalSleepMin: sleepMin, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: recovery, strain: strain,
                    exerciseCount: nil)
    }

    func testGlanceComparesTodayWithTheDaysBefore() throws {
        var days = (1...10).map { day(String(format: "2026-10-%02d", $0), recovery: 60, strain: 10, sleepMin: 420, hrv: 50, rhr: 55) }
        days.append(day("2026-10-11", recovery: 85, strain: 12, sleepMin: 480, hrv: 60, rhr: 52))
        let g = try XCTUnwrap(CoachGlance.make(from: days))
        XCTAssertEqual(g.charge, 85)
        XCTAssertEqual(g.week.count, 7)
        let hrv = try XCTUnwrap(g.stats.first { $0.id == "hrv" })
        XCTAssertEqual(hrv.deltaText, "+10")
        let rhr = try XCTUnwrap(g.stats.first { $0.id == "rhr" })
        XCTAssertFalse(rhr.higherIsBetter)
        XCTAssertEqual(rhr.deltaText, "-3")
    }

    func testGlanceNeedsABaselineBeforeItClaimsADifference() throws {
        let g = try XCTUnwrap(CoachGlance.make(from: [day("2026-10-01", recovery: 70, hrv: 55),
                                                      day("2026-10-02", recovery: 72, hrv: 57)]))
        XCTAssertNil(g.stats.first { $0.id == "hrv" }?.deltaText)
    }

    func testNoDaysIsNoGlance() { XCTAssertNil(CoachGlance.make(from: [])) }
}
