import Foundation
import Observation

/// A lesson the user hid because it isn't actually held (KRÉTA still lists it).
/// Not tied to KRÉTA's lesson id: a planned lesson's id changes once the teacher logs it.
struct HideRule: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case once     // this one occasion
        case weekly   // same weekday and lesson number every week
        case subject  // every lesson of the subject
    }

    var kind: Kind
    var subject: String   // KRÉTA's subject name, not a renamed one
    var day: String?      // once: yyyy-MM-dd
    var weekday: Int?     // weekly: 1 = Sunday … 7 = Saturday
    var slot: String?     // once/weekly: the lesson number, or the start time if there is none
    var id: Self { self }

    init(_ kind: Kind, for o: Ora) {
        self.kind = kind
        subject = o.subjectKey
        switch kind {
        case .once: day = o.dayKey; slot = o.slotKey
        case .weekly: weekday = HiddenLessons.calendar.component(.weekday, from: o.kezdetIdopont); slot = o.slotKey
        case .subject: break
        }
    }

    func matches(_ o: Ora) -> Bool {
        guard !o.isEvent, o.subjectKey == subject else { return false }
        switch kind {
        case .once: return o.dayKey == day && o.slotKey == slot
        case .weekly: return HiddenLessons.calendar.component(.weekday, from: o.kezdetIdopont) == weekday && o.slotKey == slot
        case .subject: return true
        }
    }
}

@Observable
final class HiddenLessons {
    static let shared = HiddenLessons()

    var rules: [HideRule] { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(rules), forKey: Pref.hiddenLessons) } }

    private init() {
        rules = UserDefaults.standard.data(forKey: Pref.hiddenLessons).flatMap { try? JSONDecoder().decode([HideRule].self, from: $0) } ?? []
    }

    func isHidden(_ o: Ora) -> Bool { rules.contains { $0.matches(o) } }
    func hide(_ kind: HideRule.Kind, _ o: Ora) { if !isHidden(o) { rules.append(HideRule(kind, for: o)) } }
    /// Shows the lesson again by dropping every rule that hides it.
    func unhide(_ o: Ora) { rules.removeAll { $0.matches(o) } }

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "hu_HU")
        return c
    }()
    static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}

extension Ora {
    var isEvent: Bool { tipus.nev == "TanevRendjeEsemeny" }
    var subjectKey: String { let n = tantargy?.nev ?? nev ?? ""; return n.prefix(1).uppercased() + n.dropFirst() }
    var slotKey: String { oraszam.map(String.init) ?? HiddenLessons.timeFormat.string(from: kezdetIdopont) }
    var dayKey: String { HiddenLessons.dayFormat.string(from: kezdetIdopont) }
}
