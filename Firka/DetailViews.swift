import SwiftUI

// MARK: - Detail screens

struct LessonDetail: View {
    let lesson: Ora
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section {
                LabeledContent("Időpont", value: "\(lesson.kezdetIdopont.hu("MMMMd EEEE")) \(lesson.kezdetIdopont.time)–\(lesson.vegIdopont.time)")
                if let n = lesson.oraszam { LabeledContent("Óraszám", value: "\(n).") }
                if let r = lesson.teremNeve { LabeledContent("Terem", value: r) }
                if let t = lesson.tanarNeve { LabeledContent("Tanár", value: t.renamedTeacher) }
                if let s = lesson.helyettesTanarNeve { LabeledContent("Helyettes", value: s.renamedTeacher).foregroundStyle(Color.substituted) }
                if let a = lesson.allapot?.leiras { LabeledContent("Állapot", value: a) }
                if let p = lesson.tanuloJelenlet?.leiras { LabeledContent("Jelenlét", value: p) }
            }
            if let t = lesson.tema, !t.isEmpty { Section("Téma") { Text(t) } }
            if !lesson.isEvent {
                Section {
                    HideLessonButton(lesson: lesson)
                } footer: {
                    Text("Ha az óra a valóságban nincs megtartva, de a KRÉTA mutatja.")
                }
            }
            if let test = lesson.announcedTest(in: store.data.tests) {
                Section("Számonkérés") { TestRow(test: test) }
            }
            if let uid = lesson.haziFeladatUid, let hw = store.data.homework.first(where: { $0.uid == uid }) {
                Section("Házi feladat") { HTMLText(html: hw.szoveg ?? "") }
            }
        }
        .navigationTitle(lesson.title)
    }
}

struct GradeDetail: View {
    let grade: Ertekeles

    var body: some View {
        List {
            HStack {
                Spacer()
                GradeBadge(text: grade.display, grade: grade.level, size: 90)
                Spacer()
            }
            .listRowBackground(Color.clear)
            Section {
                if let t = grade.tema { LabeledContent("Téma", value: t) }
                LabeledContent("Típus", value: grade.tipus.leiras ?? "")
                if let m = grade.mod?.leiras { LabeledContent("Mód", value: m) }
                if let w = grade.sulySzazalekErteke { LabeledContent("Súly", value: "\(w)%") }
                if let s = grade.szovegesErtek { LabeledContent("Érték", value: s) }
                if let t = grade.ertekeloTanarNeve { LabeledContent("Tanár", value: t.renamedTeacher) }
                LabeledContent("Dátum", value: grade.keszitesDatuma.hu("yMMMMd"))
                LabeledContent("Rögzítve", value: grade.rogzitesDatuma.hu("yMMMMd"))
            }
        }
        .navigationTitle(grade.tantargy.name)
    }
}

struct HomeworkDetail: View {
    let hw: HaziFeladat

    var body: some View {
        List {
            Section {
                LabeledContent("Feladva", value: hw.feladasDatuma.hu("MMMMd EEEE"))
                LabeledContent("Határidő", value: hw.hataridoDatuma.hu("MMMMd EEEE"))
                if hw.isMegoldva == true { LabeledContent("Állapot", value: "Megoldva") }
                if let t = hw.rogzitoTanarNeve { LabeledContent("Tanár", value: t.renamedTeacher) }
            }
            Section("Feladat") { HTMLText(html: hw.szoveg ?? "") }
        }
        .navigationTitle(hw.tantargy.name)
    }
}

struct TestDetail: View {
    let test: Szamonkeres

    var body: some View {
        List {
            LabeledContent("Dátum", value: test.datum.hu("MMMMd EEEE"))
            if let n = test.orarendiOraOraszama { LabeledContent("Óra", value: "\(n).") }
            if let m = test.modja?.leiras { LabeledContent("Mód", value: m) }
            if let t = test.temaja { LabeledContent("Téma", value: t) }
            if let t = test.rogzitoTanarNeve { LabeledContent("Tanár", value: t.renamedTeacher) }
            LabeledContent("Bejelentve", value: test.bejelentesDatuma.hu("MMMMd"))
        }
        .navigationTitle(test.tantargy.name)
    }
}
