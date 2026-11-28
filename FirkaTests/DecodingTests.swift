import Foundation
import Testing
@testable import Firka

@Suite("KRÉTA JSON decoding")
struct DecodingTests {
    @Test("dates in every format KRÉTA uses", arguments: [
        "2025-11-21T07:00:00Z", "2025-11-21T07:00:00.123Z", "2025-11-21T08:00:00", "2025-11-21T08:00:00.5", "2025-11-21",
    ])
    func dates(_ s: String) {
        #expect(Kreta.parseDate(s) != nil)
    }

    @Test func badDateIsRejected() {
        #expect(Kreta.parseDate("nem dátum") == nil)
        #expect(throws: DecodingError.self) { let _: [Ertekeles] = try decode("[\(gradeJSON("x", 5, 100, date: "tegnap"))]") }
    }

    @Test func grade() throws {
        let g = try (decode("[\(gradeJSON("a", 5, 200))]") as [Ertekeles])[0]
        #expect(g.szamErtek == 5 && g.sulySzazalekErteke == 200 && g.tantargy.uid == "1,MAT")
        #expect(g.mod?.leiras == "Írásbeli röpdolgozat" && g.ertekeloTanarNeve == "Kovács Anna")
    }

    @Test("one malformed item doesn't wipe the list")
    func lossyList() throws {
        let broken = gradeJSON("bad", 3, 100).replacingOccurrences(of: #""Tipus":{"Uid":"1,evkozi_jegy_ertekeles","Nev":"evkozi_jegy_ertekeles","Leiras":"x"},"#, with: "")
        let items: [Lossy<Ertekeles>] = try decode("[\(gradeJSON("ok1", 5, 100)),\(broken),\(gradeJSON("ok2", 4, 100))]")
        #expect(items.compactMap(\.value).map(\.uid) == ["ok1", "ok2"])
    }

    @Test func lessonAndSchoolEvent() throws {
        let lessons: [Ora] = try decode(#"""
        [{"Uid":"1234,TanitasiOra,2025-11-21T00:00:00Z","Datum":"2025-11-20T23:00:00Z","KezdetIdopont":"2025-11-21T07:00:00Z","VegIdopont":"2025-11-21T07:45:00Z","Nev":"matematika","Oraszam":1,"Tantargy":\#(subjectJSON),"TanarNeve":"Kovács Anna","TeremNeve":"112","Tipus":{"Uid":"2,TanitasiOra","Nev":"TanitasiOra","Leiras":"Tanítási óra"},"TanuloJelenlet":null,"Allapot":{"Uid":"2,Elmaradt","Nev":"Elmaradt","Leiras":"Elmaradt"},"HelyettesTanarNeve":null,"Csatolmanyok":[]},
         {"Uid":"9,TanevRendjeEsemeny","Datum":"2025-11-20T23:00:00Z","KezdetIdopont":"2025-11-20T23:00:00Z","VegIdopont":"2025-11-20T23:00:00Z","Nev":"Őszi szünet (Nem órarendi nap) (Hétfő)","Tipus":{"Uid":"3","Nev":"TanevRendjeEsemeny","Leiras":"x"},"Allapot":null,"Csatolmanyok":[]}]
        """#)
        let l = lessons.map(Lesson.init(kreta:))
        #expect(l[0].cancelled && !l[0].isEvent && lessons[0].oraszam == 1)
        #expect(lessons[0].vegIdopont.timeIntervalSince(lessons[0].kezdetIdopont) == 45 * 60)
        #expect(l[1].isEvent && lessons[1].tantargy == nil && !l[1].cancelled)
    }

    @Test func absenceHomeworkTestStudent() throws {
        let a: [Mulasztas] = try decode(#"[{"Uid":"77","Tantargy":\#(subjectJSON),"Ora":{"KezdoDatum":"2025-11-10T07:00:00Z","VegDatum":"2025-11-10T07:45:00Z","Oraszam":1},"Datum":"2025-11-09T23:00:00Z","Tipus":{"Nev":"keses","Leiras":"Késés"},"KesesPercben":5,"IgazolasAllapota":"Igazolando","IgazolasTipusa":null}]"#)
        #expect(Absence(kreta: a[0]).late && Absence(kreta: a[0]).stateLabel == "Igazolandó késés (5 perc)")

        let h: [HaziFeladat] = try decode(#"[{"Uid":"5","Tantargy":\#(subjectJSON),"Szoveg":"<p>42. oldal</p>","FeladasDatuma":"2025-11-19T23:00:00Z","HataridoDatuma":"2025-11-23T23:00:00Z","IsMegoldva":false}]"#)
        #expect(h[0].szoveg == "<p>42. oldal</p>")

        let t: [Szamonkeres] = try decode(#"[{"Uid":"6","Datum":"2025-11-24T23:00:00Z","BejelentesDatuma":"2025-11-17T10:00:00Z","OrarendiOraOraszama":2,"Tantargy":\#(subjectJSON),"Temaja":"Törtek","Modja":{"Nev":"irasbeli_temazaro","Leiras":"Írásbeli témazáró"}}]"#)
        #expect(t[0].modja?.leiras == "Írásbeli témazáró")

        let s: TanuloAdatlap = try decode(#"{"Nev":"Teszt Elek","IntezmenyNev":"Teszt Gimnázium","Cimek":[],"Gondviselok":[]}"#)
        #expect(s.nev == "Teszt Elek")
    }

    @Test func classAveragesAndGroups() throws {
        let avg: [OsztalyAtlag] = try decode(#"[{"Uid":"1","Tantargy":\#(subjectJSON),"TanuloAtlag":4.5,"OsztalyCsoportAtlag":3.87}]"#)
        #expect(avg[0].osztalyCsoportAtlag == 3.87)
        let groups: [OsztalyCsoport] = try decode(#"[{"Uid":"9","OktatasNevelesiFeladat":{"Uid":"1,Gimnazium","Nev":"Gimnazium"},"IsAktiv":true}]"#)
        #expect(groups[0].oktatasNevelesiFeladat?.uid == "1,Gimnazium")
    }

    @Test("teacher message (postaláda) with attachment, camelCase keys")
    func inbox() throws {
        let m: [PostaladaElem] = try decode(#"[{"azonosito":334594519,"isElolvasva":false,"isToroltElem":false,"tipus":{"kod":"BEERKEZETT"},"uzenet":{"azonosito":60621037,"kuldesDatum":"2026-11-18T09:50:50","feladoNev":"Varga Szabolcs","szoveg":"<p>Kedves","targy":"Ne gyújts rá","csatolmanyok":[{"azonosito":98472557,"fajlNev":"Hírlevél.pdf"}]}}]"#)
        #expect(m[0].id == "p334594519" && m[0].tipus?.kod == "BEERKEZETT")
        #expect(m[0].uzenet.csatolmanyok?.first?.downloadURL.absoluteString == "https://eugyintezes.e-kreta.hu/api/v1/dokumentumok/uzenetek/98472557")
    }

    @Test func snapshotRoundTrip() throws {
        var s = Snapshot()
        s.studentName = "Teszt Elek"
        s.grades = try grades(gradeJSON("a", 5, 100))
        s.lessons = [lesson("l1", day: budapest(2026, 11, 23), from: 8 * 60)]
        s.messageList = try FirkaTests.inbox("[\(inboxJSON(5, read: false))]")
        s.messageSources = ["p"]
        s.updated = Date(timeIntervalSince1970: 1_800_000_000)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = try d.decode(Snapshot.self, from: try e.encode(s))
        #expect(back.studentName == s.studentName && back.grades == s.grades && back.lessons == s.lessons && back.updated == s.updated)
        #expect(back.messageList == s.messageList && back.messageSources == s.messageSources)
    }
}

