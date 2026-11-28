import SwiftUI
import BackgroundTasks
import UserNotifications
import WidgetKit

/// Everything shown in the app; cached to disk so the app opens instantly and works offline.
struct Snapshot: Codable {
    var studentName = ""
    var schoolName: String?
    var grades: [Grade] = []
    var lessons: [Lesson] = []       // this week + next week
    var absences: [Absence] = []
    var homework: [Homework] = []
    var tests: [AnnouncedTest] = []
    /// As the lists give them (teacher messages shortened); `messages` adds the full texts downloaded since.
    var messageList: [Message] = []
    /// Message sources (id prefixes) that have loaded at least once: a source's first list is a baseline, not news.
    var messageSources: Set<String> = []
    var classAverages: [String: Double]?  // subject id -> class average
    var messageBodies: [String: String]?  // full message texts by message id
    var updated: Date?

    /// v2: the app's own models (Domain.swift). The KRÉTA-shaped cache of earlier builds is dropped, one sync refills it.
    static var file: URL { Shared.containerURL.appendingPathComponent("snapshot-v2.json") }
    private static var oldFile: URL { Shared.containerURL.appendingPathComponent("snapshot.json") }

    static func load() -> Snapshot? {
        try? FileManager.default.removeItem(at: oldFile)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(Snapshot.self, from: data)
    }

    func save(widget: Bool = true) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        do {
            try e.encode(self).write(to: Snapshot.file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            log.error("saving the cache failed: \(String(describing: error), privacy: .public)")
        }
        if widget { writeWidgetData() }
    }

    static func delete() {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: Shared.widgetFile)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Lessons in the form the widget and the Live Activity use.
    var widgetLessons: [WidgetLesson] {
        lessons.filter { !$0.isEvent && !HiddenLessons.shared.isHidden($0) }.sorted { $0.start < $1.start }.map {
            WidgetLesson(subject: $0.title, room: $0.room, start: $0.start, end: $0.end,
                         number: $0.number, cancelled: $0.cancelled, substituted: $0.substitute != nil)
        }
    }

    private func writeWidgetData() {
        let items = widgetLessons
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        try? e.encode(items).write(to: Shared.widgetFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        WidgetCenter.shared.reloadAllTimelines()
    }
}

@MainActor @Observable
final class AppStore {
    var data = Snapshot.load() ?? Snapshot()
    var loggedIn: Bool
    var needsReauth = false
    var loading = false
    var error: String?
    private var weeks: [Date: [Lesson]] = [:]
    /// The logged-in school system; internal so tests can plug in their own.
    var provider: SchoolProvider?

