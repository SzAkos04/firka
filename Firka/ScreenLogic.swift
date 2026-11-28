import Foundation

/// What the screens show, computed without SwiftUI so it's testable. The views only lay it out.
extension Lesson {
    /// In progress at `now` (a cancelled one never is).
    func isOn(at now: Date) -> Bool { start <= now && end > now && !cancelled }

    /// The test announced for this lesson: KRÉTA's link, or (when it's missing) one on the same day in the same
    /// subject, for this lesson number if the test has one.
    func announcedTest(in tests: [AnnouncedTest]) -> AnnouncedTest? {
        if let uid = testID, let t = tests.first(where: { $0.id == uid }) { return t }
        guard let subject = subject?.id else { return nil }
        return tests.first {
            $0.subject.id == subject && $0.date.startOfDay == start.startOfDay
                && ($0.lessonNumber == nil || $0.lessonNumber == number)
        }
    }
}

enum HomeLogic {
    /// Hungarian order: family name first, so the first given name is the 2nd word.
    static func greeting(name: String, hour: Int) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.count >= 2 ? parts[1] : parts.first ?? ""
        let hello = (4..<9).contains(hour) ? "Jó reggelt" : (9..<18).contains(hour) ? "Szia" : "Jó estét"
        return first.isEmpty ? "Firka" : "\(hello), \(first)!"
    }

    /// The lesson in progress, the next one, and today's lessons if any are left, otherwise the next school day's.
    static func today(_ all: [Lesson], now: Date, isHidden: (Lesson) -> Bool) -> (current: Lesson?, next: Lesson?, day: Date, lessons: [Lesson]) {
        let lessons = all.filter { !$0.isEvent && !isHidden($0) }.sorted { $0.start < $1.start }
        let current = lessons.first { $0.isOn(at: now) }
        let next = lessons.first { $0.start > now && !$0.cancelled }
        let day = (lessons.first { $0.end > now }?.start ?? now).startOfDay
        return (current, next, day, lessons.filter { $0.start.startOfDay == day })
    }

    /// "Még N perc" on the lesson card.
    static func minutesLeft(until end: Date, now: Date) -> Int { Int((end.timeIntervalSince(now) / 60).rounded(.up)) }

    /// The home screen's homework: upcoming, without the ones marked solved.
    static func openHomework(_ items: [Homework], today: Date) -> [Homework] { split(items, today: today, date: \.due).upcoming.filter { $0.done != true } }

    /// Homework/tests: from today on soonest first, before today latest first.
    static func split<T>(_ items: [T], today: Date, date: (T) -> Date) -> (upcoming: [T], past: [T]) {
        (items.filter { date($0) >= today }.sorted { date($0) < date($1) },
         items.filter { date($0) < today }.sorted { date($0) > date($1) })
    }
}

/// The absences screen's filter.
enum AbsenceFilter: String, CaseIterable {
    case all = "Mind", unexcused = "Igazolatlan", pending = "Igazolandó", subjects = "Tantárgyak"

    func apply(_ all: [Absence]) -> [Absence] {
        switch self {
        case .unexcused: all.filter { $0.state == .unexcused }
        case .pending: all.filter { $0.state == .pending }
        case .all, .subjects: all
        }
    }

    /// Per subject: absences (lateness apart, in minutes), the most missed first, to keep an eye on the limits.
    static func bySubject(_ all: [Absence]) -> [(subject: Subject, absences: Int, lateMinutes: Int)] {
        Dictionary(grouping: all, by: \.subject.id).values.map { items in
            (items[0].subject, items.filter { !$0.late }.count, items.filter(\.late).reduce(0) { $0 + ($1.lateMinutes ?? 0) })
        }
        .sorted { ($0.absences, $1.subject.name) > ($1.absences, $0.subject.name) }
    }
}

/// The counters on top of the absences screen. Lateness isn't an absence; its minutes add up.
struct AbsenceStats: Equatable {
    var justified = 0, unjustified = 0, pending = 0, lateMinutes = 0

    init(_ all: [Absence]) {
        for a in all {
            if a.late { lateMinutes += a.lateMinutes ?? 0; continue }
            switch a.state {
            case .excused: justified += 1
            case .unexcused: unjustified += 1
            case .pending: pending += 1
            }
        }
    }
}

