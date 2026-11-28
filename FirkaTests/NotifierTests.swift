import Foundation
import Testing
import UIKit
import UserNotifications
@testable import Firka

@Suite("Notifications: what counts as new")
struct NotifierTests {
    let now = budapest(2026, 11, 23, 7)

    func snapshot(grades g: [Grade] = [], lessons: [Lesson] = [], name: String = "Teszt Elek", synced: Bool = true) -> Snapshot {
        var s = Snapshot()
        s.studentName = name
        s.grades = g
        s.lessons = lessons
        s.messageSources = ["n", "f", "p"]
        s.updated = synced ? now : nil
        return s
    }

    func changes(_ old: Snapshot, _ new: Snapshot, surprise: Bool = true, off: Set<String> = [], hidden: Set<String> = []) -> [Notifier.Alert] {
        Notifier.changes(old: old, new: new, now: now, enabled: { !off.contains($0) }, surprise: surprise,
                         isHidden: { hidden.contains($0.id) })
    }

    @Test func newGradeKeepsTheSurprise() throws {
        let old = snapshot(grades: try grades(gradeJSON("a", 4, 100)))
        let new = snapshot(grades: try grades(gradeJSON("a", 4, 100), gradeJSON("b", 5, 100)))
        #expect(changes(old, new) == [Notifier.Alert(id: "grades", title: "Új jegy érkezett", lines: ["Matematika: új jegy"])])
        #expect(changes(old, new, surprise: false).first?.lines == ["Matematika: 5"])
        #expect(changes(old, new, off: ["notifyGrades"]).isEmpty)
    }

    @Test("first sync after login or an account switch: nothing")
    func noBaseline() throws {
        let new = snapshot(grades: try grades(gradeJSON("b", 5, 100)))
        #expect(changes(snapshot(synced: false), new).isEmpty)
        #expect(changes(snapshot(name: "Más Valaki"), new).isEmpty)
    }

    @Test("after an empty response, a full list is a new baseline, not 20 notifications")
    func emptyThenFull() throws {
        let full = snapshot(grades: try (1...6).map { try grades(gradeJSON("g\($0)", 5, 100))[0] })
        #expect(changes(snapshot(), full).isEmpty)
    }

    @Test func manyGradesAreCappedAtFiveLines() throws {
        let old = snapshot(grades: try grades(gradeJSON("x", 3, 100)))
        let new = snapshot(grades: old.grades + (try (1...7).map { try grades(gradeJSON("g\($0)", 5, 100))[0] }))
        let a = try #require(changes(old, new).first)
        #expect(a.title == "7 új jegy érkezett" && a.lines.count == 5)
    }

    @Test("cancelled lessons: only new, future, not hidden")
    func cancelled() {
        let day = budapest(2026, 11, 23)
        let old = snapshot(lessons: [lesson("a", day: day, from: 480), lesson("b", day: day, from: 540, cancelled: true)])
        let new = snapshot(lessons: [
            lesson("a", day: day, from: 480, cancelled: true),              // newly cancelled → yes
            lesson("b", day: day, from: 540, cancelled: true),              // already known → no
            lesson("p", day: budapest(2026, 11, 20), from: 480, cancelled: true),  // in the past → no
            lesson("h", day: day, from: 600, cancelled: true),              // hidden by the user → no
        ])
        let a = changes(old, new, hidden: ["h"])
        #expect(a.map(\.id) == ["cancelled"] && a[0].lines.count == 1 && a[0].lines[0].hasPrefix("Matematika"))
    }

    @Test func substitution() {
        let day = budapest(2026, 11, 23)
        let old = snapshot(lessons: [lesson("a", day: day, from: 480)])
        let new = snapshot(lessons: [lesson("a", day: day, from: 480, substitute: "Fekete Lili")])
        #expect(changes(old, new).first?.lines.first?.contains("Fekete Lili") == true)
    }

    @Test("an absence the school turns unexcused is news; turning excused isn't")
    func absenceTurnsUnexcused() throws {
        func absence(_ uid: String, _ state: String) throws -> Absence {
            try absences(#"[{"Uid":"\#(uid)","Tantargy":\#(subjectJSON),"Datum":"2026-11-16T23:00:00Z","IgazolasAllapota":"\#(state)"}]"#)[0]
        }
        var old = snapshot(), new = snapshot()
        old.absences = [try absence("a", "Igazolando"), try absence("b", "Igazolando"), try absence("c", "Igazolatlan")]
        new.absences = [try absence("a", "Igazolatlan"), try absence("b", "Igazolt"), try absence("c", "Igazolatlan")]
        #expect(changes(old, new) == [Notifier.Alert(id: "unexcused", title: "Igazolatlan lett", lines: ["Matematika: Igazolatlan hiányzás"])])
        #expect(changes(old, new, off: ["notifyAbsences"]).isEmpty)
    }

    @Test("another substitute teacher on the same lesson is news; the same one again isn't")
    func substituteChanges() {
        let day = budapest(2026, 11, 23)
        let old = snapshot(lessons: [lesson("a", day: day, from: 480, substitute: "Fekete Lili"), lesson("b", day: day, from: 540, substitute: "Kiss Ede")])
        let new = snapshot(lessons: [lesson("a", day: day, from: 480, substitute: "Nagy Béla"), lesson("b", day: day, from: 540, substitute: "Kiss Ede")])
        let a = changes(old, new)
        #expect(a.map(\.id) == ["substituted"] && a[0].lines.count == 1 && a[0].lines[0].contains("Nagy Béla"))
    }

    @Test("a grade the teacher corrects is news (its value only without surprise grades)")
    func gradeEdited() throws {
        let old = snapshot(grades: try grades(gradeJSON("a", 3, 100), gradeJSON("b", 5, 100)))
        let new = snapshot(grades: try grades(gradeJSON("a", 4, 100), gradeJSON("b", 5, 100)))
        #expect(changes(old, new) == [Notifier.Alert(id: "edited", title: "Módosult egy jegy", lines: ["Matematika: módosult"])])
        #expect(changes(old, new, surprise: false).first?.lines == ["Matematika: 3 → 4"])
        #expect(changes(old, new, off: ["notifyGrades"]).isEmpty)
    }

    @Test("the first sync that has teacher messages doesn't announce years of them")
    func inboxBaseline() throws {
        var old = snapshot()
        old.messageSources = ["n", "f"]
        var new = snapshot()
        new.messageList = try inbox(#"[{"azonosito":1,"tipus":{"kod":"BEERKEZETT"},"uzenet":{"azonosito":1,"kuldesDatum":"2026-11-18T09:50:50","targy":"Régi"}}]"#)
        #expect(changes(old, new).isEmpty)
    }

    @Test("why notifications can't arrive, if something blocks them")
    func blocked() {
        let ok = Notifier.blocker(auth: .authorized, refresh: .available, lowPower: false)
        #expect(ok == nil)
        #expect(Notifier.blocker(auth: .denied, refresh: .available, lowPower: false)?.contains("ki vannak kapcsolva") == true)
        #expect(Notifier.blocker(auth: .notDetermined, refresh: .available, lowPower: false) != nil)
        #expect(Notifier.blocker(auth: .authorized, refresh: .denied, lowPower: false)?.contains("Háttérben frissítés") == true)
        #expect(Notifier.blocker(auth: .authorized, refresh: .restricted, lowPower: false) != nil)
        #expect(Notifier.blocker(auth: .authorized, refresh: .available, lowPower: true)?.contains("Alacsony fogyasztású") == true)
    }
}
