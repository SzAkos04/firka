import SwiftUI
import Charts

struct GradesView: View {
    @Environment(AppStore.self) private var store
    @State private var mode = 0

    private var classOverall: Double? { GradesLogic.classOverall(store.visibleGrades, averages: store.data.classAverages) }

    var body: some View {
        let grades = store.visibleGrades
        let subjects = GradesLogic.subjects(grades)

        NavigationStack {
            List {
                NewGradesSection()

                Section {
                    HStack(spacing: 12) {
                        AverageBadge(value: grades.overallAverage, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Összesített átlag").font(.headline)
                            Text("\(grades.countedInAverage) jegy alapján").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let r = grades.reportCardAverage(store.rounding) {
                        LabeledContent("Várható bizonyítvány", value: r.hu2)
                    }
                    if let c = classOverall {
                        LabeledContent("Osztályátlag", value: c.hu2)
                    }
                    Distribution(grades: grades)
                    AverageChart(grades: grades, classAverage: classOverall).frame(height: 150)
                }

                // the report card only once a half-year or year-end grade exists
                let hasTermGrades = grades.contains { $0.term != nil }
                Picker("Nézet", selection: $mode) {
                    Text("Tantárgyak").tag(0)
                    Text("Legutóbbiak").tag(1)
                    if hasTermGrades { Text("Bizonyítvány").tag(2) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if mode == 0 {
                    ForEach(subjects) { s in
                        NavigationLink(value: s.subject) {
                            HStack(spacing: 12) {
                                AverageBadge(value: s.grades.average, size: 42)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(s.subject.name).lineLimit(1)
                                    GradeStrip(grades: s.grades)
                                }
                                Spacer(minLength: 0)
                                if let c = store.data.classAverages?[s.subject.id] {
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("osztály")
                                        Text(c.hu2).monospacedDigit()
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                                }
                            }
                        }
                    }
                } else if mode == 1 {
                    ForEach(grades.sorted { $0.date > $1.date }) { g in
                        NavigationLink(value: g) { GradeRow(grade: g) }
                    }
                } else if hasTermGrades {
                    ReportCardSection(grades: grades)
                }
            }
            .overlay { if grades.isEmpty { ContentUnavailableView("Még nincs jegyed", systemImage: "star") } }
            .navigationTitle("Jegyek")
            .onChange(of: grades.contains { $0.term != nil }, initial: true) { _, has in if !has && mode == 2 { mode = 0 } }
            .refreshable { await store.refresh() }
            .navigationDestination(for: Grade.self) { GradeDetail(grade: $0) }
            .navigationDestination(for: Subject.self) { SubjectView(subject: $0) }
        }
    }
}

struct SubjectView: View {
    let subject: Subject
    @Environment(AppStore.self) private var store
    @State private var whatIf: [WhatIf] = []  // "mi lenne ha" grades
    @State private var weight = 100  // the weight the next one gets

    var body: some View {
        // from the store, so a refresh while the page is open shows up here too
        let grades = store.visibleGrades.filter { $0.subject.id == subject.id }
        let classAverage = store.data.classAverages?[subject.id]
        let sorted = grades.sorted { $0.date > $1.date }
        List {
            Section {
                HStack(spacing: 16) {
                    AverageBadge(value: grades.average, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Átlag").font(.headline)
                        if let t = grades.teacher { Text(t.renamedTeacher).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                if let a = grades.average {
                    LabeledContent("Várható jegy", value: "\(store.rounding.grade(a))")
                }
                LabeledContent("Jegyek száma", value: "\(grades.countedInAverage)")
                if let c = classAverage {
                    LabeledContent("Osztályátlag", value: c.hu2).accessibilityIdentifier("subjectClassAverage")
                }
                AverageChart(grades: grades, classAverage: classAverage).frame(height: 160)
            }

            Section {
                Picker("Súly", selection: $weight) {
                    ForEach([50, 100, 200, 300], id: \.self) { Text("\($0)%") }
                }
                .pickerStyle(.segmented)
                HStack {
                    ForEach(1...5, id: \.self) { n in
                        Button { whatIf.append(WhatIf(n, weight: weight)) } label: { GradeBadge(text: "\(n)", grade: n) }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("whatIf\(n)")
                    }
                }
                if !whatIf.isEmpty {
                    HStack {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(whatIf.enumerated()), id: \.offset) { i, w in
                                    // tap one to take it back
                                    Button { whatIf.remove(at: i) } label: {
                                        Text(w.weight == 100 ? "\(w.grade)" : "\(w.grade) · \(w.weight)%")
                                            .font(.subheadline.weight(.semibold))
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(Color.grade(w.grade).opacity(0.2), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(w.grade), \(w.weight)%, törlés")
                                    .accessibilityIdentifier("whatIfChip")
                                }
                            }
                        }
                        AverageBadge(value: grades.average(adding: whatIf))
                    }
                    Button("Mind törlése", role: .destructive) { whatIf = [] }
                }
            } header: { Text("Mi lenne, ha…") } footer: { Text("Érints meg egy jegyet a sorban, hogy kivedd.") }

            Section("Jegyek") {
                ForEach(sorted) { g in NavigationLink(value: g) { GradeRow(grade: g) } }
            }
        }
        .navigationTitle(subject.name)
    }
}

struct AverageChart: View {
    let grades: [Grade]
    var classAverage: Double?
    @State private var selected: Date?

    var body: some View {
        let points = grades.runningAverage
        // dragging along the chart: the point nearest the finger
        let picked = selected.flatMap { s in points.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) } }
        if points.count < 2 {
            Text("A grafikonhoz legalább két különböző napon kapott jegy kell.").font(.caption).foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Dátum", p.date), y: .value("Átlag", p.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.onGrade(5))
                    AreaMark(x: .value("Dátum", p.date), yStart: .value("", 1), yEnd: .value("Átlag", p.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Color.grade(5), Color.grade(5).opacity(0)], startPoint: .top, endPoint: .bottom))
                }
                if let picked {
                    RuleMark(x: .value("Dátum", picked.date))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text("\(picked.date.hu("MMMd")): \(picked.value.hu2)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.regularMaterial, in: Capsule())
                        }
                }
                if let classAverage {
                    RuleMark(y: .value("Osztályátlag", classAverage))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .bottom, alignment: .leading) {
                            Text("osztály").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartYScale(domain: 1...5)
            .chartYAxis { AxisMarks(values: [1, 2, 3, 4, 5]) }
            .chartXAxis {
                // dates only; with grades a few days apart Charts would otherwise label hours
                let span = points.last!.date.timeIntervalSince(points.first!.date)
                AxisMarks(values: span < 5 * 86400 ? .stride(by: .day) : .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
        }
    }
}

struct Distribution: View {
    let grades: [Grade]

    var body: some View {
        let counted = grades.filter(\.countsInAverage)
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { n in
                let count = counted.filter { $0.number == n }.count
                VStack(spacing: 1) {
                    Text("\(count)").font(.system(.headline, design: .rounded).monospacedDigit())
                    Text(["1-es", "2-es", "3-as", "4-es", "5-ös"][n - 1]).font(.caption2)
                }
                .foregroundStyle(Color.onGrade(n))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.grade(n), in: RoundedRectangle(cornerRadius: 9))
                .opacity(count == 0 ? 0.45 : 1)
            }
        }
    }
}

/// A subject's last 8 grades as small chips, oldest to newest; width shows weight (200% wide, 50% narrow).
struct GradeStrip: View {
    let grades: [Grade]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(grades.filter { $0.level != nil }.sorted { $0.date < $1.date }.suffix(8)) { g in
                let w = g.weight ?? 100
                Text(g.display)
                    .font(.system(size: w < 100 ? 10 : 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.onGrade(g.level!))
                    .frame(width: w > 100 ? 24 : w < 100 ? 12 : 17, height: 17)
                    .background(Color.grade(g.level!), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

/// Half-year and year-end grades per subject; the next term without grades shows the expected grade.
struct ReportCardSection: View {
    let grades: [Grade]
    @Environment(AppStore.self) private var store
    @ScaledMetric private var column = 56.0

    var body: some View {
        let card = grades.reportCard(store.rounding)
        Section {
            HStack {
                Text("Tantárgy")
                Spacer()
                Text("Félév").frame(width: column)
                Text("Év vége").frame(width: column)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(card.rows) { row in
                HStack {
                    Text(row.subject.name).lineLimit(2)
                    Spacer()
                    cell(row.half, expected: card.upcoming == .half ? row.expected : nil).frame(width: column)
                    cell(row.end, expected: card.upcoming == .end ? row.expected : nil).frame(width: column)
                }
            }

            HStack {
                Text("Átlag").font(.headline)
                Spacer()
                Text(columnAverage(card.rows.map { $0.half?.level ?? (card.upcoming == .half ? $0.expected : nil) }))
                    .frame(width: column)
                Text(columnAverage(card.rows.map { $0.end?.level ?? (card.upcoming == .end ? $0.expected : nil) }))
                    .frame(width: column)
            }
            .font(.headline.monospacedDigit())
        } footer: {
            if card.upcoming != nil {
                Text("A halvány, szaggatott keretes jegy a várható jegy: a mostani évközi átlagod, a beállított kerekítéssel. A valódi jegy akkor jelenik meg, amikor a tanár beírja a KRÉTA-ba.")
            }
        }
    }

    @ViewBuilder
    private func cell(_ g: Grade?, expected: Int?) -> some View {
        if let g {
            GradeBadge(text: g.display, grade: g.level, size: 34)
        } else if let e = expected {
            Text("\(e)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.onGrade(e).opacity(0.8))
                .frame(width: 34, height: 34)
                .background(Color.grade(e).opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.onGrade(e).opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .accessibilityLabel("várható \(e)")
        } else {
            Text("–").foregroundStyle(.tertiary)
        }
    }

    private func columnAverage(_ values: [Int?]) -> String { GradesLogic.columnAverage(values) }
}
