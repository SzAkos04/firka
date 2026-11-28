import Foundation
import Testing
@testable import Firka

extension Global {
    /// The KRÉTA client against a fake server: URLs, headers, errors, token renewal.
    @Suite("KRÉTA client", .serialized)
    final class Network {
        let saved = Token.load()
        init() { Token.delete() }
        deinit { Stub.stop(); Token.delete(); saved?.save() }

        @Test("requests: the student's school host, the token, KRÉTA's headers, the date range")
        func request() async throws {
            Stub.start { _ in .init(body: "[\(gradeJSON("a", 5, 100))]") }
            let c = KretaClient(token: testToken())
            let g: [Ertekeles] = try await c.list("Ertekelesek", from: budapest(2026, 11, 2), to: budapest(2026, 11, 8))
            #expect(g.map(\.uid) == ["a"])
            let r = try #require(Stub.requests.first)
            #expect(r.url?.host == "klik000000001.e-kreta.hu")
            #expect(r.url?.path == "/ellenorzo/v3/sajat/Ertekelesek")
            #expect(r.query == ["datumTol": ["2026-11-02"], "datumIg": ["2026-11-08"]])
            #expect(r.value(forHTTPHeaderField: "authorization") == "Bearer acc1")
            #expect(r.value(forHTTPHeaderField: "apiKey") == Kreta.apiKey)
            #expect(r.value(forHTTPHeaderField: "user-agent") == Kreta.userAgent)
        }

        @Test("a week asks from the day before (KRÉTA filters by UTC date) and keeps only its own days")
        func week() async throws {
            let monday = budapest(2026, 11, 23)
            Stub.start { _ in .init(body: "[" + [lessonJSON("sun", start: monday.addingTimeInterval(-3600)),
                                                  lessonJSON("mon", start: monday.addingTimeInterval(8 * 3600)),
                                                  lessonJSON("next", start: monday.adding(days: 7).addingTimeInterval(8 * 3600))]
                .joined(separator: ",") + "]") }
            let lessons = try await KretaClient(token: testToken()).week(monday)
            #expect(lessons.map(\.uid) == ["mon"])
            #expect(Stub.requests.first?.query == ["datumTol": ["2026-11-22"], "datumIg": ["2026-11-29"]])
        }

        @Test("query parameters are sent as given, also twice (class averages need that)")
        func repeatedQuery() async throws {
            Stub.start { _ in .init() }
            let q = [URLQueryItem(name: "x", value: "1"), URLQueryItem(name: "x", value: "1")]
            let _: [OsztalyAtlag] = try await KretaClient(token: testToken()).list("Ertekelesek/Atlagok/OsztalyAtlagok", query: q)
            #expect(Stub.requests.first?.query == ["x": ["1", "1"]])
        }

        @Test("server errors are errors, with the code in the Hungarian message")
        func serverError() async {
            Stub.start { _ in .init(status: 503, body: "") }
            await #expect { let _: [Ertekeles] = try await KretaClient(token: testToken()).list("Ertekelesek") } throws: {
                guard case KretaError.http(503) = $0 else { return false }
                return $0.localizedDescription.contains("503")
            }
        }

        @Test("a broken response body is an error, not an empty list")
        func garbage() async {
            Stub.start { _ in .init(body: "<html>karbantartás</html>") }
            await #expect(throws: DecodingError.self) { let _: [Ertekeles] = try await KretaClient(token: testToken()).list("Ertekelesek") }
        }

        @Test("without a school code there's no request: log in again")
        func noInstitute() async {
            Stub.start { _ in .init() }
            await #expect(throws: KretaError.self) { let _: [Ertekeles] = try await KretaClient(token: testToken(institute: "")).list("Ertekelesek") }
            #expect(Stub.requests.isEmpty)
        }

