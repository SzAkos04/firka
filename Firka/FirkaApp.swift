import SwiftUI

@main
struct FirkaApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var phase

    /// Unit tests run inside the app: it stays idle so it doesn't sync or touch the data the tests use.
    static let underUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() { Background.register() }

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
            if p == .background, store.loggedIn, !store.isDemo { Background.schedule() }
        }
    }
}

struct MainTabs: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView {
            Tab("Kezdőlap", systemImage: "house") { HomeView() }
            Tab("Órarend", systemImage: "calendar") { TimetableView() }
            Tab("Jegyek", systemImage: "chart.line.uptrend.xyaxis") { GradesView() }
            Tab("Hiányzások", systemImage: "person.badge.clock") { AbsencesView() }
            Tab("Egyebek", systemImage: "ellipsis.circle") { MoreView() }
        }
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
