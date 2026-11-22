import Foundation
import CryptoKit
import Security
import os

let log = Logger(subsystem: "firka", category: "app")

// MARK: - API models
// Property names are the KRÉTA JSON keys with the first letter lowercased
// (see `Kreta.apiDecoder`), so "SzamErtek" -> `szamErtek`.

struct NUD: Codable, Hashable {  // KRÉTA's {Uid, Nev, Leiras} triple
    var uid: String?
    var nev: String?
    var leiras: String?
}

struct Tantargy: Codable, Hashable {
    var uid: String
    var nev: String
    var kategoria: NUD?
    var sortIndex: Int?
}

/// Grade
struct Ertekeles: Codable, Identifiable, Hashable {
    var uid: String
    var rogzitesDatuma: Date
    var keszitesDatuma: Date
    var tantargy: Tantargy
    var tema: String?
    var tipus: NUD
    var mod: NUD?
    var ertekFajta: NUD
    var ertekeloTanarNeve: String?
    var szamErtek: Int?
    var szovegesErtek: String?
    var sulySzazalekErteke: Int?
    var szovegesErtekelesRovidNev: String?
    var id: String { uid }
}

/// Timetable entry (lesson or school-calendar event)
struct Ora: Codable, Identifiable, Hashable {
    var uid: String
    var datum: Date
    var kezdetIdopont: Date
    var vegIdopont: Date
    var nev: String?
    var oraszam: Int?
    var tantargy: Tantargy?
    var tanarNeve: String?
    var helyettesTanarNeve: String?
    var teremNeve: String?
    var tema: String?
    var tipus: NUD
    var allapot: NUD?
    var tanuloJelenlet: NUD?
    var bejelentettSzamonkeresUid: String?
    var haziFeladatUid: String?
    var id: String { uid }
}

/// Absence / lateness
struct Mulasztas: Codable, Identifiable, Hashable {
    struct OraInfo: Codable, Hashable {
        var kezdoDatum: Date
        var vegDatum: Date
        var oraszam: Int?
    }
    var uid: String
    var tantargy: Tantargy
    var ora: OraInfo?
    var datum: Date
    var rogzitoTanarNeve: String?
    var tipus: NUD?
    var kesesPercben: Int?
    var igazolasAllapota: String
    var igazolasTipusa: NUD?
    var id: String { uid }
}

/// Homework
struct HaziFeladat: Codable, Identifiable, Hashable {
    var uid: String
    var tantargy: Tantargy
    var rogzitoTanarNeve: String?
    var szoveg: String?
    var feladasDatuma: Date
    var hataridoDatuma: Date
    var isMegoldva: Bool?
    var id: String { uid }
}

extension Ora {
    /// The lessons starting in [from, to): drops the extra day asked for around a week.
    static func keep(_ items: [Ora], from: Date, to: Date) -> [Ora] {
        items.filter { $0.kezdetIdopont >= from && $0.kezdetIdopont < to }
    }
}

/// Announced test
struct Szamonkeres: Codable, Identifiable, Hashable {
    var uid: String
    var datum: Date
    var bejelentesDatuma: Date
    var rogzitoTanarNeve: String?
    var orarendiOraOraszama: Int?
    var tantargy: Tantargy
    var temaja: String?
    var modja: NUD?
    var id: String { uid }
}

/// Notice board item
struct FaliujsagElem: Codable, Identifiable, Hashable {
    var uid: String
    var rogzitoNeve: String?
    var ervenyessegKezdete: Date
    var cim: String?
    var tartalom: String?
    var id: String { uid }
}

/// Teacher's note
struct Feljegyzes: Codable, Identifiable, Hashable {
    var uid: String
    var cim: String?
    var datum: Date
    var keszitoTanarNeve: String?
    var tartalom: String?
    var tartalomFormazott: String?
    var tipus: NUD?
    var id: String { uid }
}

/// Class group; its "OktatasNevelesiFeladat" uid is needed for class averages.
struct OsztalyCsoport: Decodable {
    var oktatasNevelesiFeladat: NUD?
    var isAktiv: Bool?
}

/// Per-subject class average
struct OsztalyAtlag: Decodable {
    var tantargy: Tantargy
    var osztalyCsoportAtlag: Double?
}

/// Teacher message from the KRÉTA messaging service (eugyintezes.e-kreta.hu), "postaláda".
struct PostaladaElem: Codable, Identifiable, Hashable {
    struct Uzenet: Codable, Hashable {
        var azonosito: Int
        var kuldesDatum: Date
        var feladoNev: String?
        var feladoTitulus: String?
        var targy: String?
        var szoveg: String?
        var csatolmanyok: [Csatolmany]?
    }
    struct Tipus: Codable, Hashable { var kod: String? }

    var azonosito: Int
    var isToroltElem: Bool?
    var tipus: Tipus?
    var uzenet: Uzenet
    var id: String { "p\(azonosito)" }
}

struct Csatolmany: Codable, Hashable, Identifiable {
    var azonosito: Int
    var fajlNev: String
    var id: Int { azonosito }

