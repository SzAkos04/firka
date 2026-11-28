import SwiftUI

// The screens that differ for a university (Neptun): grades by credits and terms, exams instead of absences.

struct UniversityGradesView: View {
    @Environment(AppStore.self) private var store
    @State private var semester: String?
    @State private var other: [Grade]?  // courses of a term that isn't the current one

    var body: some View {
        let data = store.data
        let current = data.semesters.first { $0.current } ?? data.semesters.first
        let picked = semester.flatMap { id in data.semesters.first { $0.id == id } } ?? current
        let courses = picked == current ? data.courses : (other ?? [])
        let avg = CreditAverages(courses)

        NavigationStack {
            List {
                NewGradesSection()
                Section {
                    // like the KRÉTA grades screen: the average as a badge, the rest as rows
                    HStack(spacing: 12) {
                        AverageBadge(value: avg.average, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Súlyozott átlag").font(.headline)
                            Text("\(avg.completed) kredit alapján").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Kreditindex", value: avg.creditIndex.hu2)
                    LabeledContent("Korrigált kreditindex", value: avg.correctedCreditIndex.hu2)
                    LabeledContent("Teljesített kredit", value: "\(avg.completed) / \(avg.taken)")
                } header: {
                    if data.semesters.count > 1, let picked {
                        Picker("Félév", selection: Binding(get: { picked.id }, set: { semester = $0 })) {
                            ForEach(data.semesters) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                        .textCase(nil)
                        .accessibilityIdentifier("semesterPicker")
                    } else if let picked {
                        Text(picked.name)
                    }
                }
                Section("Tárgyak") {
                    ForEach(courses) { c in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.subject.name)
                                Text([c.credit.map { "\($0) kredit" }, c.mode].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if c.number != nil, store.isHidden(c) {  // no result yet is no surprise: "–"
                                GradeBadge(text: "?", grade: nil)
                            } else {
                                GradeBadge(text: c.number.map(String.init) ?? "–", grade: c.number)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .overlay { if courses.isEmpty { ContentUnavailableView("Nincs adat ebből a félévből", systemImage: "graduationcap") } }
            .navigationTitle("Jegyek")
            .refreshable { await store.refresh() }
            .task(id: picked?.id) {
                guard let picked, picked != current else { other = nil; return }
                other = await store.courses(semester: picked)
            }
        }
    }
}

struct ExamsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let (upcoming, past) = HomeLogic.split(store.data.exams, today: Date().startOfDay, date: \.start)
        NavigationStack {
            List {
                if !upcoming.isEmpty { Section("Közelgő") { ForEach(upcoming) { ExamRow(exam: $0) } } }
                if !past.isEmpty { Section("Korábbi") { ForEach(past) { ExamRow(exam: $0) } } }
            }
            .overlay { if store.data.exams.isEmpty { ContentUnavailableView("Nincs vizsgád", systemImage: "checkmark.seal") } }
            .navigationTitle("Vizsgák")
            .refreshable { await store.refresh() }
        }
    }
}

private struct ExamRow: View {
    let exam: Exam

    var body: some View {
        Button {} label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exam.subject.name)
                    Text([exam.start.hu("MMMMd EEEE HH:mm"), exam.room, exam.kind].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let r = exam.result { GradeBadge(text: "\(r)", grade: r) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("examRow")
    }
}
