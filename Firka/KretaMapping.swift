import Foundation

// KRÉTA's API shapes (Kreta.swift) onto the app's own models (Domain.swift). The only place that knows what
// KRÉTA's codes mean ("Elmaradt", "UresOra", "felevi_jegy_ertekeles", "Igazolando" …).

extension Subject {
    init(kreta t: Tantargy) { self.init(id: t.uid, raw: t.nev, order: t.sortIndex) }
}

extension Lesson {
    init(kreta o: Ora) {
        let event = o.tipus.nev == "TanevRendjeEsemeny"
        self.init(id: o.uid, kind: event ? .event : .lesson, start: o.kezdetIdopont, end: o.vegIdopont,
                  subject: o.tantargy.map(Subject.init(kreta:)), name: o.nev ?? o.tipus.leiras, number: o.oraszam,
                  teacher: o.tanarNeve, substitute: o.helyettesTanarNeve, room: o.teremNeve, topic: o.tema,
                  cancelled: (o.allapot?.nev ?? "").lowercased().contains("elmarad") || o.tipus.nev == "UresOra",
                  stateText: o.allapot?.leiras, attendance: o.tanuloJelenlet?.leiras,
                  testID: o.bejelentettSzamonkeresUid, homeworkID: o.haziFeladatUid)
    }
}

extension Grade {
    init(kreta g: Ertekeles) {
        let type = g.tipus.nev ?? ""
        let kind: Kind = type == "evkozi_jegy_ertekeles" ? .midYear : type.contains("felevi") ? .halfYear
            : type.contains("evvegi") ? .yearEnd : .other
        let value: Value = switch g.ertekFajta.nev { case "Osztalyzat": .grade; case "Szazalekos": .percent; default: .text }
        self.init(id: g.uid, date: g.keszitesDatuma, recorded: g.rogzitesDatuma, subject: Subject(kreta: g.tantargy),
                  kind: kind, value: value, number: g.szamErtek, text: g.szovegesErtek, shortText: g.szovegesErtekelesRovidNev,
                  weight: g.sulySzazalekErteke, credit: nil, topic: g.tema, mode: g.mod?.leiras, teacher: g.ertekeloTanarNeve,
                  kindText: g.tipus.leiras)
    }
}

extension Absence {
    init(kreta a: Mulasztas) {
        let state: State = switch a.igazolasAllapota { case "Igazolt": .excused; case "Igazolatlan": .unexcused; default: .pending }
        self.init(id: a.uid, subject: Subject(kreta: a.tantargy), date: a.datum, lessonStart: a.ora?.kezdoDatum,
                  lessonEnd: a.ora?.vegDatum, lessonNumber: a.ora?.oraszam,
                  late: a.tipus?.nev?.lowercased() == "keses" || (a.kesesPercben ?? 0) > 0, lateMinutes: a.kesesPercben,
                  state: state, excuse: a.igazolasTipusa?.leiras, recordedBy: a.rogzitoTanarNeve)
    }
}

extension Homework {
    init(kreta h: HaziFeladat) {
        self.init(id: h.uid, subject: Subject(kreta: h.tantargy), teacher: h.rogzitoTanarNeve, html: h.szoveg,
                  given: h.feladasDatuma, due: h.hataridoDatuma, done: h.isMegoldva)
    }
}

extension AnnouncedTest {
    init(kreta t: Szamonkeres) {
        self.init(id: t.uid, date: t.datum, announced: t.bejelentesDatuma, subject: Subject(kreta: t.tantargy),
                  lessonNumber: t.orarendiOraOraszama, topic: t.temaja, mode: t.modja?.leiras, teacher: t.rogzitoTanarNeve)
    }
}

extension Attachment {
    init(kreta c: Csatolmany) { self.init(id: String(c.azonosito), name: c.fajlNev, url: c.downloadURL) }
}

extension Message {
    init(kreta n: FaliujsagElem) {
        self.init(id: "n" + n.uid, title: n.cim ?? "Üzenet", author: n.rogzitoNeve, date: n.ervenyessegKezdete, html: n.tartalom ?? "")
    }

    init(kreta f: Feljegyzes) {
        self.init(id: "f" + f.uid, title: f.cim ?? f.tipus?.leiras ?? "Feljegyzés", author: f.keszitoTanarNeve, date: f.datum,
                  html: f.tartalomFormazott ?? f.tartalom ?? "")
    }

    /// The list only has the first 100 characters; AppStore.fullMessage downloads the rest.
    init(kreta p: PostaladaElem) {
        let u = p.uzenet
        self.init(id: p.id, title: u.targy ?? "Üzenet", author: u.feladoNev, authorRole: u.feladoTitulus, date: u.kuldesDatum,
                  html: u.szoveg ?? "", attachments: (u.csatolmanyok ?? []).map(Attachment.init(kreta:)),
                  unread: p.isElolvasva == false)
    }
}
