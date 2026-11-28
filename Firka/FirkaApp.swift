import SwiftUI

@main
struct FirkaApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var phase

    /// Unit tests run inside the app: it stays idle so it doesn't sync or touch the data the tests use.
    static let underUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        if Self.underUnitTests {
            // The UI tests share this app's settings on the simulator: start the unit tests without their renames or hidden lessons.
            Renames.shared.subjects = [:]
            Renames.shared.teachers = [:]
            HiddenLessons.shared.rules = []
        }
        Background.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if Self.underUnitTests { Color.clear }
                else if store.loggedIn { MainTabs() } else { LoginScreen() }
            }
            .environment(store)
            .fullScreenCover(isPresented: Binding(get: { store.needsReauth }, set: { store.needsReauth = $0 })) {
                LoginScreen(reauth: true).environment(store)
            }
        }
        .onChange(of: phase, initial: true) { _, p in
            guard !Self.underUnitTests else { return }
            if p == .active, store.loggedIn { Task { await store.refreshIfStale() } }
            if p != .inactive, store.loggedIn, !store.isDemo { Task { await ServerPush.sync() } }  // settings changed meanwhile
            if p == .background, store.loggedIn, !store.isDemo { Background.schedule() }
        }
    }
}

struct MainTabs: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var tab = AppTab.home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Kezdőlap", systemImage: "house", value: .home) { HomeView() }
            Tab("Órarend", systemImage: "calendar", value: .timetable) { TimetableView() }
            if store.data.university {
                Tab("Jegyek", systemImage: "chart.line.uptrend.xyaxis", value: .grades) { UniversityGradesView() }
                Tab("Vizsgák", systemImage: "pencil.and.list.clipboard", value: .absences) { ExamsView() }
            } else {
                Tab("Jegyek", systemImage: "chart.line.uptrend.xyaxis", value: .grades) { GradesView() }
                Tab("Hiányzások", systemImage: "person.badge.clock", value: .absences) { AbsencesView() }
            }
            Tab("Egyebek", systemImage: "ellipsis.circle", value: AppTab.more) { MoreView() }
        }
        .onOpenURL { if let t = AppTab(url: $0) { tab = t } }  // a tapped server notification
        // While the app is open, move the Live Activity headline along at lesson changes.
        .task {
            while !Task.isCancelled {
                // starting is only allowed in the foreground
                await LessonLive.sync(store.data.widgetLessons, canStart: phase == .active)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
