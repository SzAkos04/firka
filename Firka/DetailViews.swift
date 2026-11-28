import SwiftUI

// MARK: - Detail screens

struct LessonDetail: View {
    let lesson: Lesson
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section {
                LabeledContent("Időpont", value: "\(lesson.start.hu("MMMMd EEEE")) \(lesson.start.time)–\(lesson.end.time)")
                if let n = lesson.number { LabeledContent("Óraszám", value: "\(n).") }
                if let r = lesson.room { LabeledContent("Terem", value: r) }
                if let t = lesson.teacher { LabeledContent("Tanár", value: t.renamedTeacher) }
                if let s = lesson.substitute { LabeledContent("Helyettes", value: s.renamedTeacher).foregroundStyle(Color.substituted) }
                if let a = lesson.stateText { LabeledContent("Állapot", value: a) }
                if let p = lesson.attendance { LabeledContent("Jelenlét", value: p) }
            }
            if let t = lesson.topic, !t.isEmpty { Section("Téma") { Text(t) } }
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
            if let uid = lesson.homeworkID, let hw = store.data.homework.first(where: { $0.id == uid }) {
                Section("Házi feladat") { HTMLText(html: hw.html ?? "") }
            }
        }
        .navigationTitle(lesson.title)
    }
}

struct GradeDetail: View {
    let grade: Grade

    var body: some View {
        List {
            HStack {
                Spacer()
                GradeBadge(text: grade.display, grade: grade.level, size: 90)
                Spacer()
            }
            .listRowBackground(Color.clear)
            Section {
                if let t = grade.topic { LabeledContent("Téma", value: t) }
                LabeledContent("Típus", value: grade.kindText ?? "")
                if let m = grade.mode { LabeledContent("Mód", value: m) }
                if let w = grade.weight { LabeledContent("Súly", value: "\(w)%") }
                if let s = grade.text { LabeledContent("Érték", value: s) }
                if let t = grade.teacher { LabeledContent("Tanár", value: t.renamedTeacher) }
                LabeledContent("Dátum", value: grade.date.hu("yMMMMd"))
                LabeledContent("Rögzítve", value: grade.recorded.hu("yMMMMd"))
            }
        }
        .navigationTitle(grade.subject.name)
    }
}

struct HomeworkDetail: View {
    let hw: Homework

    var body: some View {
        List {
            Section {
                LabeledContent("Feladva", value: hw.given.hu("MMMMd EEEE"))
                LabeledContent("Határidő", value: hw.due.hu("MMMMd EEEE"))
                if hw.done == true { LabeledContent("Állapot", value: "Megoldva") }
                if let t = hw.teacher { LabeledContent("Tanár", value: t.renamedTeacher) }
            }
            Section("Feladat") { HTMLText(html: hw.html ?? "") }
        }
        .navigationTitle(hw.subject.name)
    }
}

struct TestDetail: View {
    let test: AnnouncedTest

    var body: some View {
        List {
            LabeledContent("Dátum", value: test.date.hu("MMMMd EEEE"))
            if let n = test.lessonNumber { LabeledContent("Óra", value: "\(n).") }
            if let m = test.mode { LabeledContent("Mód", value: m) }
            if let t = test.topic { LabeledContent("Téma", value: t) }
            if let t = test.teacher { LabeledContent("Tanár", value: t.renamedTeacher) }
            LabeledContent("Bejelentve", value: test.announced.hu("MMMMd"))
        }
        .navigationTitle(test.subject.name)
    }
}
