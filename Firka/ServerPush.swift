import Foundation

/// Notifications from the owner's server (server/push, NTFY_PUSH_PLAN.md): it polls KRÉTA every few minutes and
/// sends them through ntfy, much sooner than iOS runs the background refresh. The phone only tells it the settings.
/// The address comes from Config/Local.xcconfig (PUSH_SERVER); without one none of this shows.
/// The server knows the sender from Tailscale (tailnet only), so there is no password here.
enum ServerPush {
    static var base: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "FirkaPushServer") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    /// The server sends the notifications: the phone's own ones stay off.
    static var active: Bool { base != nil && UserDefaults.standard.bool(forKey: Pref.serverPush) }

    /// The settings that shape the notifications, as server/push/poll.mjs reads them.
    struct Prefs: Codable, Equatable {
        var kinds: [String: Bool]
        var surprise: Bool
        var subjects: [String: String]
        var teachers: [String: String]
        var hidden: [HideRule]
    }

    static func current() -> Prefs {
        Prefs(kinds: Dictionary(uniqueKeysWithValues: Notifier.kinds.map { ($0.key, Notifier.enabled($0.key)) }),
              surprise: Pref.on(Pref.surpriseGrades), subjects: Renames.shared.subjects, teachers: Renames.shared.teachers,
              hidden: HiddenLessons.shared.rules)
    }

    static func upload(_ p: Prefs, to base: URL) async throws {
        var req = URLRequest(url: base.appendingPathComponent("api/prefs"), timeoutInterval: 15)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONEncoder().encode(p)
        let (_, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw KretaError.http(status) }
    }

    /// Sends the settings if the server is in charge; a failure only logs (next time the app opens it goes again).
    static func sync() async {
        guard active, let base else { return }
        do { try await upload(current(), to: base) } catch { log.error("server prefs: \(String(describing: error), privacy: .public)") }
    }

    struct Status: Decodable {
        var lastPoll: Date?
        var result: String?
        var loggedIn: Bool

        enum CodingKeys: CodingKey { case lastPoll, result, loggedIn }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            lastPoll = try c.decodeIfPresent(String.self, forKey: .lastPoll).flatMap(Kreta.parseDate)
            result = try c.decodeIfPresent(String.self, forKey: .result)
            loggedIn = try c.decode(Bool.self, forKey: .loggedIn)
        }
    }

    static func status(from base: URL) async throws -> Status {
        let (data, resp) = try await URLSession.shared.data(for: URLRequest(url: base.appendingPathComponent("api/status"), timeoutInterval: 15))
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw KretaError.http(status) }
        return try JSONDecoder().decode(Status.self, from: data)
    }
}
