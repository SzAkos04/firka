import SwiftUI
import BackgroundTasks
import UserNotifications
import WidgetKit

/// Everything shown in the app; cached to disk so the app opens instantly and works offline.
struct Snapshot: Codable {
    var studentName = ""
    var schoolName: String?
    var grades: [Ertekeles] = []
    var lessons: [Ora] = []          // this week + next week
    var absences: [Mulasztas] = []
    var homework: [HaziFeladat] = []
    var tests: [Szamonkeres] = []
    var notices: [FaliujsagElem] = []
    var notes: [Feljegyzes] = []
    var classAverages: [String: Double]?  // subject uid -> class average; optional so older caches still decode
    var inbox: [PostaladaElem]?  // teacher messages; nil in caches from before it existed
    var inboxBodies: [String: String]?  // full message texts (the list only has the first 100 characters)
    var updated: Date?

    static var file: URL { Shared.containerURL.appendingPathComponent("snapshot.json") }

    static func load() -> Snapshot? {
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
        lessons.filter { !$0.isEvent && !HiddenLessons.shared.isHidden($0) }.sorted { $0.kezdetIdopont < $1.kezdetIdopont }.map {
            WidgetLesson(subject: $0.title, room: $0.teremNeve, start: $0.kezdetIdopont, end: $0.vegIdopont,
                         number: $0.oraszam, cancelled: $0.isCancelled, substituted: $0.helyettesTanarNeve != nil)
        }
    }

