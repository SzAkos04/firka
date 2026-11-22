import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                list(now: ctx.date)
            }
            .navigationTitle(greeting)
            .refreshable { await store.refresh() }
            .navigationDestination(for: Ora.self) { LessonDetail(lesson: $0) }
            .navigationDestination(for: Ertekeles.self) { GradeDetail(grade: $0) }
            .navigationDestination(for: HaziFeladat.self) { HomeworkDetail(hw: $0) }
            .navigationDestination(for: Szamonkeres.self) { TestDetail(test: $0) }
        }
    }

    private var greeting: String {
        HomeLogic.greeting(name: store.data.studentName, hour: Calendar.hu.component(.hour, from: Date()))
    }

    @ViewBuilder
    private func list(now: Date) -> some View {
        let data = store.data
        let (current, next, day, dayLessons) = HomeLogic.today(data.lessons, now: now, isHidden: HiddenLessons.shared.isHidden)
        let tests = HomeLogic.split(data.tests, today: now.startOfDay, date: \.datum).upcoming
        let homework = HomeLogic.split(data.homework, today: now.startOfDay, date: \.hataridoDatuma).upcoming
        let recent = store.visibleGrades.sorted { $0.keszitesDatuma > $1.keszitesDatuma }.prefix(5)

        List {
            if let err = store.error {
                Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote)
            }

            NewGradesSection()

            Section {
                if let current {
                    NowCard(title: "Most", lesson: current, now: now)
                } else if let next {
                    NowCard(title: next.kezdetIdopont.startOfDay == now.startOfDay ? "Következő óra" : "Következő óra – \(next.kezdetIdopont.hu("EEEE"))",
                            lesson: next, now: now)
                } else {
                    Text("Nincs több óra a következő két hétben 🎉").foregroundStyle(.secondary)
                }
            }

            if !dayLessons.isEmpty {
                Section(day == now.startOfDay ? "Mai órák" : day.hu("EEEE, MMMM d.").capitalizedFirst) {
                    ForEach(dayLessons) { l in
                        NavigationLink(value: l) { LessonRow(lesson: l, active: l.id == current?.id) }
                    }
                }
            }

            if !tests.isEmpty {
                Section("Közelgő számonkérések") {
                    ForEach(tests.prefix(5)) { t in NavigationLink(value: t) { TestRow(test: t) } }
                }
            }

            if !homework.isEmpty {
                Section("Házi feladatok") {
                    ForEach(homework.prefix(5)) { h in NavigationLink(value: h) { HomeworkRow(hw: h) } }
                }
            }

            if !recent.isEmpty {
                Section("Legutóbbi jegyek") {
                    ForEach(Array(recent)) { g in NavigationLink(value: g) { GradeRow(grade: g) } }
                }
            }

            if let u = data.updated {
                Text("Frissítve: \(u.hu("MMMd HH:mm"))").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .overlay { if store.loading && data.updated == nil { ProgressView("Betöltés…") } }
    }
}

struct NowCard: View {
    let title: String
    let lesson: Ora
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(.tint)
            HStack(alignment: .firstTextBaseline) {
                Text(lesson.title).font(.title2.bold())
                Spacer()
                if let room = lesson.teremNeve { Text(room).font(.headline).foregroundStyle(.secondary) }
            }
            if let sub = lesson.helyettesTanarNeve?.renamedTeacher {
                Label("Helyettesít: \(sub)", systemImage: "person.2.fill").font(.subheadline).foregroundStyle(.orange)
            }
            if lesson.kezdetIdopont <= now {
                let total = lesson.vegIdopont.timeIntervalSince(lesson.kezdetIdopont)
                ProgressView(value: min(now.timeIntervalSince(lesson.kezdetIdopont), total), total: total)
                Text("Még \(Int(lesson.vegIdopont.timeIntervalSince(now) / 60) + 1) perc · vége \(lesson.vegIdopont.time)")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("\(lesson.kezdetIdopont.time) – \(lesson.vegIdopont.time) · \(lesson.kezdetIdopont, style: .relative) múlva")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Rows used on several screens

struct LessonRow: View {
    let lesson: Ora
    var active = false

    var body: some View {
        HStack(spacing: 12) {
            Text(lesson.oraszam.map(String.init) ?? "")
                .font(.headline.monospacedDigit())
                .frame(width: 28, height: 28)
                .background((active ? Color.accentColor : Color.secondary).opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(.body.weight(active ? .bold : .regular))
                    .strikethrough(lesson.isCancelled)
                    .foregroundStyle(lesson.isCancelled ? .red : lesson.helyettesTanarNeve != nil ? .orange : .primary)
                Text([(lesson.helyettesTanarNeve ?? lesson.tanarNeve)?.renamedTeacher, lesson.teremNeve].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if lesson.bejelentettSzamonkeresUid != nil { Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.red) }
            if lesson.haziFeladatUid != nil { Image(systemName: "house.fill").foregroundStyle(.blue) }
            VStack(alignment: .trailing) {
                Text(lesson.kezdetIdopont.time)
                Text(lesson.vegIdopont.time).foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit())
        }
    }
}

struct GradeRow: View {
    let grade: Ertekeles

    var body: some View {
        HStack(spacing: 12) {
            GradeBadge(text: grade.display, grade: grade.level)
            VStack(alignment: .leading, spacing: 2) {
                Text(grade.tantargy.name).font(.body)
                // text grades ("Nem írt" etc.) only have a short "-" badge, so spell them out here
                Text([grade.level == nil ? grade.szovegesErtek : nil, grade.tema ?? grade.mod?.leiras ?? grade.tipus.leiras]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(grade.keszitesDatuma.hu("MMMd"))
                if let w = grade.sulySzazalekErteke, w != 100 { Text("\(w)%") }
                if !grade.isMidYear { Text(grade.tipus.leiras ?? "") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct TestRow: View {
    let test: Szamonkeres

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(test.tantargy.name)
                Text([test.modja?.leiras, test.temaja].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(test.datum.hu("MMMd EEE")).font(.caption)
        }
    }
}

struct HomeworkRow: View {
    let hw: HaziFeladat

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(hw.tantargy.name)
                Text((hw.szoveg ?? "").strippingTags).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text("Határidő: \(hw.hataridoDatuma.hu("MMMd"))").font(.caption)
        }
    }
}

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
                if let s = lesson.helyettesTanarNeve { LabeledContent("Helyettes", value: s.renamedTeacher).foregroundStyle(.orange) }
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
            if let uid = lesson.bejelentettSzamonkeresUid, let test = store.data.tests.first(where: { $0.uid == uid }) {
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
