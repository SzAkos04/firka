import Foundation

// Neptun (universities), NEPTUN_PLAN.md. What BME's own web client does is followed exactly (Bearer token plus
// cookies, renewal through Account/GetNewTokens with an empty body 30 s before expiry, answers wrapped in `data`).
// Response *bodies* come from the open-source references and are NOT verified at BME yet: every type below marked
// UNVERIFIED must be checked against a real capture before a release (scripts/neptun-check.mjs, section 5 of the plan).

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

/// Neptun as a school system for the store.
final class NeptunProvider: SchoolProvider {
    let client: NeptunClient
    init(session: NeptunSession) { client = NeptunClient(session: session, saved: { $0.save() }) }

    /// The terms must load; the current term's courses and results, the calendar and the messages each keep
    /// what they had when they fail.
    func fetch(old: Snapshot?) async throws -> Snapshot {
        let terms: NeptunList<NeptunTerm> = try await client.get("TakenSubjects/Terms")
        let real = terms.items.filter { $0.value != "0" && !$0.text.hasPrefix("0") }  // "0. félév": a placeholder [ref]
        let semesters = real.enumerated().map { Semester(id: $1.value, name: $1.text, current: $0 == 0) }
        let monday = Date().startOfWeek
        async let lessons = Snapshot.soft("Calendar", nil) { [self] in try await week(monday) + week(monday.adding(days: 7)) }
        async let messages = Snapshot.soft("Messages", nil) { [client] in
            let list: NeptunList<NeptunMessage> = try await client.get("Message/GetReceivedMessages",
                query: [.init(name: "firstRow", value: "0"), .init(name: "lastRow", value: "50"), .init(name: "filterType", value: "0")])
            return list.items.map(Message.init(neptun:))
        }
        var courses = old?.courses ?? []
        if let term = real.first { courses = try await self.courses(term: term, old: old) }
        let fetchedMessages: [Message]? = try await messages
        let fetchedLessons: [Lesson]? = try await lessons
        let school = await client.session.institution.name

        let (msgs, sources) = Message.merge(["m": fetchedMessages], old: old)
        var s = Snapshot()
        s.studentName = old?.studentName ?? ""
        s.schoolName = school
        s.grades = courses.filter { $0.number != nil }
        s.courses = courses
        s.lessons = fetchedLessons ?? old?.lessons ?? []
        s.messageList = msgs
        s.messageSources = sources
        s.semesters = semesters
        s.exams = old?.exams ?? []
        s.messageBodies = old?.messageBodies
        s.university = true
        s.updated = Date()
        return s
    }

    /// The term's courses, each with its result (one request per subject, as Neptun's own pages do).
    func courses(term: NeptunTerm, old: Snapshot?) async throws -> [Grade] {
        let list: NeptunList<NeptunTakenSubject> = try await client.get("TakenSubjects", query: [
            .init(name: "request.termId", value: term.value), .init(name: "sortAndPage.firstRow", value: "0"),
            .init(name: "sortAndPage.lastRow", value: "1000"),
        ])
        // Neptun gives no date for a result: the day it first shows up here
        let seen = Dictionary(((old?.courses ?? []) + (old?.grades ?? [])).map { ($0.id, $0.date) }) { a, _ in a }
        let now = Date()
        let results = await withTaskGroup(of: (Int, NeptunSubjectDetails.Result?).self) { group in
            for (i, s) in list.items.enumerated() {
                group.addTask { [client] in
                    let d: NeptunSubjectDetails? = try? await client.get("SubjectCourse/GetSubjectDetails", query: [.init(name: "subjectId", value: s.subjectId)])
                    return (i, d?.subjectResult)
                }
            }
            var out = [Int: NeptunSubjectDetails.Result?]()
            for await (i, r) in group { out[i] = r }
            return out
        }
        return list.items.enumerated().map { i, s in
            let r = results[i] ?? nil
            let id = "\(term.value)/\(s.subjectId)"
            let date = seen[id] ?? now
            return Grade(id: id, date: date, recorded: date, subject: Subject(id: s.subjectId, raw: s.subjectName), kind: .other,
                         value: .grade, number: r?.resultValue, text: r?.resultName, credit: s.subjectCredit, mode: s.subjectCode,
                         kindText: term.text)
        }
    }