    var downloadURL: URL { URL(string: "https://eugyintezes.e-kreta.hu/api/v1/dokumentumok/uzenetek/\(azonosito)")! }
}

struct TanuloAdatlap: Codable {
    var nev: String
    var intezmenyNev: String?
}

// MARK: - Token + keychain

struct Token: Codable {
    var iss: String          // institute code, e.g. "klik012345001"
    var username: String
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var expiry: Date

    private static let account = "kreta-token"

    static func load() -> Token? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Token.self, from: data)
    }

    func save() {
        Token.delete()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: Token.account,
                                // background refresh runs while the phone is locked
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                kSecValueData as String: try! JSONEncoder().encode(self)]
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess { log.error("keychain save failed: \(status, privacy: .public)") }
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}

// MARK: - Auth (OAuth2 + PKCE against idp.e-kreta.hu, same as the official app)

struct PKCE {
    let verifier: String
    let challenge: String
    let state: String

    init() {
        verifier = PKCE.random(32)
        challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        state = PKCE.random(16)
    }

    private static func random(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return Data(bytes).base64URL
    }

    var loginURL: URL {
        let s = "\(Kreta.idp)/Account/Login?ReturnUrl=%2Fconnect%2Fauthorize%2Fcallback%3Fredirect_uri%3Dhttps%253A%252F%252Fmobil.e-kreta.hu%252Fellenorzo-student%252Fprod%252Foauthredirect%26client_id%3D\(Kreta.clientId)%26response_type%3Dcode%26prompt%3Dlogin%26state%3D\(state)%26nonce%3D\(state)%26scope%3Dopenid%2520email%2520offline_access%2520kreta-ellenorzo-webapi.public%2520kreta-eugyintezes-webapi.public%2520kreta-fileservice-webapi.public%2520kreta-mobile-global-webapi.public%2520kreta-dkt-webapi.public%2520kreta-ier-webapi.public%26code_challenge%3D\(challenge)%26code_challenge_method%3DS256%26suppressed_prompt%3Dlogin"
        return URL(string: s)!
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// A request stopped because the screen that asked for it went away (paging, switching tabs): not an error.
func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
}

enum KretaError: LocalizedError {
    case reauth
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .reauth: "Lejárt a bejelentkezés, jelentkezz be újra."
        case .http(let code): "A KRÉTA szerver hibát adott (\(code))."
        }
    }
}

enum Kreta {
    static let idp = "https://idp.e-kreta.hu"
    static let clientId = "kreta-ellenorzo-student-mobile-ios"
    static let redirectPath = "/ellenorzo-student/prod/oauthredirect"
    static let userAgent = "eKretaStudent/264745 CFNetwork/1494.0.7 Darwin/23.4.0"
    static let apiKey = "21ff6c25-d1da-4a68-a811-c881a6057463"

    // Formatters are expensive to create; these are thread-safe for parsing.
    private static let iso = ISO8601DateFormatter()
    private static let isoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let localFormats: [DateFormatter] = ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"].map {
        let f = DateFormatter()  // no zone: local time, like Dart's DateTime.parse
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    /// KRÉTA sends ISO-8601 with or without fractional seconds / timezone.
    static func parseDate(_ s: String) -> Date? {
        if let d = iso.date(from: s) ?? isoFraction.date(from: s) { return d }
        for f in localFormats { if let d = f.date(from: s) { return d } }
        return nil
    }

    static let apiDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .custom { keys in
            let k = keys.last!.stringValue
            return AnyKey(k.prefix(1).lowercased() + k.dropFirst())
        }
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            guard let date = parseDate(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Bad date \(s)"))
            }
            return date
        }
        return d
    }()

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    // MARK: token endpoint

    static func exchange(code: String, verifier: String) async throws -> Token {
        try await tokenRequest([
            "code": code, "code_verifier": verifier,
            "redirect_uri": "https://mobil.e-kreta.hu" + redirectPath,
            "client_id": clientId, "grant_type": "authorization_code",
        ], old: nil)
    }

    static func refresh(_ t: Token) async throws -> Token {
        try await tokenRequest([
            "institute_code": t.iss, "refresh_token": t.refreshToken,
            "grant_type": "refresh_token", "client_id": clientId,
        ], old: t)
    }

    private static func tokenRequest(_ form: [String: String], old: Token?) async throws -> Token {
        var req = URLRequest(url: URL(string: "\(idp)/connect/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "content-type")
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }
            .joined(separator: "&").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400 || status == 401 { throw KretaError.reauth }  // invalid/expired grant
        guard status == 200 else { throw KretaError.http(status) }

        struct Grant: Decodable {
            var id_token: String?
            var access_token: String
            var refresh_token: String?
            var expires_in: Double
        }
        let g = try JSONDecoder().decode(Grant.self, from: data)
        let idToken = g.id_token ?? old?.idToken ?? ""
        let claims = jwtPayload(idToken)
        return Token(
            iss: claims["kreta:institute_code"] as? String ?? old?.iss ?? "",
            username: claims["kreta:user_name"] as? String ?? old?.username ?? "",
            accessToken: g.access_token,
            refreshToken: g.refresh_token ?? old?.refreshToken ?? "",
            idToken: idToken,
            expiry: Date().addingTimeInterval(g.expires_in - 60))
    }

    static func jwtPayload(_ jwt: String) -> [String: Any] {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return [:] }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }
}

