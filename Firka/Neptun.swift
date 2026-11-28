import Foundation

// Neptun (universities), NEPTUN_PLAN.md. What BME's own web client does is followed exactly (Bearer token plus
// cookies, renewal through Account/GetNewTokens with an empty body 30 s before expiry, answers wrapped in `data`).
// Response *bodies* come from the open-source references and are NOT verified at BME yet: every type below marked
// UNVERIFIED must be checked against a real capture before a release (scripts/neptun-check.sh, section 5 of the plan).

/// A logged-in Neptun session, kept in the Keychain. No password: the user logs in on Neptun's own page.
struct NeptunSession: Codable, Equatable {
    var institution: Institution
    var accessToken: String
    /// The cookies of the Neptun host by name (the refresh token travels in one of them).
    var cookies: [String: String]

    /// From the token's own `exp` claim (it's a JWT); a token we can't read counts as expired.
    var expiry: Date {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return .distantPast }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        struct Claims: Decodable { var exp: Double }
        guard let data = Data(base64Encoded: b64), let c = try? JSONDecoder().decode(Claims.self, from: data) else { return .distantPast }
        return Date(timeIntervalSince1970: c.exp)
    }

    var cookieHeader: String { cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ") }

    private static let account = "neptun"

    static func load() -> NeptunSession? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(NeptunSession.self, from: data)
    }

    /// In place, like Token.save: no moment without a session for another reader.
    func save() {
        let find: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: Self.account]
        let value: [String: Any] = [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                    kSecValueData as String: try! JSONEncoder().encode(self)]
        var status = SecItemUpdate(find as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(find.merging(value) { $1 } as CFDictionary, nil) }
        if status != errSecSuccess { log.error("keychain save (neptun) failed: \(status, privacy: .public)") }
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account] as CFDictionary)
    }
}

/// Neptun's API with one session: renews it before it runs out (one renewal at a time) and after a 401.
actor NeptunClient {
    private(set) var session: NeptunSession
    private var renewing: Task<NeptunSession, Error>?
    /// Where a renewed session goes (the Keychain in the app).
    private let saved: @Sendable (NeptunSession) -> Void

    init(session: NeptunSession, saved: @escaping @Sendable (NeptunSession) -> Void = { _ in }) {
        self.session = session
        self.saved = saved
    }

    /// GET `path` under the API address; the answer's `data`.
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var comps = URLComponents(url: session.institution.api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        let data = try await send(URLRequest(url: comps.url!, timeoutInterval: 30))
        return try Kreta.apiDecoder.decode(NeptunWrapped<T>.self, from: data).data
    }

    private func send(_ base: URLRequest) async throws -> Data {
        for attempt in 0..<2 {
            if attempt > 0 || session.expiry.addingTimeInterval(-30) < Date() { try await renew(after: attempt > 0 ? session : nil) }
            var r = base
            r.httpShouldHandleCookies = false  // the session's own cookies, not the shared jar's
            r.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "authorization")
            r.setValue(session.cookieHeader, forHTTPHeaderField: "cookie")
            r.setValue("application/json", forHTTPHeaderField: "accept")
            let (data, resp) = try await URLSession.shared.data(for: r)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            keepCookies(resp)
            if status == 401 { if attempt == 0 { continue }; throw KretaError.reauth }
            guard (200..<300).contains(status) else { throw KretaError.http(status) }
            return data
        }
        throw KretaError.reauth
    }

    /// `turnedAway`: the session a 401 came back for; renewed meanwhile by another request: nothing to do.
    private func renew(after turnedAway: NeptunSession?) async throws {
        if let turnedAway, turnedAway.accessToken != session.accessToken { return }
        if let renewing { session = try await renewing.value; return }
        let current = session
        let task = Task { try await Self.newTokens(current) }
        renewing = task
        defer { renewing = nil }
        session = try await task.value
        saved(session)
    }

    private static func newTokens(_ s: NeptunSession) async throws -> NeptunSession {
        var r = URLRequest(url: s.institution.api.appendingPathComponent("Account/GetNewTokens"), timeoutInterval: 30)
        r.httpMethod = "POST"
        r.httpBody = Data("{}".utf8)
        r.httpShouldHandleCookies = false
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "authorization")
        r.setValue(s.cookieHeader, forHTTPHeaderField: "cookie")
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw KretaError.reauth }  // the session is over
        // at PTE the token is at the top level, BME's client may wrap it in `data` (UNVERIFIED): take either
        struct Tokens: Decodable { var accessToken: String?; var data: Inner?; struct Inner: Decodable { var accessToken: String? } }
        guard let t = try? JSONDecoder().decode(Tokens.self, from: data), let access = t.accessToken ?? t.data?.accessToken else {
            throw KretaError.reauth
        }
        var new = s
        new.accessToken = access
        new.cookies.merge(cookies(resp, institution: s.institution)) { $1 }
        return new
    }

    private func keepCookies(_ resp: URLResponse) {
        let fresh = Self.cookies(resp, institution: session.institution)
        guard !fresh.isEmpty else { return }
        session.cookies.merge(fresh) { $1 }
        saved(session)
    }

    private static func cookies(_ resp: URLResponse, institution: Institution) -> [String: String] {
        guard let h = resp as? HTTPURLResponse, let fields = h.allHeaderFields as? [String: String] else { return [:] }
        return Dictionary(HTTPCookie.cookies(withResponseHeaderFields: fields, for: institution.api).map { ($0.name, $0.value) }) { $1 }
    }
}

/// Every answer is `{ "data": … }` (BME's client unwraps it the same way).
struct NeptunWrapped<T: Decodable>: Decodable { var data: T }

// MARK: - Response shapes (UNVERIFIED: from IdrissaMaiga/neptun-api, other universities)

/// A term in `TakenSubjects/Terms`: `value` is its id, `text` its name ("2026/27/1").
struct NeptunTerm: Decodable, Hashable {
    var value: String
    var text: String
}
