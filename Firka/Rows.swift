import SwiftUI

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
                    .foregroundStyle(lesson.isCancelled ? Color.cancelled : lesson.helyettesTanarNeve != nil ? Color.substituted : .primary)
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
            if hw.isMegoldva == true {
                Label("Megoldva", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Határidő: \(hw.hataridoDatuma.hu("MMMd"))").font(.caption)
            }
        }
    }
}
