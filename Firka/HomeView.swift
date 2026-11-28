import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                list(now: ctx.date)
                    .navigationTitle(HomeLogic.greeting(name: store.data.studentName, hour: Calendar.hu.component(.hour, from: ctx.date)))
            }
            .refreshable { await store.refresh() }
            .navigationDestination(for: Lesson.self) { LessonDetail(lesson: $0) }
            .navigationDestination(for: Grade.self) { GradeDetail(grade: $0) }
            .navigationDestination(for: Homework.self) { HomeworkDetail(hw: $0) }
            .navigationDestination(for: AnnouncedTest.self) { TestDetail(test: $0) }
        }
    }

    @ViewBuilder
    private func list(now: Date) -> some View {
        let data = store.data
        let (current, next, day, dayLessons) = HomeLogic.today(data.lessons, now: now, isHidden: HiddenLessons.shared.isHidden)
        let tests = HomeLogic.split(data.tests, today: now.startOfDay, date: \.date).upcoming
        let homework = HomeLogic.openHomework(data.homework, today: now.startOfDay)
        let recent = store.visibleGrades.sorted { $0.date > $1.date }.prefix(5)

        List {
            if let err = store.error {
                Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(Color.pending).font(.footnote)
            }

            NewGradesSection()

            Section {
                if let current {
                    NowCard(title: "Most", lesson: current, now: now)
                } else if let next {
                    NowCard(title: next.start.startOfDay == now.startOfDay ? "Következő óra" : "Következő óra – \(next.start.hu("EEEE"))",
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
    let lesson: Lesson
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(.tint)
            HStack(alignment: .firstTextBaseline) {
                Text(lesson.title).font(.title2.bold())
                Spacer()
                if let room = lesson.room { Text(room).font(.headline).foregroundStyle(.secondary) }
            }
            if let sub = lesson.substitute?.renamedTeacher {
                Label("Helyettesít: \(sub)", systemImage: "person.2.fill").font(.subheadline).foregroundStyle(Color.substituted)
            }
            if lesson.start <= now {
                let total = lesson.end.timeIntervalSince(lesson.start)
                ProgressView(value: min(now.timeIntervalSince(lesson.start), total), total: total)
                Text("Még \(HomeLogic.minutesLeft(until: lesson.end, now: now)) perc · vége \(lesson.end.time)")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("\(lesson.start.time) – \(lesson.end.time) · \(lesson.start, style: .relative) múlva")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
