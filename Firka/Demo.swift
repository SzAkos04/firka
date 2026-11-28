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

    /// A made-up university term in Neptun's shape (FIRKA_DEMO=neptun): courses with credits, classes, exams.
    static var universityDemo: Snapshot {
        let now = Date(), week = now.startOfWeek
        let courses: [(String, String, Int, Int?)] = [("Analízis 1", "BMETE90AX00", 6, 4), ("A programozás alapjai 1", "BMEVIEEAA00", 7, 5),
                                                       ("Fizika 1", "BMETE13AX01", 4, nil), ("Bevezetés a számításelméletbe 1", "BMEVISZAA00", 4, 2),
                                                       ("Digitális technika 1", "BMEVIMIAA00", 5, nil), ("Testnevelés", "BMEGT70BS1B", 0, nil)]
        let grades = courses.enumerated().map { i, c in
            Grade(id: "t2/s\(i)", date: now.adding(days: -10 + i), recorded: now.adding(days: -10 + i), subject: Subject(id: "s\(i)", raw: c.0),
                  kind: .other, value: .grade, number: c.3, text: c.3.map { ["", "Elégtelen", "Elégséges", "Közepes", "Jó", "Jeles"][$0] },
                  credit: c.2, mode: c.1, kindText: "2026/27/1")
        }
        var lessons: [Lesson] = []
        for d in 0..<14 where d % 7 < 5 {
            for (k, c) in courses.prefix(4).enumerated() where (d + k) % 2 == 0 {
                let start = Calendar.hu.date(bySettingHour: 8 + 2 * k, minute: 15, second: 0, of: week.adding(days: d))!
                lessons.append(Lesson(id: "c\(d)-\(k)", start: start, end: start.addingTimeInterval(105 * 60),
                                      subject: Subject(id: "s\(k)", raw: c.0), name: c.0, room: ["K.287", "IB.025", "F29", "QBF13"][k]))
            }
        }
        let exam = { (i: Int, days: Int, result: Int?) in
            let start = Calendar.hu.date(bySettingHour: 9, minute: 0, second: 0, of: now.startOfDay.adding(days: days))!
            return Exam(id: "e\(i)", subject: Subject(id: "s\(i)", raw: courses[i].0), start: start, end: start.addingTimeInterval(3 * 3600),
                        room: "K.287", kind: "Írásbeli vizsga", registered: true, result: result, resultText: result.map { ["", "Elégtelen", "Elégséges", "Közepes", "Jó", "Jeles"][$0] })
        }
        var s = Snapshot()
        s.studentName = "Teszt Elek"
        s.schoolName = "Demó Egyetem"
        s.university = true
        s.courses = grades
        s.grades = grades.filter { $0.number != nil }
        s.lessons = lessons
        s.semesters = [Semester(id: "t2", name: "2026/27/1", current: true), Semester(id: "t1", name: "2025/26/2", current: false)]
        s.exams = [exam(0, -6, 4), exam(2, 12, nil), exam(4, 19, nil)]
        s.messageList = [Message(id: "m1", title: "Vizsgajelentkezés megnyílt", author: "Tanulmányi Osztály", date: now.adding(days: -1),
                                 html: "<p>A vizsgaidőszak jelentkezése december 1-jén nyílik.</p>", unread: true)]
        s.messageSources = ["m"]
        s.updated = now
        return s
    }
}
#endif
