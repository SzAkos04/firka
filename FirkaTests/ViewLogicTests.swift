import Foundation
import Testing
@testable import Firka

/// Logic pulled out of views, the widget and the Live Activity.

@Suite("Month grid")
struct MonthGridTests {
    @Test("blank cells before the 1st, Monday first", arguments: [
        (budapest(2026, 11, 1), 6, 30),  // starts on a Sunday
        (budapest(2027, 2, 1), 0, 28),   // starts on a Monday
        (budapest(2028, 2, 1), 1, 29),   // leap year, Tuesday
        (budapest(2026, 3, 1), 6, 31),   // clocks go forward on the 29th
    ])
    func grid(_ month: Date, _ blanks: Int, _ count: Int) {
        #expect(TimetableNav.leadingBlanks(month: month) == blanks)
        let days = TimetableNav.monthDays(month)
        #expect(days.count == count)
        #expect(days.allSatisfy { $0 == $0.startOfDay }, "every cell is a midnight, also after the DST change")
    }
}

@Suite("Attachments")
struct AttachmentTests {
    @Test("file names can't leave the attachment's folder", arguments: [
        ("dolgozat.pdf", "dolgozat.pdf"),
        ("a/b:c.pdf", "a_b_c.pdf"),
        ("", "fajl"),
        (".", "fajl"),
        ("..", "fajl"),
        ("../titok", ".._titok"),
    ])
    func safeName(_ name: String, _ expected: String) {
        #expect(Csatolmany(azonosito: 1, fajlNev: name).safeFileName == expected)
    }
}

@Suite("Widget and Live Activity")
struct WidgetScheduleTests {
    let day = budapest(2026, 11, 23)
    var lessons: [WidgetLesson] {
        [widgetLesson("Matek", day.addingTimeInterval(8 * 3600)),
         widgetLesson("Töri", day.addingTimeInterval(9 * 3600), cancelled: true),
         widgetLesson("Angol", day.addingTimeInterval(10 * 3600)),
         widgetLesson("Fizika", day.adding(days: 1).addingTimeInterval(8 * 3600))]
    }

    @Test("in a lesson: it's current, the rest of today (not cancelled) is upcoming")
    func inLesson() {
        let v = lessons.widgetView(at: day.addingTimeInterval(8 * 3600 + 60))
        #expect(v.current?.subject == "Matek")
        #expect(v.upcoming.map(\.subject) == ["Angol"])
    }

    @Test("before school nothing is current, the day is upcoming")
    func beforeSchool() {
        let v = lessons.widgetView(at: day.addingTimeInterval(7 * 3600))
        #expect(v.current == nil)
        #expect(v.upcoming.map(\.subject) == ["Matek", "Angol"])
    }

    @Test("after the last lesson: tomorrow's first, alone")
    func afterSchool() {
        let v = lessons.widgetView(at: day.addingTimeInterval(12 * 3600))
        #expect(v.current == nil)
        #expect(v.upcoming.map(\.subject) == ["Fizika"])
        #expect(lessons.widgetView(at: day.adding(days: 2)).upcoming.isEmpty)
    }

    @Test("timeline: every future start and end once, in order")
    func changeTimes() {
        let now = day.addingTimeInterval(8 * 3600 + 60)
        let t = lessons.changeTimes(after: now)
        #expect(t.first == day.addingTimeInterval(8 * 3600 + 45 * 60))
        #expect(t == t.sorted() && Set(t).count == t.count && t.allSatisfy { $0 > now })
        #expect(t.count == 7)  // Matek end + 3 lessons × 2
    }

    @Test("Live Activity: one started early, which iOS would end (8 hours) before the last lesson, is restarted when that gains time")
    func liveActivityRestart() {
        let at = { (h: Double) in self.day.addingTimeInterval(h * 3600) }
        let end = at(15)  // the last lesson ends at 15:00
        #expect(LessonLive.needsRestart(started: at(6.25), lastEnd: end, now: at(9)), "started 6:15: iOS would end it at 14:15")
        #expect(!LessonLive.needsRestart(started: at(7.5), lastEnd: end, now: at(9)), "lasts till 15:30: fine")
        #expect(!LessonLive.needsRestart(started: at(6.25), lastEnd: end, now: at(6.5)), "a restart now gains under half an hour")
        #expect(!LessonLive.needsRestart(started: nil, lastEnd: end, now: at(9)), "started by an older build: unknown")
    }

    @Test("Live Activity starts only within 2 hours of the first held lesson")
    func liveActivityStart() {
        #expect(!LessonLive.shouldStart(lessons, now: day.addingTimeInterval(5 * 3600)))
        #expect(LessonLive.shouldStart(lessons, now: day.addingTimeInterval(6.5 * 3600)))
        #expect(LessonLive.shouldStart(lessons, now: day.addingTimeInterval(8.5 * 3600)), "also mid-lesson")
        #expect(!LessonLive.shouldStart([widgetLesson("X", day.addingTimeInterval(8 * 3600), cancelled: true)],
                                        now: day.addingTimeInterval(7.5 * 3600)), "all cancelled")
        #expect(!LessonLive.shouldStart([], now: day))
    }
}

@Suite("Surprise grades")
struct SurpriseTests {
    @Test("unseen grades are hidden, oldest first; off or before the first sync nothing is")
    func hidden() throws {
        let g = try grades(gradeJSON("a", 5, 100, date: "2025-10-03T08:00:00Z"),
                           gradeJSON("b", 4, 100, date: "2025-10-01T08:00:00Z"),
                           gradeJSON("c", 3, 100, date: "2025-10-02T08:00:00Z"))
        #expect(AppStore.surprises(g, seen: ["b"], on: true).map(\.uid) == ["c", "a"])
        #expect(AppStore.surprises(g, seen: ["b"], on: false).isEmpty)
        #expect(AppStore.surprises(g, seen: nil, on: true).isEmpty)
    }
}

@Suite("Refresh fallbacks")
struct SoftFetchTests {
    struct Flaky: Error {}

    @Test("a failing optional endpoint keeps the cached list")
    func keepsCache() async throws {
        #expect(try await Snapshot.soft("x", [1, 2]) { throw Flaky() } == [1, 2])
        #expect(try await Snapshot.soft("x", nil as [Int]?) { throw Flaky() } == nil)
        #expect(try await Snapshot.soft("x", [1]) { [3] } == [3])
    }

    @Test("an expired login and a cancel still stop the refresh")
    func stopsRefresh() async {
        await #expect(throws: KretaError.self) { try await Snapshot.soft("x", [1]) { throw KretaError.reauth } }
        await #expect(throws: CancellationError.self) { try await Snapshot.soft("x", [1]) { throw URLError(.cancelled) } }
    }
}
