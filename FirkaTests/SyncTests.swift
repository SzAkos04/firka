import Foundation
import Testing
@testable import Firka

/// A whole KRÉTA account behind the stub. Endpoint names in `fail` answer 500.
struct FakeKreta {
    var grades = [gradeJSON("g1", 5, 100), gradeJSON("g2", 3, 100)]
    var lessons: [String] = []
    var absences: [String] = []
    var inbox = [inboxJSON(1), inboxJSON(2, kind: "ELKULDOTT"), inboxJSON(3, deleted: true)]
    var messageBody = "Teljes szöveg"
    var fail: Set<String> = []

    static func name(_ r: URLRequest) -> String {
        let p = r.url!.path
        if p.hasSuffix("/postaladaelemek/sajat") { return "postaladaelemek" }
        if p.contains("/postaladaelemek/") { return "uzenet" }
        if p == "/connect/token" { return "token" }
        return p.components(separatedBy: "/sajat/").last ?? p
    }

    func reply(_ r: URLRequest) -> Stub.Reply {
        let n = Self.name(r)
        if fail.contains(n) { return .init(status: 500, body: "") }
        let list = { (items: [String]) in Stub.Reply(body: "[" + items.joined(separator: ",") + "]") }
        switch n {
        case "TanuloAdatlap": return .init(body: studentJSON)
        case "Ertekelesek": return list(grades)
        case "OrarendElemek": return list(lessons)
        case "Mulasztasok": return list(absences)
        case "OsztalyCsoportok":
            return list([#"{"OktatasNevelesiFeladat":{"Uid":"1,Gimnazium"},"IsAktiv":true}"#,
                         #"{"OktatasNevelesiFeladat":{"Uid":"2,Regi"},"IsAktiv":false}"#])
        case "Ertekelesek/Atlagok/OsztalyAtlagok":
            return list([#"{"Tantargy":\#(subjectJSON),"OsztalyCsoportAtlag":3.87}"#, #"{"Tantargy":\#(historyJSON),"OsztalyCsoportAtlag":0}"#])
        case "postaladaelemek": return list(inbox)
        case "uzenet": return .init(body: inboxJSON(1, text: messageBody))
        case "token": return .init(body: grantJSON(access: "acc2"))
        default: return list([])
        }
    }
}

extension Global {
    /// Syncing, logging in and out, and the app state around it, against the fake KRÉTA.
    @MainActor @Suite("Sync and app state", .serialized)
    final class Sync {
        private let keys = [Pref.demo, Pref.seenGrades, Pref.surpriseGrades, Pref.liveActivity]
        nonisolated(unsafe) private let savedPrefs: [String: Any]  // read back in deinit
        private let savedToken = Token.load()
        private let savedCache = try? Data(contentsOf: Snapshot.file)

        init() {
            savedPrefs = Dictionary(uniqueKeysWithValues: keys.compactMap { k in UserDefaults.standard.object(forKey: k).map { (k, $0) } })
            keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
            UserDefaults.standard.set(false, forKey: Pref.liveActivity)  // no real Live Activity from the tests
            Token.delete()
            Snapshot.delete()
        }

        deinit {
            Stub.stop()
            keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
            for (k, v) in savedPrefs { UserDefaults.standard.set(v, forKey: k) }
            Token.delete()
            savedToken?.save()
            Snapshot.delete()
            try? savedCache?.write(to: Snapshot.file)
        }

        /// A logged-in store with `cache` on disk.
        func store(cache: Snapshot? = nil, _ fake: FakeKreta = FakeKreta()) -> AppStore {
            testToken().save()
            cache?.save(widget: false)
            Stub.start(fake.reply)
            return AppStore()
        }

        @Test("a full sync: everything downloaded, saved for the next launch and the widget")
        func refresh() async throws {
            let monday = Date().startOfWeek
            var fake = FakeKreta()
            fake.lessons = [lessonJSON("l1", start: monday.addingTimeInterval(8 * 3600)),
                            lessonJSON("l2", start: monday.adding(days: 7).addingTimeInterval(8 * 3600))]
            let s = store(cache: nil, fake)
            #expect(s.loggedIn && s.data.updated == nil)
            await s.refresh()
            #expect(s.error == nil)
            #expect(s.data.studentName == "Teszt Elek" && s.data.schoolName == "Teszt Gimnázium")
            #expect(s.data.grades.map(\.uid) == ["g1", "g2"])
            #expect(s.data.lessons.map(\.uid) == ["l1", "l2"], "this week and next week, once each")
            #expect(s.data.inbox?.map(\.azonosito) == [1], "received and not deleted only")
            #expect(s.data.classAverages == ["1,MAT": 3.87], "active groups only, no zero averages")
            #expect(Snapshot.load()?.grades.count == 2)
            #expect(FileManager.default.fileExists(atPath: Shared.widgetFile.path))
            let avgQueries = Stub.requests.filter { FakeKreta.name($0) == "Ertekelesek/Atlagok/OsztalyAtlagok" }
            #expect(avgQueries.map { $0.query["oktatasiNevelesiFeladatUid"] } == [["1", "1"]], "only the active group, sent twice")
            #expect(Stub.requests.first { FakeKreta.name($0) == "HaziFeladatok" }?.query["datumTol"]?.first?.hasSuffix("-09-01") == true,
                    "homework from the start of the school year")
        }

        @Test("the first sync doesn't make every existing grade a surprise; later ones are")
        func surpriseSeeding() async {
            let s = store()
            await s.refresh()
            #expect(s.hiddenGrades.isEmpty)
            var fake = FakeKreta()
            fake.grades.append(gradeJSON("g3", 4, 100, date: "2026-11-20T08:00:00Z"))
            Stub.start(fake.reply)
            await s.refresh()
            #expect(s.hiddenGrades.map(\.uid) == ["g3"])
            #expect(!s.visibleGrades.contains { $0.uid == "g3" }, "hidden also from the averages")
            let g3 = s.hiddenGrades[0]
            s.reveal(g3)
            #expect(s.hiddenGrades.isEmpty && s.visibleGrades.contains { $0.uid == "g3" })
            #expect(s.newGradeRows.map(\.uid) == ["g3"] && s.revealNotes["g3"] != nil, "stays in the list with its note")
            s.surpriseGrades = false
            s.surpriseGrades = true
            #expect(s.hiddenGrades.isEmpty, "switching it on only hides grades that come later")
        }

        @Test("one failing extra endpoint keeps its cached data; the sync still succeeds")
        func softFailure() async throws {
            var old = Snapshot()
            old.studentName = "Teszt Elek"
            old.absences = try decode(#"[{"Uid":"77","Tantargy":\#(subjectJSON),"Datum":"2025-11-09T23:00:00Z","IgazolasAllapota":"Igazolt"}]"#)
            old.classAverages = ["1,MAT": 4.1]
            old.updated = Date().addingTimeInterval(-3600)
            var fake = FakeKreta()
            fake.fail = ["Mulasztasok", "OsztalyCsoportok"]
            let s = store(cache: old, fake)
            await s.refresh()
            #expect(s.error == nil)
            #expect(s.data.absences.map(\.uid) == ["77"] && s.data.classAverages == ["1,MAT": 4.1])
            #expect(s.data.grades.count == 2)
        }

        @Test("an inbox that never loaded stays unknown when it fails, so its first good list is a baseline, not 50 alerts")
        func inboxNeverLoaded() async throws {
            var old = Snapshot()
            old.studentName = "Teszt Elek"
            old.updated = Date().addingTimeInterval(-3600)
            var fake = FakeKreta()
            fake.fail = ["postaladaelemek"]
            let s = store(cache: old, fake)
            await s.refresh()
            #expect(s.error == nil)
            #expect(s.data.inbox == nil)
        }

        @Test("grades or the timetable failing fails the sync and keeps everything as it was", arguments: ["Ertekelesek", "OrarendElemek", "TanuloAdatlap"])
        func hardFailure(_ endpoint: String) async {
            var old = Snapshot()
            old.studentName = "Régi"
            old.updated = Date().addingTimeInterval(-3600)
            var fake = FakeKreta()
            fake.fail = [endpoint]
            let s = store(cache: old, fake)
            await s.refresh()
            #expect(s.error == "A KRÉTA szerver hibát adott (500).")
            #expect(s.data.studentName == "Régi" && Snapshot.load()?.studentName == "Régi")
        }

        @Test("an expired login asks to log in again instead of showing an error")
        func reauth() async {
            let s = store()
            Stub.start { _ in .init(status: 401, body: "") }
            await s.refresh()
            #expect(s.needsReauth && s.error == nil)
        }

        @Test("a fresh cache (under 5 minutes) isn't downloaded again; a newer one on disk is picked up")
        func refreshIfStale() async {
            var c = Snapshot()
            c.studentName = "Friss"
            c.updated = Date().addingTimeInterval(-60)
            let s = store(cache: c)
            await s.refreshIfStale()
            #expect(Stub.requests.isEmpty)
            var newer = c
            newer.studentName = "Háttérben frissült"
            newer.updated = Date()
            newer.save(widget: false)
            await s.refreshIfStale()
            #expect(s.data.studentName == "Háttérben frissült" && Stub.requests.isEmpty)
        }

        @Test("logout forgets the token, the cache and the seen grades")
        func logout() async {
            let s = store()
            await s.refresh()
            s.logout()
            #expect(!s.loggedIn && Token.load() == nil && Snapshot.load() == nil)
            #expect(s.data.grades.isEmpty && s.data.updated == nil)
            #expect(!FileManager.default.fileExists(atPath: Shared.widgetFile.path))
            await s.refresh()
            #expect(s.data.updated == nil, "no client, no sync")
        }

        @Test("logging in with another account starts clean; the same account keeps its data")
        func accountSwitch() async {
            let s = store()
            await s.refresh()
            Stub.start { _ in .init(status: 500, body: "") }  // the sync after login fails: what's left is what was kept
            await s.signedIn(testToken(access: "same", user: "diak"))
            #expect(s.data.grades.count == 2)
            await s.signedIn(testToken(access: "other", user: "masik"))
            #expect(s.data.grades.isEmpty && Snapshot.load() == nil)
            #expect(Token.load()?.username == "masik" && s.loggedIn && !s.needsReauth)
        }

        @Test("timetable weeks: this and next week from the cache, others downloaded once")
        func weeks() async throws {
            let monday = Date().startOfWeek
            var c = Snapshot()
            c.lessons = [lesson("cached", day: monday, from: 480)]
            c.updated = Date()
            var fake = FakeKreta()
            fake.lessons = [lessonJSON("far", start: monday.adding(days: 21).addingTimeInterval(8 * 3600))]
            let s = store(cache: c, fake)
            #expect(await s.lessons(week: monday).map(\.uid) == ["cached"])
            #expect(await s.lessons(week: monday.adding(days: 7)).isEmpty)
            #expect(Stub.requests.isEmpty)
            #expect(await s.lessons(week: monday.adding(days: 21)).map(\.uid) == ["far"])
            #expect(await s.lessons(week: monday.adding(days: 21)).map(\.uid) == ["far"])
            #expect(Stub.requests.count == 1)
        }

        @Test("a cache from an earlier week (the last sync failed) doesn't stand for this week and the next: they are downloaded")
        func weeksFromOldCache() async throws {
            let monday = Date().startOfWeek
            var c = Snapshot()
            c.lessons = [lesson("old", day: monday.adding(days: -7), from: 480)]
            c.updated = monday.adding(days: -5)
            var fake = FakeKreta()
            fake.lessons = [lessonJSON("next", start: monday.adding(days: 7).addingTimeInterval(8 * 3600))]
            let s = store(cache: c, fake)
            #expect(await s.lessons(week: monday.adding(days: -7)).map(\.uid) == ["old"])
            #expect(Stub.requests.isEmpty)
            #expect(await s.lessons(week: monday.adding(days: 7)).map(\.uid) == ["next"])
        }

        @Test("hiding or renaming a lesson tells the server at once, when it sends the notifications")
        func lessonsChangedSyncsServer() async throws {
            setenv("FIRKA_PUSH_SERVER", "https://push.test:8446", 1)
            UserDefaults.standard.set(true, forKey: Pref.serverPush)
            defer { unsetenv("FIRKA_PUSH_SERVER"); UserDefaults.standard.removeObject(forKey: Pref.serverPush) }
            let s = store()
            s.lessonsChanged()
            for _ in 0..<200 where !Stub.paths().contains("/api/prefs") { try await Task.sleep(for: .milliseconds(10)) }
            #expect(Stub.requests.contains { $0.url?.path == "/api/prefs" && $0.httpMethod == "PUT" })
        }

        @Test("a week that can't be loaded shows an error, which goes away with the next good one")
        func weekError() async {
            let monday = Date().startOfWeek
            let s = store()
            Stub.start { _ in .init(status: 500, body: "") }
            #expect(await s.lessons(week: monday.adding(days: 28)).isEmpty)
            #expect(s.error == "Nem sikerült betölteni az órarendet.")
            Stub.start(FakeKreta().reply)
            _ = await s.lessons(week: monday.adding(days: 35))
            #expect(s.error == nil)
            Stub.start { _ in .init(status: 401, body: "") }
            _ = await s.lessons(week: monday.adding(days: 42))
            #expect(s.needsReauth)
        }

        @Test("attachments: downloaded once into the cache under a safe name; a gone file is an error")
        func attachment() async throws {
            let s = store()
            Stub.start { r in r.url?.path.hasSuffix("/77") == true ? .init(body: "%PDF-1.4") : .init(status: 404, body: "") }
            let a = Csatolmany(azonosito: 77, fajlNev: "../Hírlevél.pdf")
            let file = try await s.download(a)
            #expect(file.lastPathComponent == ".._Hírlevél.pdf" && file.deletingLastPathComponent().lastPathComponent == "77")
            #expect(try String(contentsOf: file, encoding: .utf8) == "%PDF-1.4")
            #expect(try await s.download(a) == file && Stub.requests.count == 1, "the second open comes from the cache")
            await #expect(throws: KretaError.self) { try await s.download(Csatolmany(azonosito: 78, fajlNev: "x.pdf")) }
            s.logout()
            #expect(!FileManager.default.fileExists(atPath: file.path), "logout clears downloaded files")
        }

        @Test("a message's full text is downloaded once and kept")
        func fullMessage() async throws {
            var c = Snapshot()
            c.updated = Date()
            let s = store(cache: c)
            #expect(try await s.fullMessage("p1") == "Teljes szöveg")
            #expect(try await s.fullMessage("p1") == "Teljes szöveg")
            #expect(Stub.paths() == ["/api/v1/kommunikacio/postaladaelemek/1"])
            #expect(Snapshot.load()?.inboxBodies?["1"] == "Teljes szöveg")
            #expect(try await s.fullMessage("n5") == nil, "notice-board items have their full text already")
        }

        @Test("a message's full text that can't be downloaded is an error to show, not silence")
        func fullMessageFails() async throws {
            var c = Snapshot()
            c.updated = Date()
            var fake = FakeKreta()
            fake.fail = ["uzenet"]
            let s = store(cache: c, fake)
            await #expect(throws: (any Error).self) { try await s.fullMessage("p1") }
        }
    }
}
