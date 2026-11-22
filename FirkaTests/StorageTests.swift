import Foundation
import Testing
@testable import Firka

extension Global {
    /// Settings that survive a restart, and the data the widget reads.
    @Suite("Saved settings", .serialized)
    final class Storage {
        let savedRules = HiddenLessons.shared.rules
        let savedRounding = Rounding.load()
        let savedRenames = (Renames.shared.subjects, Renames.shared.teachers)
        deinit {
            HiddenLessons.shared.rules = savedRules
            savedRounding.save()
            (Renames.shared.subjects, Renames.shared.teachers) = savedRenames
        }

        let monday = budapest(2026, 11, 23)

        @Test("hiding and showing again is saved; hiding twice adds one rule")
        func hiddenLessons() throws {
            let h = HiddenLessons.shared
            h.rules = []
            let l = lesson("a", day: monday, from: 480)
            h.hide(.weekly, l)
            h.hide(.once, l)
            #expect(h.rules.count == 1 && h.isHidden(l))
            #expect(h.isHidden(lesson("b", day: monday.adding(days: 7), from: 480)), "next week's too")
            let stored = try JSONDecoder().decode([HideRule].self, from: try #require(UserDefaults.standard.data(forKey: Pref.hiddenLessons)))
            #expect(stored == h.rules)
            h.unhide(lesson("b", day: monday.adding(days: 7), from: 480))
            #expect(h.rules.isEmpty && !h.isHidden(l))
        }

        @Test("rounding thresholds are saved; missing ones are 0.5")
        func rounding() {
            Rounding(t: [0.5, 0.6, 0.7, 0.8]).save()
            #expect(Rounding.load() == Rounding(t: [0.5, 0.6, 0.7, 0.8]))
            UserDefaults.standard.removeObject(forKey: Pref.rounding(3))
            #expect(Rounding.load().t[2] == 0.5)
        }

        @Test("renames are saved and used for subjects, lessons and teachers")
        func renames() throws {
            let r = Renames.shared
            r.subjects = ["Matematika": "Matek"]
            r.teachers = ["Kovács Anna": "Anna néni"]
            #expect(UserDefaults.standard.dictionary(forKey: Pref.renameSubjects) as? [String: String] == ["Matematika": "Matek"])
            #expect(try grades(gradeJSON("a", 5, 100))[0].tantargy.name == "Matek")
            #expect(lesson("l", day: monday, from: 480).title == "Matek")
            #expect("Kovács Anna".renamedTeacher == "Anna néni" && "Más Tanár".renamedTeacher == "Más Tanár")
            r.subjects = [:]
            #expect(lesson("l", day: monday, from: 480).title == "Matematika")
        }

        @Test("the widget gets real lessons in time order, without events or hidden ones")
        func widgetLessons() {
            HiddenLessons.shared.rules = []
            var s = Snapshot()
            s.lessons = [lesson("2", day: monday, from: 535, subject: "fizika", cancelled: true), lesson("1", day: monday, from: 480, substitute: "X Y"),
                         lesson("e", day: monday, from: 0, event: true), lesson("h", day: monday, from: 600, subject: "rajz")]
            HiddenLessons.shared.hide(.subject, s.lessons[3])
            let w = s.widgetLessons
            #expect(w.map(\.subject) == ["Matematika", "Fizika"])
            #expect(w[0].substituted && !w[0].cancelled && w[1].cancelled && w[0].number == 1)
        }

        @Test("the cache on disk round-trips and feeds the widget file")
        func cacheFile() throws {
            let saved = try? Data(contentsOf: Snapshot.file)
            defer { if let saved { try? saved.write(to: Snapshot.file) } else { Snapshot.delete() } }
            HiddenLessons.shared.rules = []
            var s = Snapshot()
            s.studentName = "Lemez Elek"
            s.lessons = [lesson("1", day: monday, from: 480)]
            s.save()
            #expect(Snapshot.load()?.studentName == "Lemez Elek")
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            let widget = try d.decode([WidgetLesson].self, from: Data(contentsOf: Shared.widgetFile))
            #expect(widget.map(\.subject) == ["Matematika"])
            try Data("nem json".utf8).write(to: Snapshot.file)
            #expect(Snapshot.load() == nil, "a broken cache is ignored, not a crash")
        }
    }
}

@Suite("Texts")
struct TextTests {
    @Test("absence labels", arguments: [
        ("Igazolt", nil, "Igazolt hiányzás"), ("Igazolatlan", nil, "Igazolatlan hiányzás"),
        ("Igazolando", nil, "Igazolandó hiányzás"), ("Igazolt", 7, "Igazolt késés (7 perc)"),
    ] as [(String, Int?, String)])
    func absenceLabel(_ state: String, _ late: Int?, _ label: String) throws {
        let a: [Mulasztas] = try decode(#"[{"Uid":"1","Tantargy":\#(subjectJSON),"Datum":"2025-11-09T23:00:00Z","IgazolasAllapota":"\#(state)","KesesPercben":\#(late.map(String.init) ?? "null")}]"#)
        #expect(a[0].stateLabel == label)
        #expect(a[0].stateShort == String(label.split(separator: " ")[0]))
    }

    @Test("grade text: number, percent, text grade, short text grade")
    func gradeDisplay() throws {
        let g = try grades(gradeJSON("a", 4, 100),
                           gradeJSON("b", 87, 100, valueType: "Szazalekos"),
                           gradeJSON("c", nil, nil, valueType: "Szoveges", text: "Nem írt"),
                           gradeJSON("d", nil, nil, valueType: "Szoveges", text: "Kiválóan megfelelt", short: "KM"))
        #expect(g.map(\.display) == ["4", "87%", "Nem írt", "KM"])
    }

    @Test("lessons: cancelled by state or as an empty slot; title from the subject, else the name")
    func lessonTexts() throws {
        let day = budapest(2026, 11, 23)
        #expect(lesson("a", day: day, from: 480, cancelled: true).isCancelled)
        var empty = lesson("b", day: day, from: 480)
        empty.tipus.nev = "UresOra"
        #expect(empty.isCancelled)
        var noSubject = lesson("c", day: day, from: 480)
        noSubject.tantargy = nil
        noSubject.nev = "osztályfőnöki"
        #expect(noSubject.title == "Osztályfőnöki")
        noSubject.nev = nil
        #expect(noSubject.title == "Óra")
    }

    @Test("messages: notice board, teacher notes and inbox in one list, newest first")
    func messages() throws {
        var s = Snapshot()
        s.notices = try decode(#"[{"Uid":"1","Cim":"Kirándulás","RogzitoNeve":"Kovács Anna","ErvenyessegKezdete":"2026-11-10T08:00:00Z","Tartalom":"<p>Hétfőn</p>"}]"#)
        s.notes = try decode(#"[{"Uid":"1","Datum":"2026-11-12T08:00:00Z","Tipus":{"Leiras":"Dicséret"},"Tartalom":"sima","TartalomFormazott":"<b>formázott</b>"}]"#)
        s.inbox = try decode("[\(inboxJSON(5, subject: "Szülői", text: "eleje"))]")
        s.inboxBodies = ["5": "teljes"]
        let m = s.messages
        #expect(m.map(\.id) == ["p5", "f1", "n1"])
        #expect(m[1].title == "Dicséret" && m[1].html == "<b>formázott</b>", "a note without a title is named by its type")
        #expect(m[0].html == "teljes" && m[0].author == "Varga Szabolcs")
        #expect(m[2].title == "Kirándulás" && m[2].author == "Kovács Anna")
    }

    @MainActor @Test("message HTML: no images or scripts are loaded, colours are dropped")
    func renderHTML() throws {
        let t = try #require(HTMLText.render(#"<p style="color:red">Szia <b>Elek</b></p><img src="https://example.com/x.png"><script>alert(1)</script>"#))
        let s = String(t.characters)
        #expect(s == "Szia Elek")
        #expect(!t.runs.contains { $0.uiKit.foregroundColor != nil })
    }

    @Test("Hungarian dates and calendar helpers")
    func dates() {
        let d = budapest(2026, 11, 25, 14, 30)
        #expect(d.startOfWeek == budapest(2026, 11, 23))
        #expect(d.startOfMonth == budapest(2026, 11, 1))
        #expect(budapest(2026, 11, 22).startOfWeek == budapest(2026, 11, 16), "the week starts on Monday")
        #expect(budapest(2026, 3, 28).adding(days: 1) == budapest(2026, 3, 29), "across the clock change")
        #expect(d.hu("MMMd") == "nov. 25.")
    }
}

@Suite("Notifications: the other kinds")
struct NotifierKindsTests {
    let now = budapest(2026, 11, 23, 7)

    func base() -> Snapshot {
        var s = Snapshot()
        s.studentName = "Teszt Elek"
        s.inbox = []
        s.updated = now
        return s
    }

    @Test("homework, tests, absences, messages: one alert each, only when switched on")
    func kinds() throws {
        let old = base()
        var new = base()
        new.homework = try decode(#"[{"Uid":"h1","Tantargy":\#(subjectJSON),"FeladasDatuma":"2026-11-20T08:00:00Z","HataridoDatuma":"2026-11-25T08:00:00Z"}]"#)
        new.tests = try decode(#"[{"Uid":"t1","Datum":"2026-11-26T08:00:00Z","BejelentesDatuma":"2026-11-20T08:00:00Z","Tantargy":\#(subjectJSON),"Temaja":"Törtek"}]"#)
        new.absences = try decode(#"[{"Uid":"a1","Tantargy":\#(subjectJSON),"Datum":"2026-11-20T08:00:00Z","IgazolasAllapota":"Igazolando"}]"#)
        new.inbox = try decode("[\(inboxJSON(9, subject: "Fogadóóra"))]")
        let all = Notifier.changes(old: old, new: new, now: now, enabled: { _ in true }, surprise: false, isHidden: { _ in false })
        #expect(all == [
            .init(id: "homework", title: "Új házi feladat", lines: ["Matematika"]),
            .init(id: "tests", title: "Új számonkérés", lines: ["Matematika: Törtek"]),
            .init(id: "absences", title: "Új hiányzás/késés", lines: ["Matematika: Igazolandó hiányzás"]),
            .init(id: "messages", title: "Új üzenet", lines: ["Fogadóóra"]),
        ])
        for (key, id) in [("notifyHomework", "homework"), ("notifyAbsences", "absences"), ("notifyMessages", "messages")] {
            let some = Notifier.changes(old: old, new: new, now: now, enabled: { $0 != key }, surprise: false, isHidden: { _ in false })
            #expect(!some.map(\.id).contains(id))
        }
        #expect(Notifier.changes(old: new, new: new, now: now, enabled: { _ in true }, surprise: false, isHidden: { _ in false }).isEmpty,
                "nothing new, nothing sent")
    }

    @Test("a substitution in a cancelled lesson isn't announced twice; past lessons aren't announced")
    func substitutionRules() {
        let day = budapest(2026, 11, 23)
        var old = base()
        old.lessons = [lesson("a", day: day, from: 480), lesson("p", day: budapest(2026, 11, 20), from: 480)]
        var new = base()
        new.lessons = [lesson("a", day: day, from: 480, cancelled: true, substitute: "X Y"),
                       lesson("p", day: budapest(2026, 11, 20), from: 480, substitute: "X Y")]
        let a = Notifier.changes(old: old, new: new, now: now, enabled: { _ in true }, surprise: false, isHidden: { _ in false })
        #expect(a.map(\.id) == ["cancelled"])
    }

    @Test("no timetable before (first sync with lessons): no lesson alerts")
    func noLessonBaseline() {
        var new = base()
        new.lessons = [lesson("a", day: budapest(2026, 11, 23), from: 480, cancelled: true)]
        #expect(Notifier.changes(old: base(), new: new, now: now, enabled: { _ in true }, surprise: false, isHidden: { _ in false }).isEmpty)
    }
}
