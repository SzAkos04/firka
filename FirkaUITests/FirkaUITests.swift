import XCTest

/// The real app, tapped through in demo mode (fake data, no KRÉTA account, no network).
/// Catches what unit tests can't: a screen that crashes, a button that does nothing, wrong navigation.
@MainActor
final class FirkaUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["FIRKA_DEMO"] = "1"  // fresh demo data on every launch
        app.launch()
    }

    private func tab(_ name: String) { app.tabBars.buttons[name].firstMatch.tap() }
    private var weekTitle: XCUIElement { app.staticTexts["weekTitle"] }

    /// Lists animate: wait until the query has `n` matches. Checks right away first, since XCTest's
    /// predicate waits look only once a second.
    private func wait(_ q: XCUIElementQuery, count op: String, _ n: Int, _ message: String = "") {
        let p = NSPredicate(format: "count \(op) \(n)")
        if p.evaluate(with: q) { return }
        let e = expectation(for: p, evaluatedWith: q)
        e.expectationDescription = message
        wait(for: [e], timeout: 5)
    }

    /// `waitForExistence`, but without its first second of waiting when the element is already there.
    private func shows(_ e: XCUIElement, timeout: TimeInterval = 3) -> Bool { e.exists || e.waitForExistence(timeout: timeout) }

    func testEveryTabOpens() {
        XCTAssertTrue(app.staticTexts["Szia, Elek!"].exists || app.staticTexts["Jó reggelt, Elek!"].exists || app.staticTexts["Jó estét, Elek!"].exists)
        tab("Órarend")
        XCTAssertTrue(shows(weekTitle))
        tab("Jegyek")
        for _ in 0..<3 where !app.buttons["Tantárgyak"].exists { app.swipeUp(velocity: .slow) }  // the picker is under the summary
        XCTAssertTrue(shows(app.buttons["Tantárgyak"]))
        tab("Hiányzások")
        XCTAssertTrue(shows(app.staticTexts["Késés, perc"]))
        tab("Egyebek")
        XCTAssertTrue(shows(app.buttons["Beállítások"]))
    }

    /// Text must stand out from its background in light and dark mode alike (a colour that only works on one of them
    /// is invisible on the other). iOS's own accessibility audit measures it on every main screen.
    func testContrastInLightAndDarkMode() throws {
        addTeardownBlock { XCUIDevice.shared.appearance = .light }  // the simulator keeps it: leave it as the other tests expect
        relaunch(["FIRKA_DEMO": "reportCard"])  // with half-year grades, so the report card is there to check
        let gradesPicker = { for _ in 0..<4 where !self.app.buttons["Legutóbbiak"].exists { self.app.swipeUp(velocity: .slow) } }
        // name, how to get there, how to leave it as the next one expects
        let screens: [(String, () -> Void, () -> Void)] = [
            ("Kezdőlap", { self.tab("Kezdőlap") }, {}),
            ("Órarend", { self.tab("Órarend") }, {}),
            ("Órarend, hónap", { self.tab("Órarend"); self.app.buttons["Hónap"].tap() }, { self.app.buttons["Hét"].tap() }),
            ("Jegyek", { self.tab("Jegyek") }, {}),
            ("Bizonyítvány", { self.tab("Jegyek"); gradesPicker(); self.app.buttons["Bizonyítvány"].tap(); self.app.swipeDown(); self.app.swipeDown() },
             { gradesPicker(); self.app.buttons["Tantárgyak"].firstMatch.tap(); self.app.swipeDown(); self.app.swipeDown() }),
            ("Matematika", { self.openMath() }, { self.tab("Jegyek") }),
            ("Hiányzások", { self.tab("Hiányzások") }, {}),
            ("Hiányzások, tantárgyak", { self.tab("Hiányzások"); self.app.buttons["Tantárgyak"].tap() }, { self.app.buttons["Mind"].tap() }),
            ("Egyebek", { self.tab("Egyebek") }, {}),
            ("Beállítások", { self.tab("Egyebek"); self.app.buttons["Beállítások"].tap() }, { self.tab("Egyebek") }),
        ]
        var found: [String] = []
        for mode in [XCUIDevice.Appearance.light, .dark] {
            XCUIDevice.shared.appearance = mode
            for (screen, open, leave) in screens {
                open()
                defer { leave() }
                Thread.sleep(forTimeInterval: 1)  // let a scroll and the large title settle
                let tabBar = app.tabBars.firstMatch.frame.insetBy(dx: 0, dy: -60)  // with the fade above it
                let barBottom = app.navigationBars.firstMatch.frame.maxY  // rows scrolled up under it or the status bar
                try app.performAccessibilityAudit(for: .contrast) { issue in
                    // Not ours to fix: iOS's own secondary greys ("nearly passed"), disabled controls (meant to be faint),
                    // rows scrolled under the see-through tab bar or into the fade above it.
                    let ignore = issue.compactDescription.contains("nearly") || issue.element?.isEnabled == false
                        || issue.element.map { $0.frame.intersects(tabBar) || $0.frame.minY < barBottom } == true
                    if !ignore {
                        found.append("\(mode == .dark ? "sötét" : "világos") · \(screen): \(issue.element?.label ?? "?") – \(issue.compactDescription)")
                    }
                    return true  // collect all of them, report below
                }
            }
        }
        XCTAssertTrue(found.isEmpty, "low contrast:\n" + found.joined(separator: "\n"))
    }

    /// Changing weeks selects Monday (today's week: today); "Ma" goes back to where the timetable opened, and is off there.
    func testWeekChangeSelectsMondayAndMaGoesBack() {
        tab("Órarend")
        XCTAssertTrue(shows(weekTitle))
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

    /// The week arrows sit by the title, not above Monday and Friday, so a thumb doesn't hit the wrong one.
    func testWeekArrowsAreAwayFromTheEdgeDays() {
        tab("Órarend")
        XCTAssertTrue(shows(weekTitle))
        let days = app.buttons.matching(identifier: "day")
        let first = days.element(boundBy: 0).frame, last = days.element(boundBy: days.count - 1).frame
        let prev = app.buttons["previousWeek"].frame, next = app.buttons["nextWeek"].frame
        XCTAssertGreaterThan(prev.midX, first.maxX, "the back arrow isn't above Monday")
        XCTAssertLessThan(next.midX, last.minX, "the forward arrow isn't above the last day")
        XCTAssertLessThanOrEqual(max(prev.maxY, next.maxY), first.minY, "the arrows don't reach into the day strip")
        for f in [prev, next] { XCTAssertGreaterThanOrEqual(min(f.width, f.height), 44, "a full-size tap target") }
    }

    /// The lessons start right under the day strip, no empty band between them.
    func testLessonsSitUnderTheDayStrip() {
        tab("Órarend")
        let row = app.buttons.matching(identifier: "lessonRow").firstMatch
        if !shows(row) { app.buttons["nextWeek"].tap() }
        XCTAssertTrue(shows(row))
        let gap = row.frame.minY - app.buttons.matching(identifier: "day").firstMatch.frame.maxY
        XCTAssertLessThanOrEqual(gap, 24, "gap under the strip: \(gap) pt")
    }

    func testAnnouncedTestInTheDayList() {
        tab("Órarend")
        XCTAssertTrue(shows(weekTitle))
        // the demo's test is on Thursday of this week; on a free weekend the timetable opens on the next one
        if Calendar.current.isDateInWeekend(Date()) { app.buttons["previousWeek"].tap() }
        app.buttons.matching(identifier: "day").element(boundBy: 3).tap()
        XCTAssertTrue(shows(app.staticTexts["Írásbeli témazáró · Az Árpád-kor"]), "the day's test, not only a dot on the strip")
    }

    func testAbsenceFilterDetailAndSubjects() {
        tab("Hiányzások")
        app.buttons["Igazolandó"].tap()
        let rows = app.buttons.matching(identifier: "absenceRow")
        XCTAssertTrue(shows(rows.firstMatch))
        XCTAssertEqual(rows.count, 1, "only the one to excuse")
        rows.firstMatch.tap()
        XCTAssertTrue(shows(app.staticTexts["Rögzítette"]), "the detail says who recorded it")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Tantárgyak"].tap()
        XCTAssertTrue(shows(app.staticTexts.matching(identifier: "absenceSubject").firstMatch))
    }

    /// The largest text sizes: fixed widths grow with the text instead of squeezing it.
    func testLargeTextGrowsTheWeekTitle() {
        let normal = weekTitleWidth()
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        XCTAssertGreaterThan(weekTitleWidth(), normal * 1.3)
        XCTAssertTrue(app.buttons["nextWeek"].isHittable && app.buttons["previousWeek"].isHittable, "the arrows stay on screen")
    }

    private func weekTitleWidth() -> CGFloat {
        tab("Órarend")
        XCTAssertTrue(shows(weekTitle))
        return weekTitle.frame.width
    }

    func testMonthViewAndBack() {
        tab("Órarend")
        app.buttons["Hónap"].tap()
        XCTAssertFalse(weekTitle.exists)
        let ma = app.navigationBars.buttons["Ma"]
        XCTAssertFalse(ma.isEnabled, "already on today, like the week view")
        app.buttons["Következő hónap"].tap()
        XCTAssertTrue(ma.isEnabled)
        app.buttons["Előző hónap"].tap()
        app.buttons["Előző hónap"].tap()
        ma.tap()
        XCTAssertFalse(ma.isEnabled)
        app.buttons["Hét"].tap()
        XCTAssertTrue(shows(weekTitle))
    }

    func testLiveActivitySwitchFlips() {
        tab("Egyebek")
        app.buttons["Beállítások"].tap()
        let toggle = app.switches["Mai órák a zárolt képernyőn"]
        XCTAssertTrue(shows(toggle))
        let before = toggle.value as? String
        toggle.switches.firstMatch.tap()
        XCTAssertNotEqual(toggle.value as? String, before, "the switch shows the new setting")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, before)
    }

    /// A launch with something extra in the environment (FIRKA_DEMO variants, the push server's address).
    private func relaunch(_ env: [String: String]) {
        app.terminate()
        app.launchEnvironment.merge(env) { $1 }
        app.launch()
    }

    func testReportCard() {
        relaunch(["FIRKA_DEMO": "reportCard"])
        tab("Jegyek")
        let card = app.buttons["Bizonyítvány"]
        for _ in 0..<4 where !card.exists { app.swipeUp(velocity: .slow) }  // the picker sits under the chart
        card.tap()
        XCTAssertTrue(shows(app.staticTexts["Félév"]))
        XCTAssertTrue(shows(app.staticTexts["Év vége"]))
    }

    func testLessonHomeworkAndTestDetails() {
        tab("Órarend")
        let row = app.buttons.matching(identifier: "lessonRow").firstMatch
        if !shows(row) { app.buttons["nextWeek"].tap() }
        row.tap()
        XCTAssertTrue(shows(app.staticTexts["Időpont"]), "lesson detail")
        tab("Egyebek")
        app.buttons["Házi feladatok"].tap()
        app.staticTexts["Matematika"].firstMatch.tap()
        XCTAssertTrue(shows(app.staticTexts["Feladva"]), "homework detail")
        tab("Egyebek")
        app.buttons["Számonkérések"].tap()
        app.staticTexts["Írásbeli témazáró · Az Árpád-kor"].tap()
        XCTAssertTrue(shows(app.staticTexts["Mód"]), "test detail")
    }

    func testServerNotificationSettings() {
        relaunch(["FIRKA_PUSH_SERVER": "https://push.invalid"])
        tab("Egyebek")
        app.buttons["Beállítások"].tap()
        let toggle = app.switches["serverPushToggle"]
        XCTAssertTrue(shows(toggle), "shown only when the app has a server's address")
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.tap() }
        XCTAssertTrue(shows(app.staticTexts["A szerver nem érhető el (Tailscale be van kapcsolva?)"]), "no server there")
        app.buttons["serverPushTest"].tap()
        XCTAssertTrue(shows(app.staticTexts["Nem sikerült elküldeni (Tailscale be van kapcsolva?)"]))
        toggle.switches.firstMatch.tap()  // off again: the setting outlives the launch
        XCTAssertFalse(app.buttons["serverPushTest"].exists)
    }

    func testSurpriseGradesReveal() {
        let hidden = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'jegy, rejtve'"))
        XCTAssertEqual(hidden.count, 3, "demo mode leaves the 3 newest grades as surprises")
        hidden.firstMatch.tap()
        XCTAssertEqual(hidden.count, 2)
        app.buttons["Mind felfedése"].tap()
        wait(hidden, count: "==", 0, "all revealed")
    }

    /// Jegyek › Matematika.
    private func openMath() {
        tab("Jegyek")
        let math = app.buttons.matching(NSPredicate(format: "label CONTAINS ', Matematika,'")).firstMatch  // "4,00, Matematika, 5, 5…"
        for _ in 0..<5 where !(math.exists && math.isHittable) { app.swipeUp(velocity: .slow) }  // under the summary; slow: no fling to wait out
        math.tap()
        XCTAssertTrue(shows(app.navigationBars["Matematika"]))
    }

    /// The subject page with the class average (the demo), and without one (a school that hides them): still works.
    func testSubjectWithAndWithoutClassAverage() {
        openMath()
        let classAverage = app.descendants(matching: .any)["subjectClassAverage"]
        XCTAssertTrue(shows(classAverage), "the class average next to yours")
        XCTAssertTrue(app.staticTexts["Jegyek száma"].exists)
        app.terminate()
        app.launchEnvironment["FIRKA_DEMO"] = "noClassAverages"
        app.launch()
        openMath()
        XCTAssertTrue(shows(app.staticTexts["Jegyek száma"]), "the page is all there")
        XCTAssertFalse(classAverage.exists, "no class average row")
    }

    func testSubjectAndGradeDetail() {
        tab("Jegyek")
        let picker = app.buttons["Legutóbbiak"]
        for _ in 0..<4 where !picker.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(picker.exists)
        XCTAssertFalse(app.buttons["Bizonyítvány"].exists, "no term grades in the demo: no report card tab")
        tab("Kezdőlap")
        openMath()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Témazáró'")).firstMatch.tap()
        XCTAssertTrue(shows(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Kovács Anna'")).firstMatch),
                      "the grade's teacher on the detail screen")
    }

    func testWhatIfWithAWeightAndRemovingOne() {
        openMath()
        let weight = app.buttons["200%"]
        for _ in 0..<4 where !weight.isHittable { app.swipeUp() }
        weight.tap()
        app.buttons["whatIf5"].tap()
        app.buttons["300%"].tap()
        app.buttons["whatIf1"].tap()
        let chips = app.buttons.matching(identifier: "whatIfChip")
        XCTAssertEqual(chips.count, 2)
        XCTAssertTrue(chips.firstMatch.label.contains("200%"))
        chips.firstMatch.tap()
        XCTAssertEqual(chips.count, 1, "a tapped grade goes, the other stays")
        XCTAssertTrue(chips.firstMatch.label.contains("300%"))
    }

    func testHideALessonAndShowItAgain() {
        tab("Órarend")
        let rows = app.buttons.matching(identifier: "lessonRow")
        if !shows(rows.firstMatch) { app.buttons["nextWeek"].tap() }  // a free day: use next week's Monday
        let row = rows.firstMatch
        XCTAssertTrue(shows(row))
        let before = rows.count
        row.press(forDuration: 0.6)
        app.buttons["Elrejtés…"].tap()
        app.buttons["A tantárgy összes órája"].tap()
        wait(rows, count: "==", before - 1, "the subject's lesson disappears")
        tab("Egyebek")
        app.buttons["Elrejtett órák"].tap()
        XCTAssertTrue(shows(app.staticTexts["A tantárgy összes órája"]))
        app.cells.firstMatch.swipeLeft()
        app.buttons.matching(NSPredicate(format: "label IN {'Delete', 'Törlés'}")).firstMatch.tap()
        tab("Órarend")
        wait(rows, count: "==", before, "shown again")
    }

    func testMessagesHomeworkAndTests() {
        tab("Egyebek")
        app.buttons["Üzenetek, feljegyzések"].tap()
        app.staticTexts["Szalagavató próba"].tap()
        XCTAssertTrue(shows(app.staticTexts["Pénteken 14:00-tól próba a tornateremben."]))
        tab("Egyebek")  // tapping the open tab goes back to its start
        app.buttons["Házi feladatok"].tap()
        XCTAssertTrue(shows(app.staticTexts["Matematika"]), "the demo homework")
        XCTAssertTrue(shows(app.staticTexts["Megoldva"]), "the solved one says so")
        tab("Egyebek")
        app.buttons["Számonkérések"].tap()
        XCTAssertTrue(shows(app.staticTexts["Írásbeli témazáró · Az Árpád-kor"]))
    }

    func testMessagesUnreadFilterAndSearch() {
        tab("Egyebek")
        app.buttons["Üzenetek, feljegyzések"].tap()
        XCTAssertTrue(shows(app.staticTexts["Szülői értekezlet"]))
        XCTAssertTrue(app.descendants(matching: .any)["Olvasatlan"].exists, "the unread teacher message is marked")
        app.buttons["Faliújság"].tap()
        XCTAssertTrue(shows(app.staticTexts["Szalagavató próba"]))
        XCTAssertFalse(app.staticTexts["Szülői értekezlet"].exists)
        app.buttons["Mind"].tap()
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        search.tap()
        search.typeText("fizika")
        XCTAssertTrue(shows(app.staticTexts["Dicséret"]), "found in the note's text")
        XCTAssertFalse(app.staticTexts["Szalagavató próba"].exists)
    }

    func testRenameASubject() {
        tab("Egyebek")
        app.buttons["Tantárgyak, tanárok átnevezése"].tap()
        let field = app.textFields["Matematika"]
        XCTAssertTrue(shows(field))
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
        XCTAssertTrue(shows(app.buttons["Bejelentkezés"]))
    }
}
