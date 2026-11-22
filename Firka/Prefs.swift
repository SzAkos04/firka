import Foundation

/// Every UserDefaults key the app uses, in one place (the notification toggles are in `Notifier.kinds`).
enum Pref {
    static let demo = "demo"
    static let surpriseGrades = "surpriseGrades"
    static let seenGrades = "seenGrades"
    static let liveActivity = "liveActivity"
    static let hiddenLessons = "hiddenLessons"
    static let renameSubjects = "renameSubjects"
    static let renameTeachers = "renameTeachers"
    static let timetableMonth = "timetableMonth"
    static func rounding(_ n: Int) -> String { "rounding\(n)" }

    /// A Bool setting that defaults to on.
    static func on(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}
