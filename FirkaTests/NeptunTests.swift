import Foundation
import Testing
@testable import Firka

extension Global {
    /// Finding a university's Neptun from its web address (NEPTUN_PLAN.md, "Any university"): no login involved.
    @Suite("Neptun: finding a university", .serialized)
    final class NeptunDiscovery {
        deinit { Stub.stop() }

        /// A Neptun web at `path` on uni.neptun.test whose config file says `config`.
        func site(_ path: String = "/hallgatoi/", config: String = #"{"apiServer":{"url": "api/"}}"#, redirect: (from: String, to: String)? = nil) {
            Stub.start { r in
                let p = r.url!.path
                if let redirect, p.hasPrefix(redirect.from) { return .init(status: 301, body: "", location: redirect.to) }
                if p == path || p + "/" == path { return .init(body: "<html><title>Neptun Web</title></html>") }
                if p == path + "assets/config/config.json" { return .init(body: config) }
                return .init(status: 404, body: "")
            }
        }

        @Test("the API is the web address + apiServer.url from the public config file")
        func plain() async throws {
            site()
            let i = try await Institution.discover(web: URL(string: "https://uni.neptun.test/hallgatoi/")!, name: "Teszt Egyetem")
            #expect(i.web.absoluteString == "https://uni.neptun.test/hallgatoi/")
            #expect(i.api.absoluteString == "https://uni.neptun.test/hallgatoi/api/")
            #expect(i.name == "Teszt Egyetem")
        }

        @Test("a config with a BOM, line breaks and extra keys (Óbuda, Debrecen, Szeged write it so)")
        func tolerant() async throws {
            site(config: "\u{FEFF}{\n  \"apiServer\": {\n    \"url\": \"api/\"\n  },\n  \"apmServer\": {\"url\": \"https://x.local:8200\"}\n}")
            let i = try await Institution.discover(web: URL(string: "https://uni.neptun.test/hallgatoi")!, name: "x")
            #expect(i.api.absoluteString == "https://uni.neptun.test/hallgatoi/api/", "a missing trailing slash is added too")
        }

        @Test("a moved address is followed, and the API is taken from where it landed (Pécs: /hallgatoing/ → /hallgato/)")
        func redirect() async throws {
            site("/hallgato/", redirect: (from: "/hallgatoing", to: "/hallgato/"))
            let i = try await Institution.discover(web: URL(string: "https://uni.neptun.test/hallgatoing/")!, name: "x")
            #expect(i.web.absoluteString == "https://uni.neptun.test/hallgato/")
            #expect(i.api.absoluteString == "https://uni.neptun.test/hallgato/api/")
        }

        @Test("not a Neptun web: a clear error, before anyone types a password")
        func notNeptun() async throws {
            site(config: "<html>not json</html>")
            await #expect(throws: NeptunError.notNeptun) {
                try await Institution.discover(web: URL(string: "https://uni.neptun.test/hallgatoi/")!, name: "x")
            }
            site()
            await #expect(throws: NeptunError.notNeptun) {
                try await Institution.discover(web: URL(string: "https://uni.neptun.test/rossz/")!, name: "x")
            }
        }
    }
}

@Suite("Neptun: the list of universities")
struct InstitutionListTests {
    @Test("the bundled list (scripts/neptun-institutions.mjs) has BME with its checked address")
    func bundled() throws {
        let all = KnownInstitution.all
        #expect(all.count > 20)
        let bme = try #require(all.first { $0.omCode == "FI23344" })
        #expect(bme.name == "Budapesti Műszaki és Gazdaságtudományi Egyetem" && bme.web.absoluteString == "https://neptun.bme.hu/hallgatoi/")
    }

    @Test("search: any part of the name, any case, with or without accents; empty shows all")
    func search() {
        let all = KnownInstitution.all
        #expect(KnownInstitution.search("muszaki", in: all).map(\.omCode) == ["FI23344"])
        #expect(KnownInstitution.search("Szeged", in: all).map(\.name) == ["Szegedi Tudományegyetem"])
        #expect(KnownInstitution.search("  ", in: all).count == all.count)
    }
}

