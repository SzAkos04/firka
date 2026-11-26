import Foundation
import Testing
@testable import Firka

/// Notifications from the owner's server (server/push): what the phone sends it, and that the phone stays quiet then.
@Suite("Server notifications")
struct ServerPushTests {
    @Test("the settings go in the shape server/push/poll.mjs reads")
    func prefsShape() throws {
        let l = lesson("l1", day: budapest(2026, 11, 26), from: 10 * 60, number: 3)
        let p = ServerPush.Prefs(kinds: ["notifyGrades": false], surprise: true, subjects: ["Irodalom": "Iroda"], teachers: [:],
                                 hidden: [HideRule(.weekly, for: l), HideRule(.subject, for: l)])
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        #expect(Set(json.keys) == ["kinds", "surprise", "subjects", "teachers", "hidden"])
        let rules = try #require(json["hidden"] as? [[String: AnyHashable]])
        #expect(rules[0] == ["kind": "weekly", "subject": "Matematika", "weekday": 5, "slot": "3"])  // Thursday; 1 = Sunday
        #expect(rules[1] == ["kind": "subject", "subject": "Matematika"])
    }

    @Test("when the server sends the notifications, the phone sends none")
    func quietWhenTheServerSends() throws {
        var old = Snapshot(), new = Snapshot()
        old.studentName = "Teszt Elek"; new.studentName = "Teszt Elek"; old.updated = budapest(2026, 11, 26)
        new.grades = try grades(gradeJSON("a", 5, 100))
        let some = Notifier.toPost(old: old, new: new, server: false, enabled: { _ in true }, surprise: true, isHidden: { _ in false })
        #expect(!some.isEmpty)
        #expect(Notifier.toPost(old: old, new: new, server: true, enabled: { _ in true }, surprise: true, isHidden: { _ in false }).isEmpty)
    }
}

extension Global {
    @Suite("Server notifications: talking to the server", .serialized)
    final class ServerPushNetwork {
        let base = URL(string: "https://push.test:8446")!
        deinit { Stub.stop() }

        @Test("the settings are a PUT of JSON to /api/prefs; a refusal is an error")
        func upload() async throws {
            Stub.start { _ in .init(status: 204, body: "") }
            let p = ServerPush.Prefs(kinds: [:], surprise: false, subjects: [:], teachers: ["Kiss Anna": "Anna néni"], hidden: [])
            try await ServerPush.upload(p, to: base)
            let r = try #require(Stub.requests.last)
            #expect(r.httpMethod == "PUT" && r.url?.absoluteString == "https://push.test:8446/api/prefs")
            #expect(r.value(forHTTPHeaderField: "content-type") == "application/json")
            #expect(try JSONDecoder().decode(ServerPush.Prefs.self, from: try #require(r.httpBody)) == p)

            Stub.start { _ in .init(status: 403, body: "") }
            await #expect(throws: (any Error).self) { try await ServerPush.upload(p, to: self.base) }
        }

        @Test("the status: when it last asked KRÉTA, with what result, and whether it is signed in")
        func status() async throws {
            Stub.start { _ in .init(body: #"{"lastPoll":"2026-11-26T21:39:32.027Z","result":"ok","loggedIn":true}"#) }
            let s = try await ServerPush.status(from: base)
            #expect(s.lastPoll == Kreta.parseDate("2026-11-26T21:39:32.027Z") && s.result == "ok" && s.loggedIn)
            #expect(Stub.paths() == ["/api/status"])

            Stub.start { _ in .init(body: #"{"loggedIn":false}"#) }   // just started, not polled yet
            let fresh = try await ServerPush.status(from: base)
            #expect(fresh.lastPoll == nil && !fresh.loggedIn)
        }
    }
}

@Suite("Links into the app")
struct AppLinkTests {
    @Test("firka://<tab> opens that tab (the server's notifications carry one); anything else is ignored")
    func tabs() {
        #expect(AppTab(url: URL(string: "firka://grades")!) == .grades)
        #expect(AppTab(url: URL(string: "firka://timetable")!) == .timetable)
        #expect(AppTab(url: URL(string: "firka://absences")!) == .absences)
        #expect(AppTab(url: URL(string: "firka://more")!) == .more)
        #expect(AppTab(url: URL(string: "firka://home")!) == .home)
        #expect(AppTab(url: URL(string: "firka://nope")!) == nil)
        #expect(AppTab(url: URL(string: "https://grades")!) == nil)
    }
}