enum GradesLogic {
    struct SubjectGrades: Identifiable {
        var subject: Subject
        var grades: [Grade]
        var id: String { subject.id }
    }

    /// Mean class average over the subjects you have grades in (KRÉTA also sends subjects you don't).
    static func classOverall(_ grades: [Grade], averages: [String: Double]?) -> Double? {
        let mine = Set(grades.map(\.subject.id))
        let all = (averages ?? [:]).filter { mine.contains($0.key) }.values
        return all.isEmpty ? nil : all.reduce(0, +) / Double(all.count)
    }

    /// Grades by subject, in KRÉTA's subject order, then by name.
    static func subjects(_ grades: [Grade]) -> [SubjectGrades] {
        Dictionary(grouping: grades, by: \.subject.id).values
            .map { SubjectGrades(subject: $0[0].subject, grades: $0) }
            .sorted { ($0.subject.order ?? 0, $0.subject.raw) < ($1.subject.order ?? 0, $1.subject.raw) }
    }

    static func columnAverage(_ values: [Int?]) -> String {
        let v = values.compactMap { $0 }
        return v.isEmpty ? "–" : (Double(v.reduce(0, +)) / Double(v.count)).hu2
    }
}

extension Grade {
    /// "Törtek · Írásbeli röpdolgozat · 200%"; the weight only when it isn't 100% and isn't in the mode already.
    var details: String {
        let weight = self.weight.flatMap { $0 == 100 || mode?.contains("\($0)%") == true ? nil : "\($0)%" }
        return [topic, mode, weight].compactMap { $0 }.joined(separator: " · ")
    }
}

extension HideRule {
    var summary: String {
        let slot = self.slot.map { Int($0) != nil ? "\($0). óra" : $0 } ?? ""
        switch kind {
        case .once:
            let d = day.flatMap { HiddenLessons.dayFormat.date(from: $0) }
            return "Csak \(d?.hu("MMMd") ?? day ?? "") · \(slot)"
        case .weekly:
            let names = ["vasárnap", "hétfő", "kedd", "szerda", "csütörtök", "péntek", "szombat"]
            return "Minden \(weekday.map { names[($0 - 1) % 7] } ?? "") · \(slot)"
        case .subject:
            return "A tantárgy összes órája"
        }
    }
}

extension Kreta {
    /// KRÉTA's login ends on this page; the web view stops there.
    static func isRedirect(_ url: URL) -> Bool { url.path == redirectPath }

    /// The authorization code from the redirect page's URL, if it carries our login's `state` (OAuth's CSRF check).
    static func code(fromRedirect url: URL, state: String) -> String? {
        guard isRedirect(url), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.contains(where: { $0.name == "state" && $0.value == state }) else { return nil }
        return items.first { $0.name == "code" }?.value
    }
}

extension Renames {
    /// Every subject and teacher in the data, once each, in Hungarian alphabetical order.
    static func names(in d: Snapshot) -> (subjects: [String], teachers: [String]) {
        let subjects = Set(d.grades.map(\.subject.raw) + d.lessons.compactMap { $0.subject?.raw } + d.tests.map(\.subject.raw)
                           + d.homework.map(\.subject.raw) + d.absences.map(\.subject.raw)).map(\.capitalizedFirst)
        let teachers = Set(d.lessons.flatMap { [$0.teacher, $0.substitute] }
                           + d.grades.map(\.teacher) + d.tests.map(\.teacher) + d.homework.map(\.teacher)
                           + d.messageList.filter { $0.source == "f" }.map(\.author)).compactMap { $0 }
        let hu = Locale(identifier: "hu_HU")
        let sort = { (a: [String]) in a.sorted { $0.compare($1, locale: hu) == .orderedAscending } }
        return (sort(Array(subjects)), sort(teachers))
    }

    /// The search on the rename screen finds the original and the own name.
    static func matches(_ name: String, search: String, custom: String?) -> Bool {
        search.isEmpty || name.localizedCaseInsensitiveContains(search) || (custom ?? "").localizedCaseInsensitiveContains(search)
    }
}

/// The app's tabs, and the links that open them: firka://grades etc. (the server's notifications carry one).
enum AppTab: String {
    case home, timetable, grades, absences, more

    init?(url: URL) {
        guard url.scheme == "firka", let host = url.host() else { return nil }
        self.init(rawValue: host)
    }
}
