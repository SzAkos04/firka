import Foundation
import Testing
@testable import Firka

/// Tests that share global state (the network stub, the keychain, the cache file, UserDefaults) run one at a time.
@Suite(.serialized) enum Global {}

/// A fake KRÉTA (and push.test, a fake of server/push): every request to *.e-kreta.hu goes to `Stub.route` instead of the internet.
/// URLSession.shared picks up registered protocol classes, so the app's code runs unchanged.
final class Stub: URLProtocol {
    /// `until`: hold the answer back (off the stub's thread, so other requests go on) until it says true, at most 3 s.
    struct Reply { var status = 200; var body = "[]"; var until: (() -> Bool)? = nil }

    nonisolated(unsafe) static var route: (URLRequest) -> Reply = { _ in Reply(status: 404, body: "") }
    nonisolated(unsafe) private static var log: [URLRequest] = []
    private static let lock = NSLock()

    static var requests: [URLRequest] { lock.withLock { log } }
    static func paths() -> [String] { requests.compactMap { $0.url?.path } }

    /// Starts a test: fresh log, the given routes, and the stub switched on.
    static func start(_ route: @escaping (URLRequest) -> Reply) {
        lock.withLock { log = [] }
        Stub.route = route
        URLProtocol.registerClass(Stub.self)
    }

    static func stop() {
        URLProtocol.unregisterClass(Stub.self)
        route = { _ in Reply(status: 404, body: "") }
    }

    override class func canInit(with r: URLRequest) -> Bool { r.url?.host?.hasSuffix("e-kreta.hu") == true || r.url?.host == "push.test" }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func stopLoading() {}

    override func startLoading() {
        var r = request
        if r.httpBody == nil, let stream = r.httpBodyStream { r.httpBody = Data(reading: stream) }
        let reply = Stub.lock.withLock { Stub.log.append(r); return Stub.route }(r)
        let answer = { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: r.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        guard let until = reply.until else { return answer() }
        DispatchQueue.global().async {
            for _ in 0..<300 where !until() { Thread.sleep(forTimeInterval: 0.01) }
            answer()
        }
    }
}

private extension Data {
    init(reading s: InputStream) {
        self.init()
        s.open()
        defer { s.close() }
        var buf = [UInt8](repeating: 0, count: 4096)
        while s.hasBytesAvailable {
            let n = s.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            append(buf, count: n)
        }
    }
}

extension URLRequest {
    var query: [String: [String]] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(grouping: items, by: \.name).mapValues { $0.compactMap(\.value) }
    }
    var form: [String: String] {
        let pairs = String(decoding: httpBody ?? Data(), as: UTF8.self).split(separator: "&").map { $0.split(separator: "=", maxSplits: 1) }
        return Dictionary(pairs.map { (String($0[0]), String($0.count > 1 ? $0[1] : "").removingPercentEncoding ?? "") }) { $1 }
    }
}

// MARK: - Accounts and responses

/// An unsigned JWT with KRÉTA's claims (the app only reads the payload).
func jwt(institute: String = "klik000000001", user: String = "diak") -> String {
    let payload = Data(#"{"kreta:institute_code":"\#(institute)","kreta:user_name":"\#(user)"}"#.utf8).base64URL
    return "eyJhbGciOiJub25lIn0.\(payload).sig"
}

func testToken(access: String = "acc1", refresh: String = "ref1", expiresIn: TimeInterval = 3600,
               institute: String = "klik000000001", user: String = "diak") -> Token {
    Token(iss: institute, username: user, accessToken: access, refreshToken: refresh,
          idToken: jwt(institute: institute, user: user), expiry: Date().addingTimeInterval(expiresIn))
}

func grantJSON(access: String, refresh: String? = "ref2", idToken: String? = nil, expiresIn: Int = 1800) -> String {
    let parts = [#""access_token":"\#(access)""#, #""expires_in":\#(expiresIn)"#, #""token_type":"Bearer""#]
        + (refresh.map { [#""refresh_token":"\#($0)""#] } ?? []) + (idToken.map { [#""id_token":"\#($0)""#] } ?? [])
    return "{" + parts.joined(separator: ",") + "}"
}

let studentJSON = #"{"Nev":"Teszt Elek","IntezmenyNev":"Teszt Gimnázium","Cimek":[],"Gondviselok":[]}"#

/// A timetable entry as KRÉTA sends it (UTC times).
func lessonJSON(_ uid: String, start: Date, cancelled: Bool = false) -> String {
    let f = ISO8601DateFormatter()
    return #"{"Uid":"\#(uid)","Datum":"\#(f.string(from: start.startOfDay))","KezdetIdopont":"\#(f.string(from: start))","VegIdopont":"\#(f.string(from: start.addingTimeInterval(2700)))","Nev":"matematika","Oraszam":1,"Tantargy":\#(subjectJSON),"Tipus":{"Nev":"TanitasiOra"},"Allapot":{"Nev":"\#(cancelled ? "Elmaradt" : "Naplozott")"}}"#
}

func inboxJSON(_ id: Int, kind: String = "BEERKEZETT", deleted: Bool = false, subject: String = "Tárgy", text: String = "Rövid",
               read: Bool = true) -> String {
    #"{"azonosito":\#(id),"isElolvasva":\#(read),"isToroltElem":\#(deleted),"tipus":{"kod":"\#(kind)"},"uzenet":{"azonosito":\#(id),"kuldesDatum":"2026-11-18T09:50:50","feladoNev":"Varga Szabolcs","targy":"\#(subject)","szoveg":"\#(text)"}}"#
}