        @Test("401: renews the token once, retries, and keeps the new token")
        func renewOn401() async throws {
            let old = testToken()
            old.save()
            Stub.start { r in
                if r.url?.path == "/connect/token" { return .init(body: grantJSON(access: "acc2")) }
                return r.value(forHTTPHeaderField: "authorization") == "Bearer acc2" ? .init(body: "[]") : .init(status: 401, body: "")
            }
            let c = KretaClient(token: old)
            let _: [Ertekeles] = try await c.list("Ertekelesek")
            #expect(Stub.paths() == ["/ellenorzo/v3/sajat/Ertekelesek", "/connect/token", "/ellenorzo/v3/sajat/Ertekelesek"])
            let form = try #require(Stub.requests.first { $0.url?.path == "/connect/token" }).form
            #expect(form == ["institute_code": "klik000000001", "refresh_token": "ref1", "grant_type": "refresh_token", "client_id": Kreta.clientId])
            #expect(Token.load()?.accessToken == "acc2" && Token.load()?.refreshToken == "ref2")
            #expect(await c.token.accessToken == "acc2")
        }

        @Test("401 after a renewal too: log in again")
        func still401() async {
            testToken().save()
            Stub.start { r in r.url?.path == "/connect/token" ? .init(body: grantJSON(access: "acc2")) : .init(status: 401, body: "") }
            await #expect(throws: KretaError.self) { let _: [Ertekeles] = try await KretaClient(token: testToken()).list("Ertekelesek") }
        }

        @Test("an expired token is renewed before the request")
        func expired() async throws {
            let old = testToken(expiresIn: -10)
            old.save()
            Stub.start { r in r.url?.path == "/connect/token" ? .init(body: grantJSON(access: "acc2")) : .init() }
            let _: [Ertekeles] = try await KretaClient(token: old).list("Ertekelesek")
            #expect(Stub.paths().first == "/connect/token")
            #expect(Stub.requests.last?.value(forHTTPHeaderField: "authorization") == "Bearer acc2")
        }