    private func writeWidgetData() {
        let items = widgetLessons
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        try? e.encode(items).write(to: Shared.widgetFile, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Downloads everything from KRÉTA in parallel. Student, grades and timetable must succeed;
    /// the rest fall back to `old` so one flaky endpoint doesn't block the whole refresh.
    static func fetch(_ c: KretaClient, old: Snapshot?) async throws -> Snapshot {
        let now = Date()
        let week = now.startOfWeek
        let sept1 = Calendar.hu.date(from: DateComponents(year: Calendar.hu.component(.year, from: now), month: 9, day: 1))!
        let schoolStart = sept1 > now ? Calendar.hu.date(byAdding: .year, value: -1, to: sept1)! : sept1

        async let student: TanuloAdatlap = c.get("TanuloAdatlap")
        async let grades: [Ertekeles] = c.list("Ertekelesek")
        async let w1 = c.week(week)
        async let w2 = c.week(week.adding(days: 7))
        async let absences = soft("Mulasztasok", old?.absences ?? []) { try await c.list("Mulasztasok") }
        async let homework = soft("HaziFeladatok", old?.homework ?? []) { try await c.list("HaziFeladatok", from: schoolStart) }
        async let tests = soft("BejelentettSzamonkeresek", old?.tests ?? []) { try await c.list("BejelentettSzamonkeresek") }
        async let notices = soft("FaliujsagElemek", old?.notices ?? []) { try await c.list("FaliujsagElemek") }
        async let notes = soft("Feljegyzesek", old?.notes ?? []) { try await c.list("Feljegyzesek") }
        async let classAvg = classAverages(c)
        // nil until it first loads, so the first good list is a baseline for the notifications (Notifier.changes)
        async let inbox: [PostaladaElem]? = soft("postaladaelemek", old?.inbox) {
            let all: [PostaladaElem] = try await c.list(fullURL: "https://eugyintezes.e-kreta.hu/api/v1/kommunikacio/postaladaelemek/sajat")
            return all.filter { $0.tipus?.kod == "BEERKEZETT" && $0.isToroltElem != true }
        }

        let s = try await student
        return try await Snapshot(studentName: s.nev, schoolName: s.intezmenyNev, grades: grades,
                                  lessons: w1 + w2, absences: absences, homework: homework, tests: tests,
                                  notices: notices, notes: notes,
                                  classAverages: classAvg ?? old?.classAverages,  // keep the last known ones on failure
                                  inbox: inbox, inboxBodies: old?.inboxBodies,
                                  updated: now)
    }

    static func soft<T>(_ name: String, _ fallback: T, _ op: () async throws -> T) async throws -> T {
        do {
            return try await op()
        } catch KretaError.reauth {
            throw KretaError.reauth
        } catch where isCancellation(error) {
            throw CancellationError()
        } catch {
            log.error("\(name, privacy: .public) failed, keeping cached: \(String(describing: error), privacy: .public)")
            return fallback
        }
    }

    /// Optional extra: a failure here (or a school that hides class averages) must not fail the sync.
    static func classAverages(_ c: KretaClient) async -> [String: Double]? {
        do {
            let groups: [OsztalyCsoport] = try await c.get("OsztalyCsoportok")
            let tasks = Set(groups.filter { $0.isAktiv != false }
                .compactMap { $0.oktatasNevelesiFeladat?.uid?.split(separator: ",").first.map(String.init) })
            var result: [String: Double] = [:]
            for t in tasks {
                // the parameter is sent twice, like firka (and the official app) do
                let q = [URLQueryItem(name: "oktatasiNevelesiFeladatUid", value: t), URLQueryItem(name: "oktatasiNevelesiFeladatUid", value: t)]
                let avgs: [OsztalyAtlag] = try await c.list("Ertekelesek/Atlagok/OsztalyAtlagok", query: q)
                for a in avgs { if let v = a.osztalyCsoportAtlag, v > 0 { result[a.tantargy.uid] = v } }
            }
            log.info("class averages: \(result.count, privacy: .public) subjects from \(tasks.count, privacy: .public) groups")
            return result
        } catch {
            log.error("class averages failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

@MainActor @Observable
final class AppStore {
    var data = Snapshot.load() ?? Snapshot()
    var loggedIn: Bool
    var needsReauth = false
    var loading = false
    var error: String?
    private var weeks: [Date: [Ora]] = [:]
    private var client: KretaClient?
    var kretaClient: KretaClient? { client }

    /// Full text of a teacher message: downloaded once, then kept with the cached data.
    /// nil: nothing to download (not a teacher message, or the demo). A failed download throws.
    func fullMessage(_ id: String) async throws -> String? {
        guard id.hasPrefix("p"), let n = Int(id.dropFirst()) else { return nil }
        if let body = data.inboxBodies?[String(n)] { return body }
        guard let client, let url = URL(string: "https://eugyintezes.e-kreta.hu/api/v1/kommunikacio/postaladaelemek/\(n)") else { return nil }
        do {
            let full = try Kreta.apiDecoder.decode(PostaladaElem.self, from: try await client.raw(url))
            let body = full.uzenet.szoveg ?? ""
            data.inboxBodies = (data.inboxBodies ?? [:]).merging([String(n): body]) { $1 }
            data.save(widget: false)
            return body
        } catch {
            log.error("message \(n, privacy: .public) failed: \(String(describing: error), privacy: .public)")
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
            if surpriseGrades { seenGrades = Set(data.grades.map(\.uid)) }  // only grades from now on are surprises
        }
    }

    /// Grade UIDs already seen. nil until the first sync, which is seeded silently.
    private var seenGrades = (UserDefaults.standard.array(forKey: Pref.seenGrades) as? [String]).map(Set.init) {
        didSet { UserDefaults.standard.set(seenGrades.map(Array.init), forKey: Pref.seenGrades) }
    }

    var hiddenGrades: [Ertekeles] { Self.surprises(data.grades, seen: seenGrades, on: surpriseGrades) }

    /// The grades still to flip, oldest first. `seen` is nil before the first sync: nothing is a surprise then.
    nonisolated static func surprises(_ grades: [Ertekeles], seen: Set<String>?, on: Bool) -> [Ertekeles] {
        guard on, let seen else { return [] }
        return grades.filter { !seen.contains($0.uid) }.sorted { $0.keszitesDatuma < $1.keszitesDatuma }
    }

    var visibleGrades: [Ertekeles] {
        let hidden = Set(hiddenGrades.map(\.uid))
        return data.grades.filter { !hidden.contains($0.uid) }
    }

    func isHidden(_ g: Ertekeles) -> Bool {
        guard surpriseGrades, let seen = seenGrades else { return false }
        return !seen.contains(g.uid)
    }

    /// Revealed this session; they stay in the "új jegyek" section with their note until the next launch.
    private(set) var revealed: [Ertekeles] = []
    private(set) var revealNotes: [String: RevealNote] = [:]

    var newGradeRows: [Ertekeles] {
        (revealed + hiddenGrades).sorted { $0.keszitesDatuma < $1.keszitesDatuma }
    }

    func reveal(_ g: Ertekeles) {
        guard isHidden(g) else { return }
        let previous = visibleGrades.filter { $0.tantargy.uid == g.tantargy.uid }
        revealNotes[g.uid] = g.revealNote(previous: previous, rounding: rounding)
        revealed.append(g)
        seenGrades?.insert(g.uid)
    }

    private func seedSeenGrades() {
        if seenGrades == nil, data.updated != nil { seenGrades = Set(data.grades.map(\.uid)) }
    }

    init() {
        var token = Token.load()
        #if DEBUG
        // Dev hooks, set via `SIMCTL_CHILD_<name>=… xcrun simctl launch`:
        //   FIRKA_FORCE_REFRESH=1  pretend the access token expired (tests token renewal)
        //   FIRKA_HIDE_NEWEST=N    re-hide the N newest grades (tests surprise grades)
        //   FIRKA_DEMO=1           start over in demo mode (UI tests)
        //   FIRKA_DEMO=noClassAverages  the same without class averages (a school that hides them)
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
        client = token.map(KretaClient.init)
        loggedIn = token != nil || UserDefaults.standard.bool(forKey: Pref.demo)
        seedSeenGrades()
        #if DEBUG
        if env["FIRKA_PROBE"] != nil, let client { Task { await DebugProbe.run(client) } }
        if env["FIRKA_DEMO"] != nil { startDemo() }
        if env["FIRKA_DEMO"] == "noClassAverages" { data.classAverages = nil; data.save() }
        if let n = env["FIRKA_HIDE_NEWEST"].flatMap(Int.init) {
            seenGrades = Set(data.grades.sorted { $0.keszitesDatuma < $1.keszitesDatuma }.dropLast(n).map(\.uid))
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
        client = KretaClient(token: token)
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
        client = nil
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
        guard let client, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            var new = try await Snapshot.fetch(client, old: data)
            guard self.client === client else { return }  // logged out (or switched) while downloading
            log.info("refresh ok: \(new.grades.count, privacy: .public) grades, \(new.lessons.count, privacy: .public) lessons, \(new.absences.count, privacy: .public) absences")
            new.keepBodies(from: data)  // a message opened while it downloaded
            data = new
            data.save()
            seedSeenGrades()
            await LessonLive.sync(data.widgetLessons, canStart: true)
            weeks = [:]
            error = nil
        } catch KretaError.reauth {
            if self.client === client { needsReauth = true }
        } catch where isCancellation(error) {
        } catch {
            guard self.client === client else { return }
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

    func lessons(week: Date) async -> [Ora] {
        if let w = weeks[week] { return w }
        let end = week.adding(days: 7)
        let cached = data.lessons.filter { $0.kezdetIdopont >= week && $0.kezdetIdopont < end }
        // the snapshot holds its own sync's week and the next: those come from it, whatever today is
        let synced = data.updated?.startOfWeek
        guard let client, week != synced, week != synced?.adding(days: 7) else { return cached }
        do {
            let w = try await client.week(week)
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
        seenGrades = Set(data.grades.sorted { $0.keszitesDatuma < $1.keszitesDatuma }.dropLast(3).map(\.uid))
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
                       isHidden: (Ora) -> Bool) -> [Alert] {
        server ? [] : changes(old: old, new: new, now: Date(), enabled: enabled, surprise: surprise, isHidden: isHidden)
    }

    /// What's new between two syncs, as notifications. Pure, so the rules are testable.
    static func changes(old: Snapshot, new: Snapshot, now: Date, enabled: (String) -> Bool, surprise: Bool,
                        isHidden: (Ora) -> Bool) -> [Alert] {
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
                diff(old.grades, new.grades).map { "\($0.tantargy.name): \(surprise ? "új jegy" : $0.display)" })
            // the same grade with another value: the teacher corrected it
            let was = Dictionary(old.grades.map { ($0.uid, $0.display) }, uniquingKeysWith: { a, _ in a })
            add("edited", "Módosult egy jegy", { "\($0) jegy módosult" }, new.grades.compactMap { g in
                guard let before = was[g.uid], before != g.display else { return nil }
                return "\(g.tantargy.name): \(surprise ? "módosult" : "\(before) → \(g.display)")"
            })
        }
        if enabled("notifyLessons"), !old.lessons.isEmpty {
            let wasCancelled = Set(old.lessons.filter(\.isCancelled).map(\.id))
            let wasSubst = Dictionary(old.lessons.map { ($0.id, $0.helyettesTanarNeve) }, uniquingKeysWith: { a, _ in a })
            let future = new.lessons.filter { !$0.isEvent && $0.vegIdopont > now && !isHidden($0) }
            add("cancelled", "Elmaradt óra", { "\($0) elmaradt óra" },
                future.filter { $0.isCancelled && !wasCancelled.contains($0.id) }
                    .map { "\($0.title) – \($0.kezdetIdopont.hu("EEEE HH:mm"))" })
            add("substituted", "Helyettesítés", { "\($0) helyettesítés" },
                future.filter { !$0.isCancelled && $0.helyettesTanarNeve != nil && wasSubst[$0.id] != $0.helyettesTanarNeve }
                    .map { "\($0.title): \($0.helyettesTanarNeve?.renamedTeacher ?? "") (\($0.kezdetIdopont.hu("EEEE HH:mm")))" })
        }
        if enabled("notifyHomework") {
            add("homework", "Új házi feladat", { "\($0) új házi feladat" }, diff(old.homework, new.homework).map { $0.tantargy.name })
            add("tests", "Új számonkérés", { "\($0) új számonkérés" },
                diff(old.tests, new.tests).map { "\($0.tantargy.name): \($0.temaja ?? $0.modja?.leiras ?? "")" })
        }
        if enabled("notifyAbsences") {
            add("absences", "Új hiányzás/késés", { "\($0) új hiányzás/késés" },
                diff(old.absences, new.absences).map { "\($0.tantargy.name): \($0.stateLabel)" })
            // KRÉTA keeps the absence and changes its state; unexcused is the one that matters
            let wasUnexcused = Dictionary(old.absences.map { ($0.uid, $0.igazolasAllapota == "Igazolatlan") }, uniquingKeysWith: { a, _ in a })
            add("unexcused", "Igazolatlan lett", { "\($0) mulasztás igazolatlan lett" },
                new.absences.filter { $0.igazolasAllapota == "Igazolatlan" && wasUnexcused[$0.uid] == false }
                    .map { "\($0.tantargy.name): \($0.stateLabel)" })
        }
        if enabled("notifyMessages") {
            // The first sync with teacher messages would otherwise announce years of them.
            let baseline = old.inbox == nil ? old.messages + new.messages.filter { $0.id.hasPrefix("p") } : old.messages
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

    private static func run() async -> Bool {
        UserDefaults.standard.set(Date(), forKey: Pref.lastBackgroundRun)  // shown in Settings: does iOS run us at all?
        guard let token = Token.load(), let old = Snapshot.load() else { return false }
        do {
            var new = try await Snapshot.fetch(KretaClient(token: token), old: old)
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