// MARK: - API client

/// One token renewal at a time for the whole app, foreground and background task alike.
/// KRÉTA's refresh tokens are single-use: two parallel renewals with the same one would log the user out.
actor TokenRefresher {
    static let shared = TokenRefresher()
    private var running: Task<Token, Error>?

    func fresh(_ token: Token, force: Bool) async throws -> Token {
        if let running { return try await running.value }
        // The keychain is the source of truth: another client (e.g. the background task) may have renewed it already.
        let current = Token.load() ?? token
        if current.accessToken != token.accessToken, current.expiry > Date() { return current }
        if !force, current.expiry > Date() { return current }
        let task = Task { try await Kreta.refresh(current) }
        running = task
        defer { running = nil }
        let new = try await task.value
        guard Token.load() != nil else { throw KretaError.reauth }  // logged out meanwhile: don't resurrect the token
        new.save()
        return new
    }
}

/// Decodes one element, or nil if it's malformed, so one odd item doesn't wipe a whole list.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

actor KretaClient {
    private(set) var token: Token

    init(token: Token) { self.token = token }

    private func freshToken(force: Bool = false) async throws -> Token {
        if !force && token.expiry > Date() { return token }
        token = try await TokenRefresher.shared.fresh(token, force: force)
        return token
    }

    /// Like `list`, for a full URL (the messaging service lives on another host).
    func list<T: Decodable>(fullURL: String) async throws -> [T] {
        guard let url = URL(string: fullURL) else { return [] }
        let items = try Kreta.apiDecoder.decode([Lossy<T>].self, from: try await raw(url, timeout: 30))
        return items.compactMap(\.value)
    }

    /// One Monday–Sunday week of the timetable. KRÉTA filters `datumTol` by the UTC date, so an all-day
    /// event at local midnight on Monday (23:00 UTC on Sunday) would fall out of every week: ask from the
    /// day before and keep the week's own (local) days.
    func week(_ start: Date) async throws -> [Ora] {
        let cal = Calendar(identifier: .gregorian)
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        let items: [Ora] = try await list("OrarendElemek", from: cal.date(byAdding: .day, value: -1, to: start)!,
                                          to: cal.date(byAdding: .day, value: 6, to: start)!)
        return Ora.keep(items, from: start, to: end)
    }

    /// A list endpoint; malformed items are skipped (and logged) instead of failing the request.
    func list<T: Decodable>(_ path: String, from: Date? = nil, to: Date? = nil, query: [URLQueryItem] = []) async throws -> [T] {
        let items: [Lossy<T>] = try await get(path, from: from, to: to, query: query)
        let ok = items.compactMap(\.value)
        if ok.count < items.count { log.error("\(path, privacy: .public): skipped \(items.count - ok.count, privacy: .public) malformed items") }
        return ok
    }

    func get<T: Decodable>(_ path: String, from: Date? = nil, to: Date? = nil, query: [URLQueryItem] = []) async throws -> T {
        guard !token.iss.isEmpty, var comps = URLComponents(string: "https://\(token.iss).e-kreta.hu/ellenorzo/v3/sajat/\(path)") else {
            throw KretaError.reauth
        }
        var items = query
        if let from { items.append(.init(name: "datumTol", value: Self.isoDay.string(from: from))) }
        if let to { items.append(.init(name: "datumIg", value: Self.isoDay.string(from: to))) }
        if !items.isEmpty { comps.queryItems = items }
        guard let url = comps.url else { throw KretaError.reauth }
        let data = try await raw(url)
        do {
            return try Kreta.apiDecoder.decode(T.self, from: data)
        } catch {
            log.error("\(path, privacy: .public): decode failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Any KRÉTA URL with the user's token (also the messaging service and file downloads).
    func raw(_ url: URL, timeout: TimeInterval = 20) async throws -> Data {
        for attempt in 0..<2 {
            let t = try await freshToken(force: attempt > 0)
            var req = URLRequest(url: url, timeoutInterval: timeout)
            req.setValue("*/*", forHTTPHeaderField: "accept")
            req.setValue(Kreta.userAgent, forHTTPHeaderField: "user-agent")
            req.setValue("Bearer \(t.accessToken)", forHTTPHeaderField: "authorization")
            req.setValue(Kreta.apiKey, forHTTPHeaderField: "apiKey")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                if attempt == 0 { continue }  // token revoked early: refresh once and retry
                throw KretaError.reauth
            }
            guard (200..<300).contains(status) else {
                log.error("\(url.path, privacy: .public): HTTP \(status)")
                throw KretaError.http(status)
            }
            return data
        }
        throw KretaError.reauth
    }

    var institute: String { token.iss }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
