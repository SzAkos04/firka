import Foundation
import Testing
@testable import Firka

/// What the screens show, computed without SwiftUI.
@Suite("Screens")
struct ScreenLogicTests {
    let monday = budapest(2026, 11, 23)

    @Test("greeting: the first given name (Hungarian order), by time of day", arguments: [
        ("Teszt Elek Ákos", 7, "Jó reggelt, Elek!"),
        ("Teszt Elek", 12, "Szia, Elek!"),
        ("Teszt Elek", 20, "Jó estét, Elek!"),
        ("Teszt Elek", 2, "Jó estét, Elek!"),  // after midnight it isn't morning yet
        ("Teszt Elek", 4, "Jó reggelt, Elek!"),
        ("Elek", 12, "Szia, Elek!"),
        ("", 12, "Firka"),
    ])
    func greeting(_ name: String, _ hour: Int, _ text: String) {
        #expect(HomeLogic.greeting(name: name, hour: hour) == text)
    }

    @Test("home: the lesson now, the next one, and today's list (or the next school day's)")
    func homeDay() {
        let lessons = [lesson("1", day: monday, from: 480), lesson("2", day: monday, from: 535, cancelled: true),
                       lesson("3", day: monday, from: 590), lesson("h", day: monday, from: 645),
                       lesson("e", day: monday, from: 0, event: true), lesson("t", day: monday.adding(days: 1), from: 480)]
        let hidden: (Ora) -> Bool = { $0.uid == "h" }

        let during = HomeLogic.today(lessons, now: monday.addingTimeInterval(490 * 60), isHidden: hidden)
        #expect(during.current?.uid == "1" && during.next?.uid == "3", "the cancelled one isn't next")
        #expect(during.day == monday && during.lessons.map(\.uid) == ["1", "2", "3"], "no events, no hidden lessons")

        let evening = HomeLogic.today(lessons, now: monday.addingTimeInterval(20 * 3600), isHidden: hidden)
        #expect(evening.current == nil && evening.next?.uid == "t")
        #expect(evening.day == monday.adding(days: 1) && evening.lessons.map(\.uid) == ["t"])

        let nothing = HomeLogic.today([], now: monday, isHidden: hidden)
        #expect(nothing.current == nil && nothing.next == nil && nothing.lessons.isEmpty && nothing.day == monday)
    }

    @Test("minutes left in a lesson, rounded up: 45:00 is 45, 44:59 is 45, 30 seconds is 1", arguments: [
        (2700.0, 45), (2699, 45), (2640, 44), (30, 1),
    ])
    func minutesLeft(_ seconds: Double, _ minutes: Int) {
        #expect(HomeLogic.minutesLeft(until: monday.addingTimeInterval(seconds), now: monday) == minutes)
    }

    @Test("homework and tests: upcoming soonest first, past latest first; due today is upcoming")
    func upcomingPast() {
        let dates = [monday.adding(days: -2), monday.adding(days: 3), monday, monday.adding(days: -9), monday.adding(days: 1)]
        let s = HomeLogic.split(dates, today: monday) { $0 }
        #expect(s.upcoming == [monday, monday.adding(days: 1), monday.adding(days: 3)])
        #expect(s.past == [monday.adding(days: -2), monday.adding(days: -9)])
    }

    @Test("absence stats: lateness isn't counted as absence, its minutes add up")
    func absenceStats() throws {
        func a(_ uid: String, _ state: String, late: Int? = nil) -> String {
            #"{"Uid":"\#(uid)","Tantargy":\#(subjectJSON),"Datum":"2025-11-09T23:00:00Z","IgazolasAllapota":"\#(state)","KesesPercben":\#(late.map(String.init) ?? "null"),"Tipus":{"Nev":"\#(late == nil ? "hianyzas" : "keses")"}}"#
        }
        let list: [Mulasztas] = try decode("[" + [a("1", "Igazolt"), a("2", "Igazolt"), a("3", "Igazolatlan"), a("4", "Igazolando"),
                                                   a("5", "Igazolt", late: 5), a("6", "Igazolatlan", late: 12)].joined(separator: ",") + "]")
        let s = AbsenceStats(list)
        #expect(s.justified == 2 && s.unjustified == 1 && s.pending == 1 && s.lateMinutes == 17)
    }

    @Test("class average: only over the subjects you have grades in")
    func classOverall() throws {
        let g = try grades(gradeJSON("a", 5, 100))
        #expect(GradesLogic.classOverall(g, averages: ["1,MAT": 4.0, "2,TOR": 2.0]) == 4.0)
        #expect(GradesLogic.classOverall(g, averages: ["2,TOR": 2.0]) == nil)
        #expect(GradesLogic.classOverall(g, averages: nil) == nil)
    }

    @Test("subjects in KRÉTA's order, then by name")
    func subjectOrder() throws {
        let tor = historyJSON  // SortIndex 1
        let ang = #"{"Uid":"3,ANG","Nev":"angol","SortIndex":1}"#
        let g = try grades(gradeJSON("t", 4, 100, subject: tor), gradeJSON("m", 5, 100), gradeJSON("a", 3, 100, subject: ang))
        #expect(GradesLogic.subjects(g).map(\.subject.nev) == ["matematika", "angol", "történelem"])
    }

