import Foundation
import Testing
@testable import Firka

/// The week strip: which week/day it shows, the "ma" circle, swiping. Dates are in Budapest time.
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

    @Test("bug: tapping \"ma\" on a free Sunday jumped back a week; it must stay on the coming week")
    func todayCellOnSundayStays() {
        let shown = TimetableNav.days(week: monday, lessonDays: schoolWeek)
        #expect(TimetableNav.showsTodayCell(today: sunday, days: shown))
        #expect(TimetableNav.week(showing: sunday, lessonDays: schoolWeek) == monday)  // was lastMonday
    }

    @Test("a working Saturday is a school day: it opens on it and the strip shows it")
    func workingSaturday() {
        let saturday = budapest(2026, 11, 21)
        let days = schoolWeek.union([saturday])
        #expect(TimetableNav.openingDay(today: saturday, lessonDays: days) == saturday)
        #expect(TimetableNav.week(showing: saturday, lessonDays: days) == lastMonday)
        let shown = TimetableNav.days(week: lastMonday, lessonDays: days)
        #expect(shown.count == 6 && shown.last == saturday, "Saturday yes, the free Sunday no")
        #expect(!TimetableNav.showsTodayCell(today: saturday, days: shown))
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

    @Test("on a weekday the \"ma\" circle only shows when another week is open")
    func todayCellOnWeekday() {
        let wednesday = budapest(2026, 11, 25)
        #expect(!TimetableNav.showsTodayCell(today: wednesday, days: TimetableNav.days(week: monday, lessonDays: schoolWeek)))
        let nextWeek = monday.adding(days: 7)
        #expect(TimetableNav.showsTodayCell(today: wednesday, days: TimetableNav.days(week: nextWeek, lessonDays: schoolWeek)))
        #expect(TimetableNav.week(showing: wednesday, lessonDays: schoolWeek) == monday)
        #expect(TimetableNav.openingDay(today: wednesday, lessonDays: schoolWeek) == wednesday)
    }

    @Test("swiping crosses weeks at the ends")
    func stepAcrossWeeks() {
        let days = TimetableNav.days(week: monday, lessonDays: schoolWeek)
        let friday = budapest(2026, 11, 27)
        #expect(TimetableNav.step(day: monday, days: days, week: monday, by: 1) == (monday, budapest(2026, 11, 24)))
        #expect(TimetableNav.step(day: friday, days: days, week: monday, by: 1) == (budapest(2026, 11, 30), budapest(2026, 11, 30)))
        #expect(TimetableNav.step(day: monday, days: days, week: monday, by: -1) == (lastMonday, budapest(2026, 11, 20)))
    }

    @Test("swiping from \"ma\" (a day outside the strip) goes to the strip's first day, or back a week")
    func stepFromTodayCell() {
        let days = TimetableNav.days(week: monday, lessonDays: schoolWeek)
        #expect(TimetableNav.step(day: sunday, days: days, week: monday, by: 1) == (monday, monday))
        #expect(TimetableNav.step(day: sunday, days: days, week: monday, by: -1) == (lastMonday, budapest(2026, 11, 20)))
    }
}
