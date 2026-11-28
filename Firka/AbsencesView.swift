import SwiftUI

struct AbsencesView: View {
    @Environment(AppStore.self) private var store
    @State private var filter = AbsenceFilter.all

    var body: some View {
        let all = store.data.absences.sorted { $0.date > $1.date }
        let stats = AbsenceStats(all)
        let byDay = Dictionary(grouping: filter.apply(all)) { $0.date.startOfDay }.sorted { $0.key > $1.key }

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Stat(value: stats.justified, label: "Igazolt", color: .justified)
                        Stat(value: stats.unjustified, label: "Igazolatlan", color: .unjustified)
                        Stat(value: stats.pending, label: "Igazolandó", color: .pending)
                        Stat(value: stats.lateMinutes, label: "Késés, perc", color: nil)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if !all.isEmpty {
                    Picker("Szűrő", selection: $filter) {
                        ForEach(AbsenceFilter.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if filter == .subjects {
                    Section {
                        ForEach(AbsenceFilter.bySubject(all), id: \.subject.id) { s in
                            LabeledContent(s.subject.name, value: s.lateMinutes > 0 ? "\(s.absences) óra · \(s.lateMinutes) perc késés" : "\(s.absences) óra")
                                .accessibilityIdentifier("absenceSubject")
                        }
                    } footer: { Text("Hiányzott órák tantárgyanként; a késések percben, külön.") }
                } else {
                    ForEach(byDay, id: \.key) { day, items in
                        Section(day.hu("yMMMMd EEEE")) {
                            ForEach(items.sorted { ($0.lessonNumber ?? 0) < ($1.lessonNumber ?? 0) }) { a in
                                NavigationLink(value: a) {
                                    HStack(spacing: 12) {
                                        Text(a.lessonNumber.map { "\($0)." } ?? "")
                                            .font(.headline.monospacedDigit()).frame(width: 30)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(a.subject.name)
                                            Text([a.late ? "Késés, \(a.lateMinutes ?? 0) perc" : "Hiányzás",
                                                  a.state == .excused ? a.excuse : nil]
                                                .compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(a.stateShort)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(a.stateColor)
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(a.stateColor.opacity(0.15), in: Capsule())
                                    }
                                }
                                .accessibilityIdentifier("absenceRow")
                            }
                        }
                    }
                }
            }
            .overlay { if all.isEmpty { ContentUnavailableView("Nincs hiányzásod", systemImage: "checkmark.seal") } }
            .navigationTitle("Hiányzások")
            .navigationDestination(for: Absence.self) { AbsenceDetail(absence: $0) }
            .refreshable { await store.refresh() }
        }
    }
}

struct AbsenceDetail: View {
    let absence: Absence

    var body: some View {
        let a = absence
        List {
            LabeledContent("Dátum", value: a.date.hu("yMMMMd EEEE"))
            if let start = a.lessonStart, let end = a.lessonEnd {
                LabeledContent("Óra", value: [a.lessonNumber.map { "\($0)." }, "\(start.time)–\(end.time)"].compactMap { $0 }.joined(separator: " "))
            }
            LabeledContent("Típus", value: a.late ? "Késés, \(a.lateMinutes ?? 0) perc" : "Hiányzás")
            LabeledContent("Állapot", value: a.stateShort).foregroundStyle(a.stateColor)
            if a.state == .excused, let t = a.excuse { LabeledContent("Igazolás", value: t) }
            if let t = a.recordedBy { LabeledContent("Rögzítette", value: t.renamedTeacher) }
        }
        .navigationTitle(a.subject.name)
    }
}

private struct Stat: View {
    let value: Int
    let label: String
    let color: Color?  // only non-zero counts get their color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.bold().monospacedDigit())
                .foregroundStyle(value > 0 ? color ?? .primary : .secondary)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
