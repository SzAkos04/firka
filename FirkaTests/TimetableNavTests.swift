import Foundation
import Testing
@testable import Firka

/// The week strip: which week/day it shows, changing weeks, the "Ma" button, swiping. Dates are in Budapest time.
@Suite("Timetable navigation")
struct TimetableNavTests {
    let sunday = budapest(2026, 11, 22)      // a free Sunday
    let monday = budapest(2026, 11, 23)
    let lastMonday = budapest(2026, 11, 16)
    var schoolWeek: Set<Date> { Set((0..<5).map { monday.adding(days: $0) } + (0..<5).map { lastMonday.adding(days: $0) }) }

    @Test("on a free Sunday the timetable opens on next Monday")
    func opensNextMonday() {
        #expect(TimetableNav.openingDay(today: sunday, lessonDays: schoolWeek) == monday)
        #expect(TimetableNav.week(showing: monday, lessonDays: schoolWeek) == monday)
    }

    @Test("changing weeks selects Monday; back on today's week, today")
    func moveSelectsMonday() {
        let wednesday = budapest(2026, 11, 25)
        let next = budapest(2026, 11, 30)
        #expect(TimetableNav.move(week: monday, by: 1, today: wednesday, lessonDays: schoolWeek) == (next, next))
        #expect(TimetableNav.move(week: monday, by: -1, today: wednesday, lessonDays: schoolWeek) == (lastMonday, lastMonday))
        #expect(TimetableNav.move(week: next, by: -1, today: wednesday, lessonDays: schoolWeek) == (monday, wednesday))
        #expect(TimetableNav.move(week: next, by: -1, today: sunday, lessonDays: schoolWeek) == (monday, monday),
                "free Sunday: the coming week is today's, and Monday is where Ma leads")
        #expect(TimetableNav.move(week: lastMonday, by: 1, today: sunday, lessonDays: schoolWeek) == (monday, monday))
    }

    @Test("the \"Ma\" button is off where it would lead anyway")
    func atToday() {
        let wednesday = budapest(2026, 11, 25)
        #expect(TimetableNav.isAtToday(day: wednesday, today: wednesday, lessonDays: schoolWeek))
        #expect(!TimetableNav.isAtToday(day: budapest(2026, 11, 26), today: wednesday, lessonDays: schoolWeek))
        #expect(TimetableNav.isAtToday(day: monday, today: sunday, lessonDays: schoolWeek), "free Sunday: Monday is where Ma leads")
        #expect(!TimetableNav.isAtToday(day: budapest(2026, 11, 30), today: sunday, lessonDays: schoolWeek))
    }

    @Test("a working Saturday is a school day: it opens on it and the strip shows it")
    func workingSaturday() {
        let saturday = budapest(2026, 11, 21)
        let days = schoolWeek.union([saturday])
        #expect(TimetableNav.openingDay(today: saturday, lessonDays: days) == saturday)
        #expect(TimetableNav.week(showing: saturday, lessonDays: days) == lastMonday)
        let shown = TimetableNav.days(week: lastMonday, lessonDays: days)
        #expect(shown.count == 6 && shown.last == saturday, "Saturday yes, the free Sunday no")
    }

    @Test("a weekend with only a school-calendar event (no lessons) doesn't add columns")
    func weekendEventOnly() {
        let saturday = budapest(2026, 11, 28)
        let found = TimetableNav.lessonDays([lesson("a", day: monday, from: 8 * 60),
                                             lesson("e", day: saturday, from: 0, event: true)])
        #expect(found == [monday])
        #expect(TimetableNav.days(week: monday, lessonDays: found).count == 5)
        #expect(TimetableNav.openingDay(today: saturday, lessonDays: found) == budapest(2026, 11, 30))
    }

    @Test("on a weekday the timetable opens on today, in its own week")
    func weekday() {
        let wednesday = budapest(2026, 11, 25)
        #expect(TimetableNav.openingDay(today: wednesday, lessonDays: schoolWeek) == wednesday)
        #expect(TimetableNav.week(showing: wednesday, lessonDays: schoolWeek) == monday)
    }

    @Test("swiping crosses weeks at the ends")
    func stepAcrossWeeks() {
        let friday = budapest(2026, 11, 27)
        #expect(TimetableNav.step(day: monday, week: monday, lessonDays: schoolWeek, by: 1) == (monday, budapest(2026, 11, 24)))
        #expect(TimetableNav.step(day: friday, week: monday, lessonDays: schoolWeek, by: 1) == (budapest(2026, 11, 30), budapest(2026, 11, 30)))
        #expect(TimetableNav.step(day: monday, week: monday, lessonDays: schoolWeek, by: -1) == (lastMonday, budapest(2026, 11, 20)))
    }

    @Test("swiping from a day outside the strip goes to its first day, or back a week")
    func stepFromOutside() {
        #expect(TimetableNav.step(day: sunday, week: monday, lessonDays: schoolWeek, by: 1) == (monday, monday))
        #expect(TimetableNav.step(day: sunday, week: monday, lessonDays: schoolWeek, by: -1) == (lastMonday, budapest(2026, 11, 20)))
    }

    @Test("swiping back from Monday lands on a working Saturday of the week before, not on its Friday")
    func stepBackToSaturday() {
        let saturday = budapest(2026, 11, 21)
        #expect(TimetableNav.step(day: monday, week: monday, lessonDays: schoolWeek.union([saturday]), by: -1) == (lastMonday, saturday))
    }
}
