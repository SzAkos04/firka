#if DEBUG
import Foundation

// Fake data for trying the app without a KRÉTA account (debug builds only).
extension Snapshot {
    static var demo: Snapshot {
        let names = ["matematika", "magyar nyelv és irodalom", "történelem", "angol nyelv", "fizika", "biológia", "informatika", "testnevelés"]
        let subjects = names.enumerated().map { i, n in Subject(id: "s\(i)", raw: n, order: i) }
        let teachers = ["Kovács Anna", "Nagy Péter", "Szabó Éva", "Tóth Gábor", "Horváth Zsuzsa", "Varga Béla", "Kiss Dóra", "Molnár Ádám"]
        let now = Date()
        let week = now.startOfWeek

        var lessons: [Lesson] = []
        for d in 0..<14 where d % 7 < 5 {
            let day = week.adding(days: d)
            for n in 1...6 {
                let s = subjects[(d * 3 + n) % subjects.count]
                let start = Calendar.hu.date(bySettingHour: 8, minute: 0, second: 0, of: day)!.addingTimeInterval(Double(n - 1) * 55 * 60)
                let cancelled = d == 2 && n == 5
                lessons.append(Lesson(id: "l\(d)-\(n)", start: start, end: start.addingTimeInterval(45 * 60), subject: s, name: s.raw,
                                      number: n, teacher: teachers[Int(s.id.dropFirst())!],
                                      substitute: d == 1 && n == 3 ? "Fekete Lili" : nil, room: "\(100 + n * 7)", topic: "Gyakorlás",
                                      cancelled: cancelled, stateText: cancelled ? "Elmaradt" : "Naplózott",
                                      testID: d == 3 && n == 2 ? "t0" : nil, homeworkID: d == 4 && n == 1 ? "h0" : nil))
            }
        }

        let values = [5, 4, 5, 3, 4, 5, 2, 4, 5, 5, 4, 3, 5, 4, 4, 5, 3, 5, 4, 5, 1, 4, 5, 4, 3, 5, 5, 4, 2, 5, 4, 5]
        var grades = values.enumerated().map { i, v in
            let date = now.adding(days: -(values.count - i) * 2)
            return Grade(id: "g\(i)", date: date, recorded: date, subject: subjects[i % subjects.count], kind: .midYear, value: .grade,
                         number: v, weight: i % 4 == 0 ? 200 : 100, topic: ["Témazáró", "Felelet", "Házi dolgozat", "Röpdolgozat"][i % 4],
                         mode: "Írásbeli", teacher: teachers[i % teachers.count], kindText: "Évközi jegy")
        }
        grades.append(Grade(id: "gs", date: now.adding(days: -3), recorded: now.adding(days: -3), subject: subjects[7], kind: .midYear,
                            value: .text, text: "Kiválóan teljesített", shortText: "Kiváló", teacher: teachers[7], kindText: "Évközi jegy"))

        let absence = { (id: String, s: Int, days: Int, n: Int, late: Int?, state: Absence.State, by: Int) in
            Absence(id: id, subject: subjects[s], date: now.adding(days: -days), lessonStart: now.adding(days: -days),
                    lessonEnd: now.adding(days: -days), lessonNumber: n, late: late != nil, lateMinutes: late, state: state,
                    excuse: state == .excused ? "Orvosi igazolás" : nil, recordedBy: teachers[by])
        }
        let messages = [
            Message(id: "n0", title: "Szalagavató próba", author: "Igazgatóság", date: now.adding(days: -1),
                    html: "<p>Pénteken 14:00-tól próba a tornateremben.</p>"),
            Message(id: "f0", title: "Dicséret", author: teachers[4], date: now.adding(days: -6), html: "Kiemelkedő munka a fizika versenyen."),
            Message(id: "p1", title: "Szülői értekezlet", author: teachers[0], authorRole: "osztályfőnök", date: now.adding(days: -2),
                    html: "<p>Csütörtökön 17 órakor szülői értekezlet lesz.</p>", unread: true),
        ]

        return Snapshot(
            studentName: "Teszt Elek", schoolName: "Demó Gimnázium",
            grades: grades, lessons: lessons,
            absences: [absence("a0", 0, 8, 1, nil, .excused, 0), absence("a1", 1, 8, 2, nil, .excused, 0), absence("a2", 3, 2, 1, 7, .pending, 3)],
            homework: [Homework(id: "h0", subject: subjects[0], teacher: teachers[0],
                                html: "<p>Tankönyv <b>42. oldal</b> 3–7. feladat.</p><ul><li>a) rész</li><li>b) rész</li></ul>",
                                given: now.adding(days: -1), due: week.adding(days: 4)),
                       Homework(id: "h1", subject: subjects[1], teacher: teachers[1], html: "<p>Olvasónapló a 3. fejezetig.</p>",
                                given: now.adding(days: -3), due: week.adding(days: 3), done: true)],
            tests: [AnnouncedTest(id: "t0", date: week.adding(days: 3), announced: now.adding(days: -5), subject: subjects[2],
                                  lessonNumber: 2, topic: "Az Árpád-kor", mode: "Írásbeli témazáró", teacher: teachers[2])],
            messageList: messages.sorted { $0.date > $1.date }, messageSources: ["n", "f", "p"],
            // every subject but PE: a subject without one happens in real data too
            classAverages: Dictionary(uniqueKeysWithValues: zip(subjects.dropLast().map(\.id), [3.92, 4.21, 3.85, 3.6, 3.4, 4.05, 3.75])),
            updated: now)
    }
}
#endif
