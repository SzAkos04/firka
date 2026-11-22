import SwiftUI

struct TimetableView: View {
    @Environment(AppStore.self) private var store
    @State private var week = TimetableView.initialDay().startOfWeek
    @State private var day = TimetableView.initialDay()
    @State private var lessons: [Ora] = []
    @State private var loading = false
    @AppStorage(Pref.timetableMonth) private var monthMode = false
    @State private var showHidden = false

    /// Today, or next Monday on weekends.
    static func initialDay() -> Date {
        let today = Date().startOfDay
        let wd = Calendar.hu.component(.weekday, from: today)  // 1 = Sunday, 7 = Saturday
        return wd == 7 ? today.adding(days: 2) : wd == 1 ? today.adding(days: 1) : today
    }

    private var days: [Date] {
        let weekend = lessons.contains { Calendar.hu.isDateInWeekend($0.kezdetIdopont) }
        return (0..<(weekend ? 7 : 5)).map { week.adding(days: $0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if monthMode { MonthTimetable() } else { weekView }
            }
            .navigationTitle("Órarend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Nézet", selection: $monthMode) {
                        Text("Hét").tag(false)
                        Text("Hónap").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
            }
            .navigationDestination(for: Ora.self) { LessonDetail(lesson: $0) }
            .navigationDestination(for: Szamonkeres.self) { TestDetail(test: $0) }
        }
    }

