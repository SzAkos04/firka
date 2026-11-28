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
