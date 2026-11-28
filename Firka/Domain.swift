import Foundation

// The app's own data, whichever school system it comes from (KRÉTA today, Neptun next).
// Screens, the widget, the Live Activity, notifications, hidden lessons and renames read only these;
// each provider maps its own API's shapes onto them (KretaMapping.swift).

struct Subject: Codable, Hashable {
    var id: String
    /// As the school system sends it (KRÉTA: lower case); shown through `name` (Renames.swift).
    var raw: String
    /// The school system's order of subjects, when it has one.
    var order: Int?
}

/// A timetable entry: a lesson / class, or a school-calendar event.
struct Lesson: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case lesson, event }

    var id: String
    var kind: Kind = .lesson
    var start: Date
    var end: Date
    var subject: Subject?
    /// The entry's own name (events have only this).
    var name: String?
    var number: Int?
    var teacher: String?
    var substitute: String?
    var room: String?
    var topic: String?
    var cancelled = false
    /// The school system's word for its state ("Naplózott", "Elmaradt"), for the detail page.
    var stateText: String?
    /// Whether the student was there, as recorded ("Jelen", "Hiányzott").
    var attendance: String?
    var testID: String?
    var homeworkID: String?

    var isEvent: Bool { kind == .event }
}

/// A grade, a percentage or a text evaluation.
struct Grade: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case midYear, halfYear, yearEnd, other }
    enum Value: String, Codable { case grade, percent, text }

    var id: String
    /// When it was made (the lesson's date) and when it was entered.
    var date: Date
    var recorded: Date
    var subject: Subject
    var kind: Kind
    var value: Value
    var number: Int?
    var text: String?
    var shortText: String?
    /// Weight in percent (KRÉTA); nil for a grade outside the average.
    var weight: Int?
    /// Credits of the subject (Neptun); nil in KRÉTA.
    var credit: Int?
    var topic: String?
    var mode: String?
    var teacher: String?
}

struct Absence: Codable, Identifiable, Hashable {
    enum State: String, Codable { case excused, unexcused, pending }

    var id: String
    var subject: Subject
    var date: Date
    var lessonStart: Date?
    var lessonEnd: Date?
    var lessonNumber: Int?
    var late: Bool
    var lateMinutes: Int?
    var state: State
    /// How it was excused ("Orvosi igazolás").
    var excuse: String?
    var recordedBy: String?
}

struct Homework: Codable, Identifiable, Hashable {
    var id: String
    var subject: Subject
    var teacher: String?
    var html: String?
    var given: Date
    var due: Date
    var done: Bool?
}

/// A test announced in advance (KRÉTA "bejelentett számonkérés").
struct AnnouncedTest: Codable, Identifiable, Hashable {
    var id: String
    var date: Date
    var announced: Date
    var subject: Subject
    var lessonNumber: Int?
    var topic: String?
    var mode: String?
    var teacher: String?
}

/// A university exam (Neptun "vizsga").
struct Exam: Codable, Identifiable, Hashable {
    var id: String
    var subject: Subject
    var start: Date
    var end: Date?
    var room: String?
    var kind: String?
    var registered: Bool
    var result: Int?
    var resultText: String?
}

/// A university term (Neptun "félév").
struct Semester: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var current: Bool
}

struct Attachment: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var url: URL
}