    private var weekView: some View {
            VStack(spacing: 0) {
                HStack {
                    Button { move(-7) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text("\(week.hu("MMMd")) – \(week.adding(days: 6).hu("MMMd"))").font(.headline)
                    Spacer()
                    Button { move(7) } label: { Image(systemName: "chevron.right") }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                HStack(spacing: 6) {
                    ForEach(days, id: \.self) { d in
                        let selected = d == day
                        Button { day = d } label: {
                            VStack(spacing: 2) {
                                Text(d.hu("EEEEE")).font(.caption)  // H, K, Sz…
                                Text(d.hu("d")).font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(selected ? Color(.systemBackground) : d == Date().startOfDay ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                // swiping here changes the day; on the lesson rows it's the hide action
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    step(v.translation.width < 0 ? 1 : -1)
                })

                dayList
            }
            .toolbar {
                Button("Ma") { week = Self.initialDay().startOfWeek; day = Self.initialDay() }
            }
            .task(id: week) { await load() }
            .onChange(of: store.data.updated) { Task { await load() } }
    }

    private var dayList: some View {
        let items = lessons.filter { $0.kezdetIdopont.startOfDay == day }.sorted { $0.kezdetIdopont < $1.kezdetIdopont }
        let events = items.filter(\.isEvent)
        let real = items.filter { !$0.isEvent }
        let hidden = real.filter(HiddenLessons.shared.isHidden)
        return List {
            ForEach(events) { e in
                Label(e.nev ?? e.tipus.leiras ?? "Esemény", systemImage: "flag.fill").foregroundStyle(.purple)
            }
            ForEach(showHidden ? real : real.filter { !hidden.contains($0) }) { l in
                NavigationLink(value: l) { LessonRow(lesson: l, active: l.kezdetIdopont <= Date() && l.vegIdopont > Date()) }
                    .opacity(hidden.contains(l) ? 0.45 : 1)
                    .hideLessonActions(l)
            }
            HiddenFooter(count: hidden.count, showing: $showHidden)
        }
        .overlay {
            if loading && items.isEmpty { ProgressView() }
            else if real.isEmpty && events.isEmpty { ContentUnavailableView("Nincs óra", systemImage: "sun.max") }
        }
        .onChange(of: day) { showHidden = false }
        .refreshable { await store.refresh(); await load() }
    }

    private func move(_ days: Int) {
        week = week.adding(days: days)
        day = day.adding(days: days)
    }

    /// Swipe to the next/previous school day, crossing weeks.
    private func step(_ dir: Int) {
        guard let i = days.firstIndex(of: day) else { return }
        let j = i + dir
        if j >= 0 && j < days.count { day = days[j]; return }
        let w = week.adding(days: 7 * dir)
        week = w
        day = dir > 0 ? w : w.adding(days: 4)
    }

    private func load() async {
        loading = true
        lessons = await store.lessons(week: week)
        loading = false
    }
}

/// Calendar month: dots for lessons, tests, changes and school-calendar events; the chosen day's lessons below.
struct MonthTimetable: View {
    @Environment(AppStore.self) private var store
    @State private var month = Date().startOfMonth
    @State private var selected = Date().startOfDay
    @State private var lessons: [Ora] = []
    @State private var loading = false
    @State private var showHidden = false

    private var days: [Date] {
        let n = Calendar.hu.range(of: .day, in: .month, for: month)!.count
        return (0..<n).map { month.adding(days: $0) }
    }

    /// Empty cells before the 1st, Monday first.
    private var leadingBlanks: Int { (Calendar.hu.component(.weekday, from: month) + 5) % 7 }

    var body: some View {
        let byDay = Dictionary(grouping: lessons) { $0.kezdetIdopont.startOfDay }
        let tests = Dictionary(grouping: store.data.tests) { $0.datum.startOfDay }
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        List {
            Section {
                HStack {
                    Button { change(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(month.hu("yMMMM").capitalizedFirst).font(.headline)
                    Spacer()
                    Button { change(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless)

                HStack(spacing: 0) {
                    ForEach(Array(["H", "K", "Sz", "Cs", "P", "Sz", "V"].enumerated()), id: \.offset) { _, d in
                        Text(d).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: cols, spacing: 6) {
                    // ids must not clash with the day cells' ids (dates), so blanks get negative numbers
                    ForEach(0..<leadingBlanks, id: \.self) { i in Color.clear.frame(height: 44).id(-1 - i) }
                    ForEach(days, id: \.self) { d in
                        DayCell(date: d, lessons: byDay[d] ?? [], hasTest: tests[d] != nil,
                                selected: d == selected, today: d == Date().startOfDay)
                            .onTapGesture { selected = d }
                    }
                }
                .overlay(alignment: .topTrailing) { if loading { ProgressView().controlSize(.small) } }
                .gesture(DragGesture(minimumDistance: 40).onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                    change(v.translation.width < 0 ? 1 : -1)
                })
            }

            Section(selected.hu("MMMMd EEEE").capitalizedFirst) {
                let items = (byDay[selected] ?? []).sorted { $0.kezdetIdopont < $1.kezdetIdopont }
                ForEach(items.filter(\.isEvent)) { e in
                    Label(e.nev ?? e.tipus.leiras ?? "Esemény", systemImage: "flag.fill").foregroundStyle(.purple)
                }
                ForEach(tests[selected] ?? []) { t in NavigationLink(value: t) { TestRow(test: t) } }
                let real = items.filter { !$0.isEvent }
                let hidden = real.filter(HiddenLessons.shared.isHidden)
                ForEach(showHidden ? real : real.filter { !hidden.contains($0) }) { l in
                    NavigationLink(value: l) { LessonRow(lesson: l) }
                        .opacity(hidden.contains(l) ? 0.45 : 1)
                        .hideLessonActions(l)
                }
                HiddenFooter(count: hidden.count, showing: $showHidden)
                if items.isEmpty && tests[selected] == nil {
                    Text(loading ? "Betöltés…" : "Nincs óra").foregroundStyle(.secondary)
                }
            }

            Section {
                HStack(spacing: 14) {
                    Legend(color: .accentColor, text: "óra")
                    Legend(color: .red, text: "dolgozat")
                    Legend(color: .orange, text: "változás")
                    Legend(color: .purple, text: "esemény")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }
        }
        .toolbar { Button("Ma") { month = Date().startOfMonth; selected = Date().startOfDay } }
        .refreshable { await store.refresh(); await load() }
        .task(id: month) { await load() }
        .onChange(of: selected) { showHidden = false }
    }

    private func change(_ dir: Int) {
        month = Calendar.hu.date(byAdding: .month, value: dir, to: month)!
        selected = month == Date().startOfMonth ? Date().startOfDay : month
    }

    /// The month's weeks, through the same per-week cache the week view uses.
    private func load() async {
        loading = true
        defer { loading = false }
        let end = Calendar.hu.date(byAdding: .month, value: 1, to: month)!
        var all: [Ora] = []
        var week = month.startOfWeek
        while week < end {
            if Task.isCancelled { return }  // paged on to another month
            all += await store.lessons(week: week)
            week = week.adding(days: 7)
        }
        lessons = all.filter { $0.kezdetIdopont >= month && $0.kezdetIdopont < end }
    }
}

private struct DayCell: View {
    let date: Date
    let lessons: [Ora]
    let hasTest: Bool
    let selected: Bool
    let today: Bool

    var body: some View {
        let real = lessons.filter { !$0.isEvent && !HiddenLessons.shared.isHidden($0) }
        let changed = real.contains { $0.isCancelled || $0.helyettesTanarNeve != nil }
        let event = lessons.contains { $0.isEvent }
        VStack(spacing: 3) {
            Text(date.hu("d"))
                .font(.callout.monospacedDigit().weight(today ? .bold : .regular))
                .frame(width: 32, height: 32)
                .background(selected ? Color.accentColor : today ? Color.accentColor.opacity(0.15) : .clear, in: Circle())
                .foregroundStyle(selected ? Color(.systemBackground) : real.isEmpty ? .secondary : .primary)
            HStack(spacing: 3) {
                if !real.isEmpty { Dot(color: .accentColor) }
                if hasTest { Dot(color: .red) }
                if changed { Dot(color: .orange) }
                if event { Dot(color: .purple) }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.hu("MMMMd")), \(real.count) óra\(hasTest ? ", dolgozat" : "")\(changed ? ", változás" : "")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct Dot: View {
    let color: Color
    var body: some View { Circle().fill(color).frame(width: 5, height: 5) }
}

private struct Legend: View {
    let color: Color
    let text: String
    var body: some View { HStack(spacing: 4) { Dot(color: color); Text(text) } }
}