    /// Full text of a teacher message: downloaded once, then kept with the cached data.
    /// nil: nothing to download (not a teacher message, or the demo). A failed download throws.
    func fullMessage(_ id: String) async throws -> String? {
        if let body = data.messageBodies?[id] { return body }
        guard let provider else { return nil }
        do {
            guard let body = try await provider.fullMessage(id) else { return nil }
            data.messageBodies = (data.messageBodies ?? [:]).merging([id: body]) { $1 }
            data.save(widget: false)
            return body
        } catch {
            log.error("message \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
    var isDemo: Bool { UserDefaults.standard.bool(forKey: Pref.demo) }

    var rounding = Rounding.load() { didSet { rounding.save() } }

    // MARK: Surprise grades (firka's "meglepetés jegyek")
    // New grades stay hidden (also from averages) until their card is flipped on the home screen.

    var surpriseGrades = Pref.on(Pref.surpriseGrades) {
        didSet {
            UserDefaults.standard.set(surpriseGrades, forKey: Pref.surpriseGrades)
            if surpriseGrades { seenGrades = Set(data.grades.map(\.id)) }  // only grades from now on are surprises
        }
    }

    /// Grade UIDs already seen. nil until the first sync, which is seeded silently.
    private var seenGrades = (UserDefaults.standard.array(forKey: Pref.seenGrades) as? [String]).map(Set.init) {
        didSet { UserDefaults.standard.set(seenGrades.map(Array.init), forKey: Pref.seenGrades) }
    }

    var hiddenGrades: [Grade] { Self.surprises(data.grades, seen: seenGrades, on: surpriseGrades) }

    /// The grades still to flip, oldest first. `seen` is nil before the first sync: nothing is a surprise then.
    nonisolated static func surprises(_ grades: [Grade], seen: Set<String>?, on: Bool) -> [Grade] {
        guard on, let seen else { return [] }
        return grades.filter { !seen.contains($0.id) }.sorted { $0.date < $1.date }
    }

    var visibleGrades: [Grade] {
        let hidden = Set(hiddenGrades.map(\.id))
        return data.grades.filter { !hidden.contains($0.id) }
    }

    func isHidden(_ g: Grade) -> Bool {
        guard surpriseGrades, let seen = seenGrades else { return false }
        return !seen.contains(g.id)
    }

    /// Revealed this session; they stay in the "új jegyek" section with their note until the next launch.
    private(set) var revealed: [Grade] = []
    private(set) var revealNotes: [String: RevealNote] = [:]

    var newGradeRows: [Grade] {
        (revealed + hiddenGrades).sorted { $0.date < $1.date }
    }

    func reveal(_ g: Grade) {
        guard isHidden(g) else { return }
        let previous = visibleGrades.filter { $0.subject.id == g.subject.id }
        revealNotes[g.id] = g.revealNote(previous: previous, rounding: rounding)
        revealed.append(g)
        seenGrades?.insert(g.id)
    }

    private func seedSeenGrades() {
        if seenGrades == nil, data.updated != nil { seenGrades = Set(data.grades.map(\.id)) }
    }

    init() {
        var token = Token.load()
        #if DEBUG
        // Dev hooks, set via `SIMCTL_CHILD_<name>=… xcrun simctl launch`:
        //   FIRKA_FORCE_REFRESH=1  pretend the access token expired (tests token renewal)
        //   FIRKA_HIDE_NEWEST=N    re-hide the N newest grades (tests surprise grades)
        //   FIRKA_DEMO=1           start over in demo mode (UI tests)
        //   FIRKA_DEMO=noClassAverages  the same without class averages (a school that hides them)
        //   FIRKA_DEMO=reportCard       the same with half-year grades (the report card)
        let env = ProcessInfo.processInfo.environment
        if env["FIRKA_FORCE_REFRESH"] != nil { token?.expiry = .distantPast }
        if env["FIRKA_DEMO"] != nil {
            UIView.setAnimationsEnabled(false)  // UI tests: no waiting for every push and tab switch to finish animating
            Token.delete()
            token = nil
            HiddenLessons.shared.rules = []
            Renames.shared.subjects = [:]
            Renames.shared.teachers = [:]
            UserDefaults.standard.removeObject(forKey: Pref.surpriseGrades)
            UserDefaults.standard.removeObject(forKey: Pref.timetableMonth)
        }
        #endif
        provider = token.map(KretaProvider.init(token:))
        loggedIn = token != nil || UserDefaults.standard.bool(forKey: Pref.demo)
        seedSeenGrades()
        #if DEBUG
        if env["FIRKA_PROBE"] != nil, let p = provider as? KretaProvider { Task { await DebugProbe.run(p.client) } }
        if env["FIRKA_DEMO"] != nil { startDemo() }
        if env["FIRKA_DEMO"] == "noClassAverages" { data.classAverages = nil; data.save() }
        if env["FIRKA_DEMO"] == "reportCard" {
            let half = data.grades.prefix(3).map { g in
                var h = g
                h.id += "-half"
                h.kind = .halfYear
                h.kindText = "Félévi jegy"
                h.weight = nil
                return h
            }
            data.grades += half
            seenGrades?.formUnion(half.map(\.id))
            data.save()
        }
        if let n = env["FIRKA_HIDE_NEWEST"].flatMap(Int.init) {
            seenGrades = Set(data.grades.sorted { $0.date < $1.date }.dropLast(n).map(\.id))
        }
        #endif
    }

    func login(code: String, pkce: PKCE) async throws {
        await signedIn(try await Kreta.exchange(code: code, verifier: pkce.verifier))
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        Background.schedule()
    }

    /// After a successful login: keep the token and sync.
    func signedIn(_ token: Token) async {
        let previous = Token.load()
        if previous?.iss != token.iss || previous?.username != token.username {
            clearAccountData()  // another account (or none before): don't mix data or "seen" grades
        }
        token.save()
        UserDefaults.standard.set(false, forKey: Pref.demo)
        provider = KretaProvider(token: token)
        needsReauth = false
        loggedIn = true
        await refresh()
    }

    /// After hiding/renaming lessons: the widget and the Live Activity read the saved data.
    func lessonsChanged() {
        data.save()
        Task { await LessonLive.sync(data.widgetLessons, canStart: false) }
        Task { await ServerPush.sync() }  // the server applies the hidden lessons and names from its next poll
    }

    func logout() {
        Token.delete()
        BGTaskScheduler.shared.cancelAllTaskRequests()
        UserDefaults.standard.set(false, forKey: Pref.demo)
        provider = nil
        clearAccountData()
        loggedIn = false
        Task { await LessonLive.endAll() }
    }

    private func clearAccountData() {
        Snapshot.delete()
        try? FileManager.default.removeItem(at: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("attachments"))
        data = Snapshot()
        weeks = [:]
        seenGrades = nil
        revealed = []
        revealNotes = [:]
        error = nil
    }

    func refresh() async {
        guard let provider, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            var new = try await provider.fetch(old: data)
            guard self.provider === provider else { return }  // logged out (or switched) while downloading
            log.info("refresh ok: \(new.grades.count, privacy: .public) grades, \(new.lessons.count, privacy: .public) lessons, \(new.absences.count, privacy: .public) absences")
            new.keepBodies(from: data)  // a message opened while it downloaded
            data = new
            data.save()
            seedSeenGrades()
            await LessonLive.sync(data.widgetLessons, canStart: true)
            weeks = [:]
            error = nil
        } catch KretaError.reauth {
            if self.provider === provider { needsReauth = true }
        } catch where isCancellation(error) {
        } catch {
            guard self.provider === provider else { return }
            log.error("refresh failed: \(String(describing: error), privacy: .public)")
            self.error = (error as? LocalizedError)?.errorDescription ?? "Nem sikerült frissíteni (nincs internet?)."
        }
    }

    func refreshIfStale() async {
        // A background refresh may have written newer data while we were suspended.
        if let disk = Snapshot.load(), let d = disk.updated, d > (data.updated ?? .distantPast) { data = disk }
        await LessonLive.sync(data.widgetLessons, canStart: true)
        if let u = data.updated, Date().timeIntervalSince(u) < 300 { return }
        await refresh()
    }

    /// Lessons for any week (cached in memory; the current two weeks come from the snapshot).
    private static let timetableError = "Nem sikerült betölteni az órarendet."

    func lessons(week: Date) async -> [Lesson] {
        if let w = weeks[week] { return w }
        let end = week.adding(days: 7)
        let cached = data.lessons.filter { $0.start >= week && $0.start < end }
        // the snapshot holds its own sync's week and the next: those come from it, whatever today is
        let synced = data.updated?.startOfWeek
        guard let provider, week != synced, week != synced?.adding(days: 7) else { return cached }
        do {
            let w = try await provider.week(week)
            weeks[week] = w
            if error == Self.timetableError { error = nil }
            return w
        } catch KretaError.reauth {
            needsReauth = true
        } catch where isCancellation(error) {
        } catch {
            log.error("week \(week, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            self.error = Self.timetableError
        }
        return cached
    }

    #if DEBUG
    func startDemo() {
        UserDefaults.standard.set(true, forKey: Pref.demo)
        data = .demo
        data.save()
        // leave the 3 newest grades as surprises
        seenGrades = Set(data.grades.sorted { $0.date < $1.date }.dropLast(3).map(\.id))
        loggedIn = true
    }
    #endif
}

// MARK: - Notifications (diff old snapshot vs new, like firka's NotificationDiffService)

enum Notifier {
    static let kinds: [(key: String, label: String)] = [
        ("notifyGrades", "Új jegyek"),
        ("notifyLessons", "Elmaradt órák, helyettesítések"),
        ("notifyHomework", "Házi feladatok, számonkérések"),
        ("notifyAbsences", "Hiányzások, késések"),
        ("notifyMessages", "Üzenetek, feljegyzések"),
    ]

    static func enabled(_ key: String) -> Bool { Pref.on(key) }

    /// What stops notifications from arriving at all, in words for the settings screen; nil if nothing does.
    static func blocker(auth: UNAuthorizationStatus, refresh: UIBackgroundRefreshStatus, lowPower: Bool) -> String? {
        if auth == .denied { return "Az értesítések ki vannak kapcsolva a Firkának az iOS Beállításokban." }
        if auth == .notDetermined { return "A Firka még nem kapott engedélyt értesítések küldésére." }
        if refresh != .available { return "A Háttérben frissítés ki van kapcsolva, így a Firka nem tud új jegyeket keresni, amíg nincs megnyitva." }
        if lowPower { return "Alacsony fogyasztású módban az iOS nem frissíti az appokat a háttérben." }
        return nil
    }

    struct Alert: Equatable {
        var id: String
        var title: String
        var lines: [String]
    }

    /// Background refresh only: in the foreground the user sees the changes on screen.
    static func post(old: Snapshot, new: Snapshot) {
        for a in toPost(old: old, new: new, server: ServerPush.active, enabled: enabled, surprise: Pref.on(Pref.surpriseGrades),
                        isHidden: HiddenLessons.shared.isHidden) {
            send(a)
        }
    }

    /// What the phone itself announces: nothing while the owner's server sends the notifications (ServerPush).
    static func toPost(old: Snapshot, new: Snapshot, server: Bool, enabled: (String) -> Bool, surprise: Bool,
                       isHidden: (Lesson) -> Bool) -> [Alert] {
        server ? [] : changes(old: old, new: new, now: Date(), enabled: enabled, surprise: surprise, isHidden: isHidden)
    }

    /// What's new between two syncs, as notifications. Pure, so the rules are testable.
    static func changes(old: Snapshot, new: Snapshot, now: Date, enabled: (String) -> Bool, surprise: Bool,
                        isHidden: (Lesson) -> Bool) -> [Alert] {
        // First sync after login: nothing to compare against, don't spam the whole year.
        guard old.updated != nil, old.studentName == new.studentName else { return [] }
        var out: [Alert] = []
        func add(_ id: String, _ one: String, _ many: (Int) -> String, _ lines: [String]) {
            if !lines.isEmpty { out.append(Alert(id: id, title: lines.count == 1 ? one : many(lines.count), lines: Array(lines.prefix(5)))) }
        }

        // If KRÉTA once returned an empty list (firka has seen this as a "stale session"),
        // treat the next full list as a new baseline instead of announcing everything in it.
        func diff<T: Identifiable>(_ a: [T], _ b: [T]) -> [T] where T.ID == String {
            if a.isEmpty && b.count > 3 { return [] }
            let seen = Set(a.map(\.id))
            return b.filter { !seen.contains($0.id) }
        }

        if enabled("notifyGrades") {
            // with surprise grades on, don't spoil the value in the notification
            add("grades", "Új jegy érkezett", { "\($0) új jegy érkezett" },
                diff(old.grades, new.grades).map { "\($0.subject.name): \(surprise ? "új jegy" : $0.display)" })
            // the same grade with another value: the teacher corrected it
            let was = Dictionary(old.grades.map { ($0.id, $0.display) }, uniquingKeysWith: { a, _ in a })
            add("edited", "Módosult egy jegy", { "\($0) jegy módosult" }, new.grades.compactMap { g in
                guard let before = was[g.id], before != g.display else { return nil }
                return "\(g.subject.name): \(surprise ? "módosult" : "\(before) → \(g.display)")"
            })
        }
        if enabled("notifyLessons"), !old.lessons.isEmpty {
            let wasCancelled = Set(old.lessons.filter(\.cancelled).map(\.id))
            let wasSubst = Dictionary(old.lessons.map { ($0.id, $0.substitute) }, uniquingKeysWith: { a, _ in a })
            let future = new.lessons.filter { !$0.isEvent && $0.end > now && !isHidden($0) }
            add("cancelled", "Elmaradt óra", { "\($0) elmaradt óra" },
                future.filter { $0.cancelled && !wasCancelled.contains($0.id) }
                    .map { "\($0.title) – \($0.start.hu("EEEE HH:mm"))" })
            add("substituted", "Helyettesítés", { "\($0) helyettesítés" },
                future.filter { !$0.cancelled && $0.substitute != nil && wasSubst[$0.id] != $0.substitute }
                    .map { "\($0.title): \($0.substitute?.renamedTeacher ?? "") (\($0.start.hu("EEEE HH:mm")))" })
        }
        if enabled("notifyHomework") {
            add("homework", "Új házi feladat", { "\($0) új házi feladat" }, diff(old.homework, new.homework).map { $0.subject.name })
            add("tests", "Új számonkérés", { "\($0) új számonkérés" },
                diff(old.tests, new.tests).map { "\($0.subject.name): \($0.topic ?? $0.mode ?? "")" })
        }
        if enabled("notifyAbsences") {
            add("absences", "Új hiányzás/késés", { "\($0) új hiányzás/késés" },
                diff(old.absences, new.absences).map { "\($0.subject.name): \($0.stateLabel)" })
            // KRÉTA keeps the absence and changes its state; unexcused is the one that matters
            let wasUnexcused = Dictionary(old.absences.map { ($0.id, $0.state == .unexcused) }, uniquingKeysWith: { a, _ in a })
            add("unexcused", "Igazolatlan lett", { "\($0) mulasztás igazolatlan lett" },
                new.absences.filter { $0.state == .unexcused && wasUnexcused[$0.id] == false }
                    .map { "\($0.subject.name): \($0.stateLabel)" })
        }
        if enabled("notifyMessages") {
            // A source's first list (e.g. the first sync with teacher messages) would otherwise announce years of them.
            let baseline = old.messages + new.messages.filter { !old.messageSources.contains($0.source) }
            add("messages", "Új üzenet", { "\($0) új üzenet" }, diff(baseline, new.messages).map(\.title))
        }
        return out
    }

    private static func send(_ a: Alert) {
        let c = UNMutableNotificationContent()
        c.title = a.title
        c.body = a.lines.joined(separator: "\n")
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(a.id)-\(Date().timeIntervalSince1970)", content: c, trigger: nil))
    }
}

// MARK: - Background refresh

enum Background {
    /// "$(APP_ID).refresh", from Info.plist (BGTaskSchedulerPermittedIdentifiers), so the two can't drift apart.
    static let id = (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?.first ?? ""

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            nonisolated(unsafe) let task = task  // iOS hands it to this handler alone
            schedule()
            let work = Task {
                let ok = await run()
                task.setTaskCompleted(success: ok)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: id)
        // iOS decides the real timing; ask for the next lesson change so the Live Activity headline keeps up
        let next = Snapshot.load().flatMap { LessonLive.nextChange($0.widgetLessons) }
        r.earliestBeginDate = min(next ?? .distantFuture, Date().addingTimeInterval(15 * 60))
        try? BGTaskScheduler.shared.submit(r)
    }

    /// One background refresh (internal for the tests): download, alert, save for the app and the widget.
    static func run() async -> Bool {
        UserDefaults.standard.set(Date(), forKey: Pref.lastBackgroundRun)  // shown in Settings: does iOS run us at all?
        guard let token = Token.load(), let old = Snapshot.load() else { return false }
        do {
            var new = try await KretaProvider(token: token).fetch(old: old)
            Notifier.post(old: old, new: new)
            new.keepBodies(from: Snapshot.load())  // the app may have saved a message text meanwhile
            new.save()
            await LessonLive.sync(new.widgetLessons, canStart: false)
            return true
        } catch {
            log.error("background refresh failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
