import Foundation

/// Which week and day the timetable shows, without any UI, so it's testable.
/// `lessonDays`: the (start of) days that have real lessons, not just school-calendar events.
enum TimetableNav {
    /// The days with real lessons, for `lessonDays`.
    static func lessonDays(_ lessons: [Ora]) -> Set<Date> {
        Set(lessons.filter { !$0.isEvent }.map { $0.kezdetIdopont.startOfDay })
    }

    /// Monday–Friday of `week`, plus a weekend day when it has lessons.
    static func days(week: Date, lessonDays: Set<Date>) -> [Date] {
        (0..<7).map { week.adding(days: $0) }.filter { $0 < week.adding(days: 5) || lessonDays.contains($0) }
    }

    /// The week whose strip shows `day`; a free weekend day goes with the coming week.
    static func week(showing day: Date, lessonDays: Set<Date>) -> Date {
        isFreeWeekend(day, lessonDays) ? day.startOfWeek.adding(days: 7) : day.startOfWeek
    }

    /// Where the timetable opens and "Ma" jumps: today, or on a free weekend the next Monday.
    static func openingDay(today: Date, lessonDays: Set<Date>) -> Date {
        isFreeWeekend(today, lessonDays) ? today.startOfWeek.adding(days: 7) : today
    }

    /// `weeks` weeks forward or back: Monday is selected, or on the week "Ma" leads to, that day.
    static func move(week: Date, by weeks: Int, today: Date, lessonDays: Set<Date>) -> (week: Date, day: Date) {
        let w = week.adding(days: 7 * weeks)
        let opening = openingDay(today: today, lessonDays: lessonDays)
        return (w, opening.startOfWeek == w ? opening : w)
    }

    /// Whether `day` is where "Ma" leads, so the button has nothing to do.
    static func isAtToday(day: Date, today: Date, lessonDays: Set<Date>) -> Bool {
        day == openingDay(today: today, lessonDays: lessonDays)
    }

    /// One school day forward (+1) or back (-1), crossing weeks. From a day outside the strip
    /// forward is the strip's first day, back is the previous week.
    static func step(day: Date, days: [Date], week: Date, by dir: Int) -> (week: Date, day: Date) {
        let j = (days.firstIndex(of: day) ?? (dir > 0 ? -1 : 0)) + dir
        if days.indices.contains(j) { return (week, days[j]) }
        let w = week.adding(days: 7 * dir)
        return (w, dir > 0 ? w : w.adding(days: 4))
    }

    /// The days of the month starting at `month`.
    static func monthDays(_ month: Date) -> [Date] {
        let n = Calendar.hu.range(of: .day, in: .month, for: month)!.count
        return (0..<n).map { month.adding(days: $0) }
    }

    /// Empty cells before the 1st in a Monday-first grid.
    static func leadingBlanks(month: Date) -> Int { (Calendar.hu.component(.weekday, from: month) + 5) % 7 }

    private static func isFreeWeekend(_ day: Date, _ lessonDays: Set<Date>) -> Bool {
        Calendar.hu.isDateInWeekend(day) && !lessonDays.contains(day)
    }
}
