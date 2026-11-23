import XCTest

/// The real app, tapped through in demo mode (fake data, no KRÉTA account, no network).
/// Catches what unit tests can't: a screen that crashes, a button that does nothing, wrong navigation.
final class FirkaUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["FIRKA_DEMO"] = "1"  // fresh demo data on every launch
        app.launch()
    }

    private func tab(_ name: String) { app.tabBars.buttons[name].firstMatch.tap() }
    private var weekTitle: XCUIElement { app.staticTexts["weekTitle"] }

    /// Lists animate: wait until the query has `n` matches.
    private func wait(_ q: XCUIElementQuery, count op: String, _ n: Int, _ message: String = "") {
        let e = expectation(for: NSPredicate(format: "count \(op) \(n)"), evaluatedWith: q)
        e.expectationDescription = message
        wait(for: [e], timeout: 5)
    }

    func testEveryTabOpens() {
        XCTAssertTrue(app.staticTexts["Szia, Elek!"].exists || app.staticTexts["Jó reggelt, Elek!"].exists || app.staticTexts["Jó estét, Elek!"].exists)
        tab("Órarend")
        XCTAssertTrue(weekTitle.waitForExistence(timeout: 3))
        tab("Jegyek")
        XCTAssertTrue(app.buttons["Tantárgyak"].waitForExistence(timeout: 3))
        tab("Hiányzások")
        XCTAssertTrue(app.staticTexts["Késés, perc"].waitForExistence(timeout: 3))
        tab("Egyebek")
        XCTAssertTrue(app.buttons["Beállítások"].waitForExistence(timeout: 3))
    }

    /// Changing weeks selects Monday (today's week: today); "Ma" goes back to where the timetable opened, and is off there.
    func testWeekChangeSelectsMondayAndMaGoesBack() {
        tab("Órarend")
        XCTAssertTrue(weekTitle.waitForExistence(timeout: 3))
        let opening = weekTitle.label
        let ma = app.navigationBars.buttons["Ma"]
        let days = app.buttons.matching(identifier: "day")
        var selected: String? { days.allElementsBoundByIndex.first { $0.isSelected }?.label }
        let openingDay = selected
        XCTAssertFalse(ma.isEnabled, "already where Ma leads")
        XCTAssertEqual(days.count, 5)

        days.element(boundBy: 2).tap()
        XCTAssertTrue(selected?.contains("szerda") == true)
        XCTAssertTrue(ma.isEnabled)
        app.buttons["nextWeek"].tap()
        XCTAssertNotEqual(weekTitle.label, opening)
        XCTAssertTrue(selected?.contains("hétfő") == true, "a new week starts on Monday")
        app.buttons["previousWeek"].tap()
        XCTAssertEqual(weekTitle.label, opening)
        XCTAssertEqual(selected, openingDay, "back on today's week: today")
        app.buttons["previousWeek"].tap()
        XCTAssertTrue(selected?.contains("hétfő") == true)

        ma.tap()
        XCTAssertEqual(weekTitle.label, opening)
        XCTAssertEqual(selected, openingDay)
        XCTAssertFalse(ma.isEnabled)
    }

    /// The lessons start right under the day strip, no empty band between them.
    func testLessonsSitUnderTheDayStrip() {
        tab("Órarend")
        let row = app.buttons.matching(identifier: "lessonRow").firstMatch
        if !row.waitForExistence(timeout: 3) { app.buttons["nextWeek"].tap() }
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let gap = row.frame.minY - app.buttons.matching(identifier: "day").firstMatch.frame.maxY
        XCTAssertLessThanOrEqual(gap, 24, "gap under the strip: \(gap) pt")
    }

    func testMonthViewAndBack() {
        tab("Órarend")
        app.buttons["Hónap"].tap()
        XCTAssertFalse(weekTitle.exists)
        app.buttons["Hét"].tap()
        XCTAssertTrue(weekTitle.waitForExistence(timeout: 3))
    }

    func testSurpriseGradesReveal() {
        let hidden = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'jegy, rejtve'"))
        XCTAssertEqual(hidden.count, 3, "demo mode leaves the 3 newest grades as surprises")
        hidden.firstMatch.tap()
        XCTAssertEqual(hidden.count, 2)
        app.buttons["Mind felfedése"].tap()
        let gone = NSPredicate(format: "count == 0")
        expectation(for: gone, evaluatedWith: hidden)
        waitForExpectations(timeout: 3)
    }

    func testSubjectAndGradeDetail() {
        tab("Jegyek")
        XCTAssertFalse(app.buttons["Bizonyítvány"].exists, "no term grades in the demo: no report card tab")
        let math = app.buttons.matching(NSPredicate(format: "label CONTAINS ', Matematika,'")).firstMatch  // "4,00, Matematika, 5, 5…"
        for _ in 0..<5 where !math.isHittable { app.swipeUp() }  // the subjects are under the summary
        math.tap()
        XCTAssertTrue(app.navigationBars["Matematika"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Témazáró'")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Kovács Anna'")).firstMatch
            .waitForExistence(timeout: 3), "the grade's teacher on the detail screen")
    }

    func testHideALessonAndShowItAgain() {
        tab("Órarend")
        let rows = app.buttons.matching(identifier: "lessonRow")
        if !rows.firstMatch.waitForExistence(timeout: 3) { app.buttons["nextWeek"].tap() }  // a free day: use next week's Monday
        let row = rows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let before = rows.count
        row.press(forDuration: 1)
        app.buttons["Elrejtés…"].tap()
        app.buttons["A tantárgy összes órája"].tap()
        wait(rows, count: "==", before - 1, "the subject's lesson disappears")
        tab("Egyebek")
        app.buttons["Elrejtett órák"].tap()
        XCTAssertTrue(app.staticTexts["A tantárgy összes órája"].waitForExistence(timeout: 3))
        app.cells.firstMatch.swipeLeft()
        app.buttons.matching(NSPredicate(format: "label IN {'Delete', 'Törlés'}")).firstMatch.tap()
        tab("Órarend")
        wait(rows, count: "==", before, "shown again")
    }

    func testMessagesHomeworkAndTests() {
        tab("Egyebek")
        app.buttons["Üzenetek, feljegyzések"].tap()
        app.staticTexts["Szalagavató próba"].tap()
        XCTAssertTrue(app.staticTexts["Pénteken 14:00-tól próba a tornateremben."].waitForExistence(timeout: 3))
        tab("Egyebek")  // tapping the open tab goes back to its start
        app.buttons["Házi feladatok"].tap()
        XCTAssertTrue(app.staticTexts["Matematika"].waitForExistence(timeout: 3), "the demo homework")
        tab("Egyebek")
        app.buttons["Számonkérések"].tap()
        XCTAssertTrue(app.staticTexts["Írásbeli témazáró · Az Árpád-kor"].waitForExistence(timeout: 3))
    }

    func testRenameASubject() {
        tab("Egyebek")
        app.buttons["Tantárgyak, tanárok átnevezése"].tap()
        let field = app.textFields["Matematika"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Matek")
        tab("Jegyek")
        let renamed = app.buttons.matching(NSPredicate(format: "label CONTAINS ', Matek,'")).firstMatch
        for _ in 0..<5 where !renamed.exists { app.swipeUp() }
        XCTAssertTrue(renamed.exists, "the new name shows up on the grades screen")
    }

    func testLogoutGoesToLogin() {
        tab("Egyebek")
        app.buttons["Beállítások"].tap()
        app.swipeUp()
        app.buttons["Kijelentkezés"].firstMatch.tap()
        app.alerts.buttons["Kijelentkezés"].tap()
        XCTAssertTrue(app.buttons["Bejelentkezés"].waitForExistence(timeout: 3))
    }
}