    @Test("a subject's grade count: the ones in its average, like the overall \"N jegy alapján\"")
    func subjectGradeCount() throws {
        let g = try grades(gradeJSON("a", 5, 100), gradeJSON("b", 3, 200),
                           gradeJSON("c", nil, nil, valueType: "Szoveges", text: "Nem írt"),  // a text grade isn't counted
                           gradeJSON("d", 4, nil, kind: "felevi_jegy_ertekeles"),            // nor the half-year grade
                           gradeJSON("t", 4, 100, subject: historyJSON))
        #expect(GradesLogic.subjects(g).map(\.grades.countedInAverage) == [2, 1])
    }

    @Test("report card column average; nothing yet is a dash")
    func columnAverage() {
        #expect(GradesLogic.columnAverage([5, 4, nil, 4]) == "4,33")
        #expect(GradesLogic.columnAverage([nil, nil]) == "–")
    }

    @Test("grade details: topic, mode, weight only when it adds something")
    func gradeDetails() throws {
        let g = try grades(gradeJSON("a", 5, 200), gradeJSON("b", 5, 100), gradeJSON("c", 5, 50))
        #expect(g[0].details == "Törtek · Írásbeli röpdolgozat · 200%")
        #expect(g[1].details == "Törtek · Írásbeli röpdolgozat")
        var c = g[2]
        c.mod?.leiras = "Szóbeli felelet 50%"
        c.tema = nil
        #expect(c.details == "Szóbeli felelet 50%", "KRÉTA already wrote the weight into the mode")
    }

    @Test("hidden lesson rules described in Hungarian")
    func hideRuleText() {
        let l = lesson("x", day: monday, from: 480, number: 3)
        #expect(HideRule(.once, for: l).summary == "Csak nov. 23. · 3. óra")
        #expect(HideRule(.weekly, for: l).summary == "Minden hétfő · 3. óra")
        #expect(HideRule(.subject, for: l).summary == "A tantárgy összes órája")
        #expect(HideRule(.weekly, for: lesson("y", day: monday, from: 480, number: nil)).summary == "Minden hétfő · 08:00")
    }

    @Test("login: the code from KRÉTA's redirect, only for our own login (state), nothing from other pages")
    func loginCode() {
        let redirect = "https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect"
        #expect(Kreta.code(fromRedirect: URL(string: redirect + "?code=AB12&state=x")!, state: "x") == "AB12")
        #expect(Kreta.code(fromRedirect: URL(string: redirect + "?code=AB12&state=y")!, state: "x") == nil, "a code from another login attempt")
        #expect(Kreta.code(fromRedirect: URL(string: redirect + "?code=AB12")!, state: "x") == nil, "no state: not our login")
        #expect(Kreta.code(fromRedirect: URL(string: redirect + "?error=access_denied&state=x")!, state: "x") == nil)
        #expect(Kreta.code(fromRedirect: URL(string: "https://idp.e-kreta.hu/Account/Login?code=AB12&state=x")!, state: "x") == nil)
        #expect(Kreta.isRedirect(URL(string: "https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect?error=x")!))
    }

    @Test("the login page failing to load is an error to show; our own cancelled redirect isn't")
    func loginPageFailure() {
        #expect(LoginWebView.isLoadFailure(URLError(.notConnectedToInternet)))
        #expect(LoginWebView.isLoadFailure(URLError(.secureConnectionFailed)))
        #expect(!LoginWebView.isLoadFailure(URLError(.cancelled)))
        #expect(!LoginWebView.isLoadFailure(NSError(domain: "WebKitErrorDomain", code: 102)), "the redirect we stop ourselves")
    }

    @Test("a lesson is on now only between its start and end, and not when it's cancelled")
    func lessonOnNow() {
        let day = budapest(2026, 11, 23)
        let l = lesson("a", day: day, from: 8 * 60)
        #expect(l.isOn(at: budapest(2026, 11, 23, 8, 10)))
        #expect(!l.isOn(at: budapest(2026, 11, 23, 8, 45)) && !l.isOn(at: budapest(2026, 11, 23, 7, 59)))
        #expect(!lesson("b", day: day, from: 8 * 60, cancelled: true).isOn(at: budapest(2026, 11, 23, 8, 10)))
    }

    @Test("rename screen: every subject and teacher once, Hungarian order; search finds own names too")
    func renameNames() throws {
        var d = Snapshot()
        d.grades = try grades(gradeJSON("a", 5, 100), gradeJSON("b", 4, 100, subject: historyJSON))
        d.lessons = [lesson("l", day: monday, from: 480, substitute: "Ács Béla")]
        let n = Renames.names(in: d)
        #expect(n.subjects == ["Matematika", "Történelem"])
        #expect(n.teachers == ["Ács Béla", "Kovács Anna"])
        #expect(Renames.matches("Matematika", search: "", custom: nil))
        #expect(Renames.matches("Matematika", search: "mat", custom: nil))
        #expect(Renames.matches("Matematika", search: "Matek", custom: "Matek"))
        #expect(!Renames.matches("Matematika", search: "töri", custom: nil))
    }

    @Test("attachment icons by extension, any case", arguments: [
        ("a.PDF", "doc.richtext"), ("b.docx", "doc.text"), ("c.xlsx", "tablecells"), ("d.pptx", "rectangle.on.rectangle"),
        ("e.HEIC", "photo"), ("f.mp4", "film"), ("g.zip", "doc.zipper"), ("noext", "doc"),
    ])
    func icons(_ name: String, _ icon: String) {
        #expect(AttachmentList.icon(name) == icon)
    }
}
