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
