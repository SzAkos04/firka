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
