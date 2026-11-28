import SwiftUI

struct MoreView: View {
    enum Page: Hashable { case homework, tests, messages, settings, rename, hidden }
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading) {
                        Text(store.data.studentName).font(.headline)
                        if let s = store.data.schoolName { Text(s).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    NavigationLink(value: Page.homework) { Label("Házi feladatok", systemImage: "house") }
                    NavigationLink(value: Page.tests) { Label("Számonkérések", systemImage: "exclamationmark.bubble") }
                    NavigationLink(value: Page.messages) { Label("Üzenetek, feljegyzések", systemImage: "envelope") }
                }
                Section {
                    NavigationLink(value: Page.rename) { Label("Tantárgyak, tanárok átnevezése", systemImage: "pencil") }
                    NavigationLink(value: Page.hidden) { Label("Elrejtett órák", systemImage: "eye.slash") }
                    NavigationLink(value: Page.settings) { Label("Beállítások", systemImage: "gear") }
                }
            }
            .navigationTitle("Egyebek")
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .homework: HomeworkList()
                case .tests: TestsList()
                case .messages: MessagesList()
                case .settings: SettingsView()
                case .rename: RenameView()
                case .hidden: HiddenLessonsView()
                }
            }
            .navigationDestination(for: HaziFeladat.self) { HomeworkDetail(hw: $0) }
            .navigationDestination(for: Szamonkeres.self) { TestDetail(test: $0) }
            .navigationDestination(for: Message.self) { MessageDetail(message: $0) }
        }
    }
}

struct HomeworkList: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let today = Date().startOfDay
        let (upcoming, past) = HomeLogic.split(store.data.homework, today: today, date: \.hataridoDatuma)
        List {
            if !upcoming.isEmpty { Section("Közelgő") { ForEach(upcoming) { h in NavigationLink(value: h) { HomeworkRow(hw: h) } } } }
            if !past.isEmpty { Section("Korábbi") { ForEach(past) { h in NavigationLink(value: h) { HomeworkRow(hw: h) } } } }
        }
        .overlay { if store.data.homework.isEmpty { ContentUnavailableView("Nincs házi feladat", systemImage: "party.popper") } }
        .navigationTitle("Házi feladatok")
        .refreshable { await store.refresh() }
    }
}

struct TestsList: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let today = Date().startOfDay
        let (upcoming, past) = HomeLogic.split(store.data.tests, today: today, date: \.datum)
        List {
            if !upcoming.isEmpty { Section("Közelgő") { ForEach(upcoming) { t in NavigationLink(value: t) { TestRow(test: t) } } } }
            if !past.isEmpty { Section("Korábbi") { ForEach(past) { t in NavigationLink(value: t) { TestRow(test: t) } } } }
        }
        .overlay { if store.data.tests.isEmpty { ContentUnavailableView("Nincs bejelentett számonkérés", systemImage: "checkmark") } }
        .navigationTitle("Számonkérések")
        .refreshable { await store.refresh() }
    }
}
