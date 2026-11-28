import SwiftUI

// MARK: - Rows used on several screens

struct LessonRow: View {
    let lesson: Lesson
    var active = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                // a university class has no lesson number: an icon instead of an empty circle
                if let n = lesson.number { Text("\(n)") } else { Image(systemName: "book.closed").font(.caption) }
            }
                .font(.headline.monospacedDigit())
                .frame(width: 28, height: 28)
                .background((active ? Color.accentColor : Color.secondary).opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(.body.weight(active ? .bold : .regular))
                    .strikethrough(lesson.cancelled)
                    .foregroundStyle(lesson.cancelled ? Color.cancelled : lesson.substitute != nil ? Color.substituted : .primary)
                Text([(lesson.substitute ?? lesson.teacher)?.renamedTeacher, lesson.room].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if lesson.testID != nil { Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.red) }
            if lesson.homeworkID != nil { Image(systemName: "house.fill").foregroundStyle(.blue) }
            VStack(alignment: .trailing) {
                Text(lesson.start.time)
                Text(lesson.end.time).foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit())
        }
    }
}

struct GradeRow: View {
    let grade: Grade

    var body: some View {
        HStack(spacing: 12) {
            GradeBadge(text: grade.display, grade: grade.level)
            VStack(alignment: .leading, spacing: 2) {
                Text(grade.subject.name).font(.body)
                // text grades ("Nem írt" etc.) only have a short "-" badge, so spell them out here
                Text([grade.level == nil ? grade.text : nil, grade.topic ?? grade.mode ?? grade.kindText]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(grade.date.hu("MMMd"))
                if let w = grade.weight, w != 100 { Text("\(w)%") }
                if !grade.isMidYear { Text(grade.kindText ?? "") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct TestRow: View {
    let test: AnnouncedTest

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(test.subject.name)
                Text([test.mode, test.topic].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(test.date.hu("MMMd EEE")).font(.caption)
        }
    }
}

struct HomeworkRow: View {
    let hw: Homework

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(hw.subject.name)
                Text((hw.html ?? "").strippingTags).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if hw.done == true {
                Label("Megoldva", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Határidő: \(hw.due.hu("MMMd"))").font(.caption)
            }
        }
    }
}
