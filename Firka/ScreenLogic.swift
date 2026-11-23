import Foundation

/// What the screens show, computed without SwiftUI so it's testable. The views only lay it out.
enum HomeLogic {
    /// Hungarian order: family name first, so the first given name is the 2nd word.
    static func greeting(name: String, hour: Int) -> String {
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.count >= 2 ? parts[1] : parts.first ?? ""
        let hello = (4..<9).contains(hour) ? "Jó reggelt" : (9..<18).contains(hour) ? "Szia" : "Jó estét"
        return first.isEmpty ? "Firka" : "\(hello), \(first)!"
    }

    /// The lesson in progress, the next one, and today's lessons if any are left, otherwise the next school day's.
    static func today(_ all: [Ora], now: Date, isHidden: (Ora) -> Bool) -> (current: Ora?, next: Ora?, day: Date, lessons: [Ora]) {
        let lessons = all.filter { !$0.isEvent && !isHidden($0) }.sorted { $0.kezdetIdopont < $1.kezdetIdopont }
        let current = lessons.first { $0.kezdetIdopont <= now && $0.vegIdopont > now && !$0.isCancelled }
        let next = lessons.first { $0.kezdetIdopont > now && !$0.isCancelled }
        let day = (lessons.first { $0.vegIdopont > now }?.kezdetIdopont ?? now).startOfDay
        return (current, next, day, lessons.filter { $0.kezdetIdopont.startOfDay == day })
    }

    /// "Még N perc" on the lesson card.
    static func minutesLeft(until end: Date, now: Date) -> Int { Int((end.timeIntervalSince(now) / 60).rounded(.up)) }

    /// Homework/tests: from today on soonest first, before today latest first.
    static func split<T>(_ items: [T], today: Date, date: (T) -> Date) -> (upcoming: [T], past: [T]) {
        (items.filter { date($0) >= today }.sorted { date($0) < date($1) },
         items.filter { date($0) < today }.sorted { date($0) > date($1) })
    }
}

/// The counters on top of the absences screen. Lateness isn't an absence; its minutes add up.
struct AbsenceStats: Equatable {
    var justified = 0, unjustified = 0, pending = 0, lateMinutes = 0

    init(_ all: [Mulasztas]) {
        for a in all {
            if a.isLate { lateMinutes += a.kesesPercben ?? 0; continue }
            switch a.igazolasAllapota {
            case "Igazolt": justified += 1
            case "Igazolatlan": unjustified += 1
            default: pending += 1
            }
        }
    }
}

enum GradesLogic {
    struct SubjectGrades: Identifiable {
        var subject: Tantargy
        var grades: [Ertekeles]
        var id: String { subject.uid }
    }

    /// Mean class average over the subjects you have grades in (KRÉTA also sends subjects you don't).
    static func classOverall(_ grades: [Ertekeles], averages: [String: Double]?) -> Double? {
        let mine = Set(grades.map(\.tantargy.uid))
        let all = (averages ?? [:]).filter { mine.contains($0.key) }.values
        return all.isEmpty ? nil : all.reduce(0, +) / Double(all.count)
    }

    /// Grades by subject, in KRÉTA's subject order, then by name.
    static func subjects(_ grades: [Ertekeles]) -> [SubjectGrades] {
        Dictionary(grouping: grades, by: \.tantargy.uid).values
            .map { SubjectGrades(subject: $0[0].tantargy, grades: $0) }
            .sorted { ($0.subject.sortIndex ?? 0, $0.subject.nev) < ($1.subject.sortIndex ?? 0, $1.subject.nev) }
    }

    static func columnAverage(_ values: [Int?]) -> String {
        let v = values.compactMap { $0 }
        return v.isEmpty ? "–" : (Double(v.reduce(0, +)) / Double(v.count)).hu2
    }
}

extension Ertekeles {
    /// "Törtek · Írásbeli röpdolgozat · 200%"; the weight only when it isn't 100% and isn't in the mode already.
    var details: String {
        let mode = mod?.leiras
        let weight = sulySzazalekErteke.flatMap { $0 == 100 || mode?.contains("\($0)%") == true ? nil : "\($0)%" }
        return [tema, mode, weight].compactMap { $0 }.joined(separator: " · ")
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
        let subjects = Set(d.grades.map(\.tantargy.nev) + d.lessons.compactMap { $0.tantargy?.nev } + d.tests.map(\.tantargy.nev)
                           + d.homework.map(\.tantargy.nev) + d.absences.map(\.tantargy.nev)).map(\.capitalizedFirst)
        let teachers = Set(d.lessons.flatMap { [$0.tanarNeve, $0.helyettesTanarNeve] }
                           + d.grades.map(\.ertekeloTanarNeve) + d.tests.map(\.rogzitoTanarNeve)
                           + d.homework.map(\.rogzitoTanarNeve) + d.notes.map(\.keszitoTanarNeve)).compactMap { $0 }
        let hu = Locale(identifier: "hu_HU")
        let sort = { (a: [String]) in a.sorted { $0.compare($1, locale: hu) == .orderedAscending } }
        return (sort(Array(subjects)), sort(teachers))
    }

    /// The search on the rename screen finds the original and the own name.
    static func matches(_ name: String, search: String, custom: String?) -> Bool {
        search.isEmpty || name.localizedCaseInsensitiveContains(search) || (custom ?? "").localizedCaseInsensitiveContains(search)
    }
}