    /// Classes of a week from the calendar (UNVERIFIED field names; events without times are left out).
    func week(_ start: Date) async throws -> [Lesson] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.hu.timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.000"
        let list: NeptunList<NeptunCalendarEvent> = try await client.get("Calendar/GetCalendarEvents", query: [
            .init(name: "startDate", value: f.string(from: start)), .init(name: "endDate", value: f.string(from: start.adding(days: 7))),
            .init(name: "displayClasses", value: "true"), .init(name: "displayExams", value: "false"),
            .init(name: "displayPeriods", value: "false"), .init(name: "displayTasks", value: "false"),
            .init(name: "displayOnlineMeetings", value: "false"), .init(name: "displayOtherEvents", value: "false"),
        ])
        // only the week's own days, like KRÉTA's (a server that answers more doesn't double them)
        return list.items.compactMap(Lesson.init(neptun:)).filter { $0.start >= start && $0.start < start.adding(days: 7) }
    }
    func fullMessage(_ id: String) async throws -> String? { nil }
    func download(_ a: Attachment) async throws -> Data { throw KretaError.http(404) }
}

/// A list answer: an array, or (some endpoints) an object holding one; items that don't decode are skipped.
struct NeptunList<T: Decodable>: Decodable, @unchecked Sendable {  // decoded once, then only read
    var items: [T]

    struct AnyKey: CodingKey {
        var stringValue: String; var intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from d: Decoder) throws {
        if let list = try? d.singleValueContainer().decode([Lossy<T>].self) { items = list.compactMap(\.value); return }
        let c = try d.container(keyedBy: AnyKey.self)
        for k in c.allKeys { if let list = try? c.decode([Lossy<T>].self, forKey: k) { items = list.compactMap(\.value); return } }
        items = []
    }
}

struct NeptunTakenSubject: Decodable {
    var subjectId: String
    var subjectCode: String?
    var subjectName: String
    var subjectCredit: Int?
}

struct NeptunSubjectDetails: Decodable {
    struct Result: Decodable { var resultValue: Int?; var resultName: String?; var passed: Bool? }
    var subjectResult: Result?
}

struct NeptunMessage: Decodable {
    var messageId: String
    var subject: String?
    var sendDate: Date?
    var isNew: Bool?
}

/// UNVERIFIED beyond `classInstanceId`, `courseCode`, `courseType`, `rooms` ([ref]): the times and title are
/// candidates read from BME's bundle.
struct NeptunCalendarEvent: Decodable {
    var classInstanceId: String?
    var title: String?
    var start: Date?
    var end: Date?
    var location: String?
    var rooms: String?
    var courseCode: String?
}

extension Message {
    init(neptun m: NeptunMessage) {
        self.init(id: "m" + m.messageId, title: m.subject ?? "Üzenet", date: m.sendDate ?? .distantPast, html: "", unread: m.isNew == true)
    }
}

extension Lesson {
    init?(neptun e: NeptunCalendarEvent) {
        guard let start = e.start, let end = e.end else { return nil }
        let title = e.title ?? e.courseCode ?? "Óra"
        self.init(id: e.classInstanceId ?? "\(start.timeIntervalSince1970)-\(title)", start: start, end: end,
                  subject: Subject(id: e.courseCode ?? title, raw: title), name: title, room: e.location ?? e.rooms)
    }
}

/// Taking the session over from Neptun's own page after the user logged in there (NeptunLoginSheet).
enum NeptunLogin {
    /// `storage`: the page's sessionStorage (BME's client keeps `access_token` there); `cookies`: the web view's.
    /// Only the university's own cookies are kept.
    static func session(storage: [String: String], cookies: [HTTPCookie], institution: Institution) -> NeptunSession? {
        guard let token = storage["access_token"], !token.isEmpty, let host = institution.api.host else { return nil }
        let own = cookies.filter { c in
            let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
            return host == d || host.hasSuffix("." + d)
        }
        return NeptunSession(institution: institution, accessToken: token,
                             cookies: Dictionary(own.map { ($0.name, $0.value) }) { $1 })
    }
}
