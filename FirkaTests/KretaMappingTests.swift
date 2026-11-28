import Foundation
import Testing
@testable import Firka

/// KRÉTA's shapes onto the app's own models (Domain.swift): what the screens get from each KRÉTA field.
@Suite("KRÉTA → the app's models")
struct KretaMappingTests {
    let math = Subject(id: "1,MAT", raw: "matematika", order: 0)

    @Test("a lesson: times, teacher, room, substitute, state; links to its test and homework")
    func lesson() throws {
        let o: Ora = try decode(#"{"Uid":"l1","Datum":"2026-11-22T23:00:00Z","KezdetIdopont":"2026-11-23T07:00:00Z","VegIdopont":"2026-11-23T07:45:00Z","Nev":"matematika","Oraszam":1,"Tantargy":\#(subjectJSON),"TanarNeve":"Kovács Anna","HelyettesTanarNeve":"Fekete Lili","TeremNeve":"101","Tema":"Törtek","Tipus":{"Nev":"TanitasiOra"},"Allapot":{"Nev":"Naplozott","Leiras":"Naplózott"},"TanuloJelenlet":{"Leiras":"Jelen"},"BejelentettSzamonkeresUid":"t1","HaziFeladatUid":"h1"}"#)
        let l = Lesson(kreta: o)
        #expect(l.id == "l1" && l.kind == .lesson && !l.cancelled)
        #expect(l.start == o.kezdetIdopont && l.end == o.vegIdopont && l.number == 1)
        #expect(l.subject == math && l.name == "matematika")
        #expect(l.teacher == "Kovács Anna" && l.substitute == "Fekete Lili" && l.room == "101" && l.topic == "Törtek")
        #expect(l.stateText == "Naplózott" && l.attendance == "Jelen" && l.testID == "t1" && l.homeworkID == "h1")
    }

    @Test("cancelled: an Elmaradt state or an empty slot (UresOra); a school-calendar event is an event with its name")
    func lessonKinds() throws {
        let gone: Ora = try decode(lessonJSON("a", start: .now, cancelled: true))
        #expect(Lesson(kreta: gone).cancelled)
        let empty: Ora = try decode(#"{"Uid":"b","Datum":"2026-11-22T23:00:00Z","KezdetIdopont":"2026-11-23T07:00:00Z","VegIdopont":"2026-11-23T07:45:00Z","Tipus":{"Nev":"UresOra"}}"#)
        #expect(Lesson(kreta: empty).cancelled)
        let event: Ora = try decode(#"{"Uid":"e","Datum":"2026-11-22T23:00:00Z","KezdetIdopont":"2026-11-22T23:00:00Z","VegIdopont":"2026-11-23T22:59:00Z","Tipus":{"Nev":"TanevRendjeEsemeny","Leiras":"Tanítási szünet"}}"#)
        let e = Lesson(kreta: event)
        #expect(e.kind == .event && e.name == "Tanítási szünet" && e.subject == nil)
    }

    @Test("grades: kind (mid-year, half-year, year-end), value type, weight, mode, teacher")
    func gradeKinds() throws {
        let g = try grades(gradeJSON("a", 4, 200), gradeJSON("b", 80, 100, valueType: "Szazalekos"),
                                 gradeJSON("c", nil, nil, valueType: "Szoveges", text: "Kiválóan teljesített", short: "Kiváló"),
                                 gradeJSON("d", 5, nil, kind: "felevi_jegy_ertekeles"), gradeJSON("e", 4, nil, kind: "evvegi_jegy_ertekeles"))
        #expect(g[0].kind == .midYear && g[0].value == .grade && g[0].number == 4 && g[0].weight == 200)
        #expect(g[0].subject == math && g[0].topic == "Törtek" && g[0].mode == "Írásbeli röpdolgozat" && g[0].teacher == "Kovács Anna")
        #expect(g[0].date == g[0].recorded && g[0].credit == nil)
        #expect(g[1].value == .percent && g[1].number == 80)
        #expect(g[2].value == .text && g[2].text == "Kiválóan teljesített" && g[2].shortText == "Kiváló")
        #expect(g[3].kind == .halfYear && g[4].kind == .yearEnd)
    }

    @Test("absences: late or not (by type or minutes), the excuse state, how it was excused, the lesson's times")
    func absences() throws {
        let a: [Mulasztas] = try decode(#"[{"Uid":"1","Tantargy":\#(subjectJSON),"Ora":{"KezdoDatum":"2026-11-23T07:00:00Z","VegDatum":"2026-11-23T07:45:00Z","Oraszam":1},"Datum":"2026-11-22T23:00:00Z","RogzitoTanarNeve":"Kovács Anna","Tipus":{"Nev":"hianyzas"},"IgazolasAllapota":"Igazolt","IgazolasTipusa":{"Leiras":"Orvosi igazolás"}},{"Uid":"2","Tantargy":\#(subjectJSON),"Datum":"2026-11-22T23:00:00Z","Tipus":{"Nev":"keses"},"KesesPercben":7,"IgazolasAllapota":"Igazolando"},{"Uid":"3","Tantargy":\#(subjectJSON),"Datum":"2026-11-22T23:00:00Z","KesesPercben":3,"IgazolasAllapota":"Igazolatlan"}]"#)
        let m = a.map(Absence.init(kreta:))
        #expect(!m[0].late && m[0].state == .excused && m[0].excuse == "Orvosi igazolás" && m[0].recordedBy == "Kovács Anna")
        #expect(m[0].lessonNumber == 1 && m[0].lessonStart == a[0].ora?.kezdoDatum && m[0].lessonEnd == a[0].ora?.vegDatum)
        #expect(m[1].late && m[1].lateMinutes == 7 && m[1].state == .pending)
        #expect(m[2].late && m[2].state == .unexcused, "minutes alone make it a lateness")
    }

    @Test("homework and announced tests")
    func homeworkAndTests() throws {
        let h: HaziFeladat = try decode(#"{"Uid":"5","Tantargy":\#(subjectJSON),"RogzitoTanarNeve":"Kovács Anna","Szoveg":"<p>42. oldal</p>","FeladasDatuma":"2025-11-19T23:00:00Z","HataridoDatuma":"2025-11-23T23:00:00Z","IsMegoldva":true}"#)
        let hw = Homework(kreta: h)
        #expect(hw.id == "5" && hw.subject == math && hw.html == "<p>42. oldal</p>" && hw.teacher == "Kovács Anna" && hw.done == true)
        #expect(hw.given == h.feladasDatuma && hw.due == h.hataridoDatuma)
        let t: Szamonkeres = try decode(#"{"Uid":"6","Datum":"2025-11-24T23:00:00Z","BejelentesDatuma":"2025-11-17T10:00:00Z","RogzitoTanarNeve":"Kiss Ede","OrarendiOraOraszama":2,"Tantargy":\#(subjectJSON),"Temaja":"Törtek","Modja":{"Nev":"irasbeli_temazaro","Leiras":"Írásbeli témazáró"}}"#)
        let test = AnnouncedTest(kreta: t)
        #expect(test.id == "6" && test.lessonNumber == 2 && test.topic == "Törtek" && test.mode == "Írásbeli témazáró" && test.teacher == "Kiss Ede")
        #expect(test.date == t.datum && test.announced == t.bejelentesDatuma && test.subject == math)
    }

    @Test("an attachment of a teacher message: its name and download address")
    func attachment() throws {
        let c: Csatolmany = try decode(#"{"azonosito":98472557,"fajlNev":"Hírlevél.pdf"}"#)
        let a = Attachment(kreta: c)
        #expect(a.id == "98472557" && a.name == "Hírlevél.pdf")
        #expect(a.url.absoluteString == "https://eugyintezes.e-kreta.hu/api/v1/dokumentumok/uzenetek/98472557")
    }
}
