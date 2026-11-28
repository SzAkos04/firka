import Foundation

/// A school system the app syncs with: KRÉTA (KretaProvider) now, Neptun next. The store only talks to this.
protocol SchoolProvider: AnyObject, Sendable {
    /// Everything for the app; parts that fail keep what `old` had. Throws `KretaError.reauth` when a login is needed.
    func fetch(old: Snapshot?) async throws -> Snapshot
    /// Lessons of any week (Monday 00:00 to Sunday).
    func week(_ start: Date) async throws -> [Lesson]
    /// A message's full text, when the list gave only its start; nil when there is nothing to download.
    func fullMessage(_ id: String) async throws -> String?
    func download(_ a: Attachment) async throws -> Data
}

enum NeptunError: Error, Equatable {
    case notNeptun
}

/// A university on the new Neptun Web; `api` is found from `web` (Institution.discover).
struct Institution: Codable, Hashable {
    var name: String
    var omCode: String?
    var web: URL
    var api: URL

    /// Opens the web address (following a move), reads its public `assets/config/config.json` and takes the API
    /// address from it. Anything else than a Neptun Web there is `NeptunError.notNeptun`.
    static func discover(web: URL, name: String, omCode: String? = nil) async throws -> Institution {
        let start = web.absoluteString.hasSuffix("/") ? web : web.appendingPathComponent("")
        let (_, page) = try await URLSession.shared.data(from: start)
        guard let landed = page.url, (page as? HTTPURLResponse)?.statusCode == 200 else { throw NeptunError.notNeptun }
        let base = landed.absoluteString.hasSuffix("/") ? landed : landed.deletingLastPathComponent()
        let (data, resp) = try await URLSession.shared.data(from: base.appendingPathComponent("assets/config/config.json"))
        struct Config: Decodable { struct Server: Decodable { var url: String }; var apiServer: Server }
        // some write it with a byte order mark, which JSONDecoder refuses
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}").union(.whitespacesAndNewlines))
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let config = try? JSONDecoder().decode(Config.self, from: Data(text.utf8)),
              let api = URL(string: config.apiServer.url, relativeTo: base)?.absoluteURL else { throw NeptunError.notNeptun }
        return Institution(name: name, omCode: omCode, web: base, api: api)
    }
}

/// A university in the login's list (Firka/Institutions.json, made by scripts/neptun-institutions.mjs).
struct KnownInstitution: Codable, Hashable, Identifiable {
    var name: String
    var omCode: String?
    var web: URL
    var id: String { web.absoluteString }

    static let all: [KnownInstitution] = {
        guard let url = Bundle.main.url(forResource: "Institutions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([KnownInstitution].self, from: data)) ?? []
    }()

    static func search(_ text: String, in list: [KnownInstitution]) -> [KnownInstitution] {
        let q = text.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? list : list.filter { $0.name.localizedStandardContains(q) }
    }
}
