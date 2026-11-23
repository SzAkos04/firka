import SwiftUI

struct TimetableView: View {
    @Environment(AppStore.self) private var store
    @State private var week = TimetableNav.openingDay(today: Date().startOfDay, lessonDays: []).startOfWeek
    @State private var day = TimetableNav.openingDay(today: Date().startOfDay, lessonDays: [])
    @State private var lessons: [Ora] = []
    @State private var loading = false
    @AppStorage(Pref.timetableMonth) private var monthMode = false
    @State private var showHidden = false

    /// Days with real lessons: the cached this/next week plus the loaded one.
    private var lessonDays: Set<Date> { TimetableNav.lessonDays(store.data.lessons + lessons) }
    private var days: [Date] { TimetableNav.days(week: week, lessonDays: lessonDays) }

    private func show(_ d: Date) {
        week = TimetableNav.week(showing: d, lessonDays: lessonDays)
        day = d
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
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Előző hét").accessibilityIdentifier("previousWeek")
                    Spacer()
                    Text("\(week.hu("MMMd")) – \(week.adding(days: 6).hu("MMMd"))").font(.headline)
                        .accessibilityIdentifier("weekTitle")
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Következő hét").accessibilityIdentifier("nextWeek")
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                let testDays = Set(store.data.tests.map { $0.datum.startOfDay })
                let today = Date().startOfDay
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { d in
                        DayButton(date: d, selected: d == day, today: d == today, hasTest: testDays.contains(d)) { day = d }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)  // room under the test dots before the strip's edge
                // swiping here changes the day; on the lesson rows it's the hide action
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    step(v.translation.width < 0 ? 1 : -1)
                })

                dayList
                    .contentMargins(.top, 8, for: .scrollContent)  // the strip is the header: no empty band under it
            }
            .background(Color(.systemGroupedBackground))  // one surface with the list, like the month view
            .toolbar {
                Button("Ma") { show(TimetableNav.openingDay(today: Date().startOfDay, lessonDays: lessonDays)) }
                    .disabled(TimetableNav.isAtToday(day: day, today: Date().startOfDay, lessonDays: lessonDays))
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
                    .accessibilityIdentifier("lessonRow")
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

    private func move(_ weeks: Int) {
        (week, day) = TimetableNav.move(week: week, by: weeks, today: Date().startOfDay, lessonDays: lessonDays)
    }

    /// Swipe to the next/previous school day, crossing weeks.
    private func step(_ dir: Int) {
        (week, day) = TimetableNav.step(day: day, days: days, week: week, by: dir)
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

    private var days: [Date] { TimetableNav.monthDays(month) }
    private var leadingBlanks: Int { TimetableNav.leadingBlanks(month: month) }

    var body: some View {
        let byDay = Dictionary(grouping: lessons) { $0.kezdetIdopont.startOfDay }
        let tests = Dictionary(grouping: store.data.tests) { $0.datum.startOfDay }
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        List {
            Section {
                HStack {
                    Button { change(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Előző hónap")
                    Spacer()
                    Text(month.hu("yMMMM").capitalizedFirst).font(.headline)
                    Spacer()
                    Button { change(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Következő hónap")
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
        .toolbar {
            Button("Ma") { month = Date().startOfMonth; selected = Date().startOfDay }
                .disabled(month == Date().startOfMonth && selected == Date().startOfDay)
        }
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

/// One day in the week strip, like the iOS Calendar: a filled circle for the chosen day (green if it's today),
/// a light green circle for today, a red dot under days with an announced test.
private struct DayButton: View {
    let date: Date
    let selected: Bool
    let today: Bool
    let hasTest: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(date.hu("EEEEE"))  // H, K, Sz…
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(date.hu("d"))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(selected ? (today ? .white : Color(.systemBackground)) : today ? Color.accentColor : .primary)
                    .frame(width: 36, height: 36)
                    // chosen: solid (green if today); today otherwise: a light green circle, so it never looks like the others
                    .background {
                        if selected { Circle().fill(today ? Color.accentColor : .primary) }
                        else if today { Circle().fill(Color.accentColor.opacity(0.18)) }
                    }
                Circle()
                    .fill(hasTest ? Color.red : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.hu("MMMMd EEEE"))\(today ? ", ma" : "")\(hasTest ? ", dolgozat" : "")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("day")
    }
}
