import Foundation
import Testing
@testable import Firka

@Suite("Timetable: week ranges, hidden lessons, the current lesson")
struct TimetableTests {
    let monday = budapest(2026, 11, 23)

    @Test("Monday all-day event at local midnight (23:00 UTC Sunday) stays in its week; Sunday drops out")
    func weekKeepsMondayMidnight() {
        let week = budapest(2026, 10, 26)  // autumn break, the week right after the DST change
        let next = budapest(2026, 11, 2)
        let event = lesson("e", day: week, from: 0, minutes: 0, event: true)
        let sunday = lesson("s", day: budapest(2026, 10, 25), from: 8 * 60)
        let nextMonday = lesson("n", day: next, from: 8 * 60)
        #expect(Ora.keep([sunday, event, nextMonday], from: week, to: next).map(\.uid) == ["e"])
    }

    @Test func hideOnce() {
        let l = lesson("a", day: monday, from: 8 * 60, number: 2)
        var nextWeek = lesson("b", day: budapest(2026, 11, 30), from: 8 * 60, number: 2)
        #expect(HideRule(.once, for: l).matches(l))
        #expect(!HideRule(.once, for: l).matches(nextWeek))
        nextWeek.kezdetIdopont = l.kezdetIdopont
        #expect(HideRule(.once, for: l).matches(nextWeek), "a planned lesson's KRÉTA id changes once it's logged")
    }

    @Test func hideWeekly() {
        let l = lesson("a", day: monday, from: 8 * 60, number: 2)
        #expect(HideRule(.weekly, for: l).matches(lesson("b", day: budapest(2026, 11, 30), from: 8 * 60, number: 2)))
        #expect(!HideRule(.weekly, for: l).matches(lesson("c", day: budapest(2026, 11, 30), from: 9 * 60, number: 3)))
        #expect(!HideRule(.weekly, for: l).matches(lesson("d", day: budapest(2026, 12, 1), from: 8 * 60, number: 2)))
        #expect(!HideRule(.weekly, for: l).matches(lesson("e", day: budapest(2026, 11, 30), from: 8 * 60, number: 2, subject: "fizika")))
    }

    @Test("without a lesson number the start time is the slot")
    func hideWithoutNumber() {
        let l = lesson("a", day: monday, from: 8 * 60, number: nil)
        #expect(HideRule(.weekly, for: l).slot == "08:00")
        #expect(HideRule(.weekly, for: l).matches(lesson("b", day: budapest(2026, 11, 30), from: 8 * 60, number: nil)))
    }

    @Test("whole subject; school events are never hidden")
    func hideSubject() {
        let l = lesson("a", day: monday, from: 8 * 60)
        #expect(HideRule(.subject, for: l).matches(lesson("b", day: budapest(2027, 2, 1), from: 13 * 60, number: 7)))
        var event = lesson("e", day: monday, from: 0, event: true)
        event.nev = "matematika"
        #expect(!HideRule(.subject, for: l).matches(event))
    }

    @Test("rules survive encoding (they're stored as JSON)")
    func ruleCodable() throws {
        let rules = [HideRule(.once, for: lesson("a", day: monday, from: 480)), HideRule(.weekly, for: lesson("b", day: monday, from: 600, number: 3))]
        #expect(try JSONDecoder().decode([HideRule].self, from: JSONEncoder().encode(rules)) == rules)
    }

    // MARK: headline (widget + Live Activity)

    var day: [WidgetLesson] {
        [widgetLesson("A", budapest(2026, 11, 23, 8)), widgetLesson("B", budapest(2026, 11, 23, 8, 55), cancelled: true),
         widgetLesson("C", budapest(2026, 11, 23, 9, 50))]
    }

    @Test func headlineInLesson() {
        let h = day.headline(at: budapest(2026, 11, 23, 8, 10))
        #expect(h?.index == 0 && h?.inProgress == true)
    }

    @Test("during a break the next lesson; cancelled ones are skipped")
    func headlineBreak() {
        let h = day.headline(at: budapest(2026, 11, 23, 8, 50))
        #expect(h?.index == 2 && h?.inProgress == false)
    }

    @Test func headlineAfterLastLesson() {
        #expect(day.headline(at: budapest(2026, 11, 23, 11)) == nil)
        #expect([WidgetLesson]().headline(at: .now) == nil)
    }

    @Test("Live Activity: counts down to the lesson end, or to the next start in a break")
    func liveActivityState() {
        let inLesson = LessonActivityAttributes.ContentState(lessons: day, now: budapest(2026, 11, 23, 8, 10))!
        #expect(inLesson.inLesson && inLesson.staleDate == budapest(2026, 11, 23, 8, 45))
        let inBreak = LessonActivityAttributes.ContentState(lessons: day, now: budapest(2026, 11, 23, 8, 50))!
        #expect(!inBreak.inLesson && inBreak.focused.subject == "C" && inBreak.staleDate == budapest(2026, 11, 23, 9, 50))
        #expect(LessonActivityAttributes.ContentState(lessons: day, now: budapest(2026, 11, 23, 12)) == nil)
        #expect(inLesson.sameContent(as: LessonActivityAttributes.ContentState(lessons: day, now: budapest(2026, 11, 23, 8, 20))!))
    }

    @Test func nextLessonChange() {
        #expect(LessonLive.nextChange(day, after: budapest(2026, 11, 23, 8, 10)) == budapest(2026, 11, 23, 8, 45))
        #expect(LessonLive.nextChange(day, after: budapest(2026, 11, 23, 23)) == nil)
    }
}