        @Test("a rejected refresh token (400) means log in again")
        func refreshRejected() async {
            let old = testToken(expiresIn: -10)
            old.save()
            Stub.start { r in r.url?.path == "/connect/token" ? .init(status: 400, body: #"{"error":"invalid_grant"}"#) : .init() }
            await #expect(throws: KretaError.self) { let _: [Ertekeles] = try await KretaClient(token: old).list("Ertekelesek") }
        }

        @Test("parallel requests with an expired token renew it only once (refresh tokens are single-use)")
        func singleRenewal() async throws {
            let old = testToken(expiresIn: -10)
            old.save()
            Stub.start { r in r.url?.path == "/connect/token" ? .init(body: grantJSON(access: "acc2")) : .init() }
            let a = KretaClient(token: old), b = KretaClient(token: old)
            async let x: [Ertekeles] = a.list("Ertekelesek")
            async let y: [Ertekeles] = b.list("Mulasztasok")
            async let z: [Ertekeles] = a.list("HaziFeladatok")
            _ = try await (x, y, z)
            #expect(Stub.paths().filter { $0 == "/connect/token" }.count == 1)
        }

        @Test("two requests turned away with the same token: one renewal, even when the second 401 comes after it")
        func late401() async throws {
            testToken().save()
            let retried: @Sendable () -> Bool = { Stub.requests.contains { $0.url?.path.hasSuffix("Ertekelesek") == true && $0.value(forHTTPHeaderField: "authorization") == "Bearer acc2" } }
            Stub.start { r in
                if r.url?.path == "/connect/token" { return .init(body: grantJSON(access: "acc2")) }
                if r.value(forHTTPHeaderField: "authorization") != "Bearer acc1" { return .init(body: "[]") }
                // this 401 comes back only after the other request has renewed and retried
                return .init(status: 401, body: "", until: r.url!.path.hasSuffix("Mulasztasok") ? retried : nil)
            }
            let c = KretaClient(token: testToken())
            async let x: [Ertekeles] = c.list("Ertekelesek")
            async let y: [Ertekeles] = c.list("Mulasztasok")
            _ = try await (x, y)
            #expect(Stub.paths().filter { $0 == "/connect/token" }.count == 1)
        }

        @Test("a token renewed elsewhere (the background task) is used without another renewal")
        func renewedElsewhere() async throws {
            testToken(access: "fromBackground", refresh: "ref9").save()
            Stub.start { _ in .init() }
            let _: [Ertekeles] = try await KretaClient(token: testToken(expiresIn: -10)).list("Ertekelesek")
            #expect(Stub.paths() == ["/ellenorzo/v3/sajat/Ertekelesek"])
            #expect(Stub.requests.first?.value(forHTTPHeaderField: "authorization") == "Bearer fromBackground")
        }

        @Test("logged out while a renewal was running: the new token isn't saved back")
        func logoutDuringRenewal() async {
            Stub.start { r in
                if r.url?.path == "/connect/token" { Token.delete(); return .init(body: grantJSON(access: "acc2")) }
                return .init()
            }
            testToken(expiresIn: -10).save()
            await #expect(throws: KretaError.self) { let _: [Ertekeles] = try await KretaClient(token: testToken(expiresIn: -10)).list("Ertekelesek") }
            #expect(Token.load() == nil)
        }

        @Test("login: code exchange with PKCE, school and user from the id token")
        func login() async throws {
            Stub.start { _ in .init(body: grantJSON(access: "a", refresh: "r", idToken: jwt(institute: "klik123", user: "kisdiak"), expiresIn: 1800)) }
            let t = try await Kreta.exchange(code: "c0de", verifier: "v3r")
            let form = try #require(Stub.requests.first).form
            #expect(form["code"] == "c0de" && form["code_verifier"] == "v3r" && form["grant_type"] == "authorization_code")
            #expect(form["redirect_uri"] == "https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect" && form["client_id"] == Kreta.clientId)
            #expect(Stub.requests.first?.url?.absoluteString == "https://idp.e-kreta.hu/connect/token")
            #expect(t.iss == "klik123" && t.username == "kisdiak" && t.accessToken == "a" && t.refreshToken == "r")
            #expect(abs(t.expiry.timeIntervalSinceNow - 1740) < 5, "a minute early, to be safe")
        }

        @Test("a refresh without new id/refresh token keeps the old ones")
        func refreshKeepsOld() async throws {
            Stub.start { _ in .init(body: grantJSON(access: "new", refresh: nil)) }
            let t = try await Kreta.refresh(testToken(institute: "klik7", user: "u7"))
            #expect(t.accessToken == "new" && t.refreshToken == "ref1" && t.iss == "klik7" && t.username == "u7")
        }

        @Test("full URLs (messages, files) use the token too; a bad URL is no request")
        func fullURL() async throws {
            Stub.start { _ in .init(body: "[\(inboxJSON(1))]") }
            let c = KretaClient(token: testToken())
            let m: [PostaladaElem] = try await c.list(fullURL: "https://eugyintezes.e-kreta.hu/api/v1/kommunikacio/postaladaelemek/sajat")
            #expect(m.map(\.azonosito) == [1])
            #expect(Stub.requests.first?.value(forHTTPHeaderField: "authorization") == "Bearer acc1")
            let none: [PostaladaElem] = try await c.list(fullURL: "")
            #expect(none.isEmpty && Stub.requests.count == 1)
        }

        @Test("the keychain keeps exactly one token")
        func keychain() {
            #expect(Token.load() == nil)
            testToken(access: "x").save()
            testToken(access: "y").save()
            #expect(Token.load()?.accessToken == "y")
            Token.delete()
            #expect(Token.load() == nil)
        }

        @Test("saving a renewed token replaces it in place: a reader at the same time (the other process) never finds none")
        func keychainNoGap() async {
            testToken(access: "a").save()
            let reader = Task.detached {
                var missing = 0
                for _ in 0..<2000 where Token.load() == nil { missing += 1 }
                return missing
            }
            for i in 0..<300 { testToken(access: "t\(i)").save() }
            #expect(await reader.value == 0)
            #expect(Token.load()?.accessToken == "t299")
        }
    }
}
