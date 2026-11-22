#if DEBUG
import Foundation

// Fake data for trying the app without a KRÉTA account (debug builds only).
extension Snapshot {
    static var demo: Snapshot {
        let names = ["matematika", "magyar nyelv és irodalom", "történelem", "angol nyelv", "fizika", "biológia", "informatika", "testnevelés"]
        let subjects = names.enumerated().map { i, n in Tantargy(uid: "s\(i)", nev: n, sortIndex: i) }
        let teachers = ["Kovács Anna", "Nagy Péter", "Szabó Éva", "Tóth Gábor", "Horváth Zsuzsa", "Varga Béla", "Kiss Dóra", "Molnár Ádám"]
        let nud = { (n: String, l: String) in NUD(uid: n, nev: n, leiras: l) }
        let now = Date()
        let week = now.startOfWeek

        var lessons: [Ora] = []
        for d in 0..<14 where d % 7 < 5 {
            let day = week.adding(days: d)
            for n in 1...6 {
                let s = subjects[(d * 3 + n) % subjects.count]
                let start = Calendar.hu.date(bySettingHour: 8, minute: 0, second: 0, of: day)!.addingTimeInterval(Double(n - 1) * 55 * 60)
                let cancelled = d == 2 && n == 5
                lessons.append(Ora(uid: "l\(d)-\(n)", datum: day, kezdetIdopont: start, vegIdopont: start.addingTimeInterval(45 * 60),
                                   oraszam: n, tantargy: s, tanarNeve: teachers[Int(s.uid.dropFirst())!],
                                   helyettesTanarNeve: d == 1 && n == 3 ? "Fekete Lili" : nil, teremNeve: "\(100 + n * 7)",
                                   tema: "Gyakorlás", tipus: nud("TanitasiOra", "Tanítási óra"),
                                   allapot: cancelled ? nud("Elmaradt", "Elmaradt") : nud("Naplozott", "Naplózott"),
                                   bejelentettSzamonkeresUid: d == 3 && n == 2 ? "t0" : nil,
                                   haziFeladatUid: d == 4 && n == 1 ? "h0" : nil))
            }
        }

        let values = [5, 4, 5, 3, 4, 5, 2, 4, 5, 5, 4, 3, 5, 4, 4, 5, 3, 5, 4, 5, 1, 4, 5, 4, 3, 5, 5, 4, 2, 5, 4, 5]
        var grades = values.enumerated().map { i, v in
            let s = subjects[i % subjects.count]
            let date = now.adding(days: -(values.count - i) * 2)
            return Ertekeles(uid: "g\(i)", rogzitesDatuma: date, keszitesDatuma: date, tantargy: s,
                             tema: ["Témazáró", "Felelet", "Házi dolgozat", "Röpdolgozat"][i % 4],
                             tipus: nud("evkozi_jegy_ertekeles", "Évközi jegy"), mod: nud("irasbeli", "Írásbeli"),
                             ertekFajta: nud("Osztalyzat", "Osztályzat"), ertekeloTanarNeve: teachers[i % teachers.count],
                             szamErtek: v, szovegesErtek: nil, sulySzazalekErteke: i % 4 == 0 ? 200 : 100)
        }
        grades.append(Ertekeles(uid: "gs", rogzitesDatuma: now.adding(days: -3), keszitesDatuma: now.adding(days: -3), tantargy: subjects[7],
                                tipus: nud("evkozi_jegy_ertekeles", "Évközi jegy"), ertekFajta: nud("Szoveges", "Szöveges"),
                                ertekeloTanarNeve: teachers[7], szovegesErtek: "Kiválóan teljesített", szovegesErtekelesRovidNev: "Kiváló"))

        let absences = [
            Mulasztas(uid: "a0", tantargy: subjects[0], ora: .init(kezdoDatum: now.adding(days: -8), vegDatum: now.adding(days: -8), oraszam: 1),
                      datum: now.adding(days: -8), tipus: nud("hianyzas", "Hiányzás"), igazolasAllapota: "Igazolt", igazolasTipusa: nud("Orvosi", "Orvosi igazolás")),
            Mulasztas(uid: "a1", tantargy: subjects[1], ora: .init(kezdoDatum: now.adding(days: -8), vegDatum: now.adding(days: -8), oraszam: 2),
                      datum: now.adding(days: -8), tipus: nud("hianyzas", "Hiányzás"), igazolasAllapota: "Igazolt", igazolasTipusa: nud("Orvosi", "Orvosi igazolás")),
            Mulasztas(uid: "a2", tantargy: subjects[3], ora: .init(kezdoDatum: now.adding(days: -2), vegDatum: now.adding(days: -2), oraszam: 1),
                      datum: now.adding(days: -2), tipus: nud("keses", "Késés"), kesesPercben: 7, igazolasAllapota: "Igazolando"),
        ]

        return Snapshot(
            studentName: "Teszt Elek", schoolName: "Demó Gimnázium",
            grades: grades, lessons: lessons, absences: absences,
            homework: [HaziFeladat(uid: "h0", tantargy: subjects[0], rogzitoTanarNeve: teachers[0],
                                   szoveg: "<p>Tankönyv <b>42. oldal</b> 3–7. feladat.</p><ul><li>a) rész</li><li>b) rész</li></ul>",
                                   feladasDatuma: now.adding(days: -1), hataridoDatuma: week.adding(days: 4))],
            tests: [Szamonkeres(uid: "t0", datum: week.adding(days: 3), bejelentesDatuma: now.adding(days: -5), rogzitoTanarNeve: teachers[2],
                                orarendiOraOraszama: 2, tantargy: subjects[2], temaja: "Az Árpád-kor", modja: nud("irasbeli_temazaro", "Írásbeli témazáró"))],
            notices: [FaliujsagElem(uid: "n0", rogzitoNeve: "Igazgatóság", ervenyessegKezdete: now.adding(days: -1),
                                    cim: "Szalagavató próba", tartalom: "<p>Pénteken 14:00-tól próba a tornateremben.</p>")],
            notes: [Feljegyzes(uid: "f0", cim: "Dicséret", datum: now.adding(days: -6), keszitoTanarNeve: teachers[4],
                               tartalom: "Kiemelkedő munka a fizika versenyen.", tipus: nud("Dicseret", "Dicséret"))],
            updated: now)
    }
}
#endif