@Suite("University averages: credit-weighted, credit index, corrected credit index")
struct CreditMathTests {
    func g(_ id: String, _ grade: Int?, credit: Int) -> Grade {
        Grade(id: id, date: .now, recorded: .now, subject: Subject(id: id, raw: id), kind: .other, value: .grade, number: grade, credit: credit)
    }

    @Test("passed subjects weigh by their credits; a fail (1) and a subject without a grade don't count in the average")
    func weighted() {
        let term = [g("a", 5, credit: 6), g("b", 3, credit: 4), g("c", 1, credit: 5), g("d", nil, credit: 3)]
        let c = CreditAverages(term)
        #expect(c.taken == 18 && c.completed == 10)
        #expect(c.average == 4.2, "(5·6 + 3·4) / 10")
        #expect(c.creditIndex == 1.4, "(5·6 + 3·4) / 30")
        #expect(abs(c.correctedCreditIndex - 1.4 * 10 / 18) < 1e-9, "credit index × completed / taken credits")
    }

    @Test("nothing completed yet: no average, indexes are zero")
    func empty() {
        let c = CreditAverages([g("a", nil, credit: 5)])
        #expect(c.average == nil && c.creditIndex == 0 && c.correctedCreditIndex == 0 && c.taken == 5 && c.completed == 0)
        #expect(CreditAverages([]).correctedCreditIndex == 0)
    }
}

/// A JWT whose payload says when it expires (Neptun's access token; NeptunClient reads `exp`).
func neptunJWT(_ access: String, expires: Date) -> String {
    let payload = Data(#"{"sub":"\#(access)","exp":\#(Int(expires.timeIntervalSince1970))}"#.utf8).base64EncodedString()
        .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    return "eyJhbGciOiJIUzI1NiJ9.\(payload).sig"
}

extension Global {
    /// The Neptun client against a fake Neptun. Shapes from BME's web client and the references (NEPTUN_PLAN.md
    /// sections 2–3); the response bodies are NOT verified at BME yet.
    @Suite("Neptun: the client", .serialized)
    final class NeptunClientTests {
        let uni = Institution(name: "Teszt", web: URL(string: "https://uni.neptun.test/hallgatoi/")!,
                              api: URL(string: "https://uni.neptun.test/hallgatoi/api/")!)
        deinit { Stub.stop() }

        func session(_ access: String = "a1", expiresIn: TimeInterval = 600, cookie: String = "old") -> NeptunSession {
            NeptunSession(institution: uni, accessToken: neptunJWT(access, expires: Date().addingTimeInterval(expiresIn)),
                          cookies: ["rt": cookie])
        }
        func bearer(_ r: URLRequest) -> String? { r.value(forHTTPHeaderField: "authorization") }

        @Test("a request carries the token and the session's cookies, and the answer's `data` is unwrapped")
        func request() async throws {
            Stub.start { _ in .init(body: #"{"data":[{"value":"t1","text":"2026/27/1"}]}"#) }
            let c = NeptunClient(session: session())
            let terms: [NeptunTerm] = try await c.get("TakenSubjects/Terms")
            #expect(terms.map(\.value) == ["t1"])
            let r = try #require(Stub.requests.last)
            #expect(r.url?.absoluteString == "https://uni.neptun.test/hallgatoi/api/TakenSubjects/Terms")
            #expect(bearer(r) == "Bearer " + (await c.session.accessToken))
            #expect(r.value(forHTTPHeaderField: "cookie") == "rt=old")
        }

        @Test("a token about to expire is renewed first (Account/GetNewTokens, empty body, cookies); the new cookie is kept")
        func renewFirst() async throws {
            let fresh = neptunJWT("a2", expires: Date().addingTimeInterval(600))
            Stub.start { r in
                if r.url?.path.hasSuffix("/Account/GetNewTokens") == true {
                    return .init(body: #"{"accessToken":"\#(fresh)"}"#, headers: ["Set-Cookie": "rt=new; Path=/; HttpOnly"])
                }
                return .init(body: #"{"data":[]}"#)
            }
            let c = NeptunClient(session: session(expiresIn: 10))
            let _: [NeptunTerm] = try await c.get("TakenSubjects/Terms")
            let renew = try #require(Stub.requests.first)
            #expect(renew.httpMethod == "POST" && renew.url?.path == "/hallgatoi/api/Account/GetNewTokens")
            #expect(renew.value(forHTTPHeaderField: "cookie") == "rt=old" && String(decoding: renew.httpBody ?? Data(), as: UTF8.self) == "{}")
            #expect(bearer(try #require(Stub.requests.last)) == "Bearer " + fresh)
            #expect(Stub.requests.last?.value(forHTTPHeaderField: "cookie") == "rt=new")
            #expect(await c.session.cookies["rt"] == "new")
            #expect(await c.session.expiry > Date().addingTimeInterval(500))
        }

        @Test("a 401: renewed once and retried; a refused renewal means logging in again")
        func turnedAway() async throws {
            let fresh = neptunJWT("a2", expires: Date().addingTimeInterval(600))
            Stub.start { r in
                if r.url?.path.hasSuffix("/Account/GetNewTokens") == true { return .init(body: #"{"data":{"accessToken":"\#(fresh)"}}"#) }
                return r.value(forHTTPHeaderField: "authorization") == "Bearer " + fresh ? .init(body: #"{"data":[]}"#) : .init(status: 401, body: "")
            }
            let c = NeptunClient(session: session())
            let _: [NeptunTerm] = try await c.get("TakenSubjects/Terms")
            #expect(Stub.paths().filter { $0.hasSuffix("GetNewTokens") }.count == 1)

            Stub.start { _ in .init(status: 401, body: "") }
            await #expect(throws: KretaError.self) { let _: [NeptunTerm] = try await NeptunClient(session: self.session()).get("TakenSubjects/Terms") }
        }
    }
}

/// A Neptun of the tests' own, with the shapes the references document (UNVERIFIED at BME).
struct FakeNeptun {
    var terms = #"[{"value":"0","text":"0. félév"},{"value":"t2","text":"2026/27/1"},{"value":"t1","text":"2025/26/2"}]"#
    var subjects = #"[{"subjectId":"s1","subjectCode":"BMEVISZAA01","subjectName":"Analízis 1","subjectCredit":6,"termId":"t2"},{"subjectId":"s2","subjectCode":"BMEVIIIAA02","subjectName":"Programozás alapjai","subjectCredit":5,"termId":"t2"},{"subjectId":"s3","subjectCode":"BMETE90AX00","subjectName":"Fizika 1","subjectCredit":4,"termId":"t2"}]"#
    var results = ["s1": #"{"resultValue":4,"resultName":"Jó","passed":true}"#, "s2": #"{"resultValue":1,"resultName":"Elégtelen","passed":false}"#]
    var messages = #"[{"messageId":"1","subject":"Vizsgajelentkezés","sendDate":"2026-12-01T10:00:00","isNew":true,"senderUserId":"u9"}]"#
    /// This week's Tuesday 8:15–10:00, whatever the week (Neptun's local time, no zone).
    var calendar: String = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.hu.timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let tue = Date().startOfWeek.adding(days: 1)
        let start = f.string(from: tue.addingTimeInterval(8 * 3600 + 15 * 60)), end = f.string(from: tue.addingTimeInterval(10 * 3600))
        return #"[{"classInstanceId":"c1","title":"Analízis 1 (EA)","start":"\#(start)","end":"\#(end)","location":"K.287","courseType":"Elmélet"},{"title":"no times"}]"#
    }()
    var fail: Set<String> = []

    func reply(_ r: URLRequest) -> Stub.Reply {
        let path = r.url!.path.replacingOccurrences(of: "/hallgatoi/api/", with: "")
        let wrap = { (s: String) in Stub.Reply(body: #"{"data":\#(s)}"#) }
        if fail.contains(path) { return .init(status: 500, body: "") }
        switch path {
        case "TakenSubjects/Terms": return wrap(terms)
        case "TakenSubjects": return wrap(subjects)
        case "SubjectCourse/GetSubjectDetails":
            let id = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "subjectId" }?.value ?? ""
            return wrap(#"{"subjectResult":\#(results[id] ?? "null")}"#)
        case "Message/GetReceivedMessages": return wrap(messages)
        case "Calendar/GetCalendarEvents": return wrap(calendar)
        default: return .init(status: 404, body: "")
        }
    }
}

extension Global {
    @Suite("Neptun: from its answers to the app's models (shapes UNVERIFIED at BME)", .serialized)
    final class NeptunProviderTests {
        let uni = Institution(name: "Teszt Egyetem", web: URL(string: "https://uni.neptun.test/hallgatoi/")!,
                              api: URL(string: "https://uni.neptun.test/hallgatoi/api/")!)
        deinit { Stub.stop() }

        func provider(_ fake: FakeNeptun = FakeNeptun()) -> NeptunProvider {
            Stub.start(fake.reply)
            return NeptunProvider(session: NeptunSession(institution: uni, accessToken: neptunJWT("a", expires: Date().addingTimeInterval(600)), cookies: [:]))
        }

        @Test("semesters (without the 0. félév placeholder), the current one's courses with credits, grades where there is a result")
        func coursesAndGrades() async throws {
            let s = try await provider().fetch(old: nil)
            #expect(s.semesters.map(\.id) == ["t2", "t1"] && s.semesters.first?.current == true)
            #expect(s.courses.map(\.subject.raw) == ["Analízis 1", "Programozás alapjai", "Fizika 1"])
            #expect(s.courses.map(\.credit) == [6, 5, 4])
            #expect(s.grades.map(\.id) == ["t2/s1", "t2/s2"], "Fizika has no result yet")
            #expect(s.grades[0].number == 4 && s.grades[0].text == "Jó" && s.grades[0].credit == 6 && s.grades[0].weight == nil)
            #expect(CreditAverages(s.courses).taken == 15 && CreditAverages(s.courses).completed == 6)
            #expect(s.schoolName == "Teszt Egyetem")
        }

        @Test("a grade keeps the date it was first seen (Neptun gives none), so surprises and the chart stay in order")
        func gradeDates() async throws {
            var old = Snapshot()
            let then = Date(timeIntervalSince1970: 1_700_000_000)  // 2023: before any fetch here
            old.grades = [Grade(id: "t2/s1", date: then, recorded: then, subject: Subject(id: "s1", raw: "Analízis 1"), kind: .other, value: .grade, number: 4)]
            let s = try await provider().fetch(old: old)
            #expect(s.grades.first { $0.id == "t2/s1" }?.date == then)
            #expect(s.grades.first { $0.id == "t2/s2" }!.date > then)
        }

        @Test("messages (source m) and classes from the calendar; an event without times is left out")
        func messagesAndCalendar() async throws {
            let s = try await provider().fetch(old: nil)
            #expect(s.messageList.map(\.id) == ["m1"] && s.messageList[0].title == "Vizsgajelentkezés" && s.messageList[0].unread)
            #expect(s.messageSources == ["m"])
            #expect(s.lessons.map(\.id) == ["c1"], "once, though the fake answers every week with it")
            #expect(s.lessons[0].name == "Analízis 1 (EA)" && s.lessons[0].room == "K.287")
            #expect(s.lessons[0].end.timeIntervalSince(s.lessons[0].start) == 105 * 60)
        }

        @Test("the calendar or the messages failing keep what was there; the terms failing fails the sync")
        func soft() async throws {
            var fake = FakeNeptun()
            fake.fail = ["Calendar/GetCalendarEvents", "Message/GetReceivedMessages"]
            var old = Snapshot()
            old.lessons = [lesson("kept", day: .now, from: 600)]
            old.messageList = [Message(id: "m0", title: "régi", date: .now, html: "")]
            old.messageSources = ["m"]
            let s = try await provider(fake).fetch(old: old)
            #expect(s.lessons.map(\.id) == ["kept"] && s.messageList.map(\.id) == ["m0"])
            fake.fail = ["TakenSubjects/Terms"]
            await #expect(throws: (any Error).self) { try await self.provider(fake).fetch(old: old) }
        }
    }
}
