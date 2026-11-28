import SwiftUI

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension Lesson {
    var title: String { Renames.shared.subject((subject?.raw ?? name ?? "Óra").capitalizedFirst) }
}

extension Grade {
    var display: String {
        if value == .grade, let n = number { return "\(n)" }
        if value == .percent, let n = number { return "\(n)%" }
        return shortText ?? text ?? "–"
    }
}

extension Absence {
    var stateLabel: String {
        let kind = late ? "késés (\(lateMinutes ?? 0) perc)" : "hiányzás"
        return "\(stateShort) \(kind)"
    }
    var stateShort: String {
        switch state {
        case .excused: "Igazolt"
        case .unexcused: "Igazolatlan"
        case .pending: "Igazolandó"
        }
    }
    var stateColor: Color {
        switch state {
        case .excused: .justified
        case .unexcused: .unjustified
        case .pending: .pending
        }
    }
}

extension Color {
    // Absence states as text on a light or dark background: iOS's green and orange are too pale on white,
    // so light mode gets darker shades (dark mode keeps the system ones).
    static let justified = Color(light: 0x1B7F37, dark: 0x30D158)
    static let unjustified = Color(light: 0xC4281C, dark: 0xFF453A)
    static let pending = Color(light: 0xB25000, dark: 0xFF9F0A)
    // Timetable changes as text, same reasoning: a substitution in orange, a cancelled lesson in red.
    static let substituted = pending
    static let cancelled = unjustified
}

/// Notice-board items, teacher notes and teacher messages in one list. The id's first letter is its source
/// (KRÉTA: n notice board, f note, p inbox), which the filter and the notifications go by.
struct Message: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var author: String?
    /// The sender's role, shown after the name ("osztályfőnök").
    var authorRole: String?
    var date: Date
    var html: String
    var attachments: [Attachment] = []
    var unread = false

    var source: String { String(id.prefix(1)) }

    /// A sync's messages, source by source: a source that failed (nil) keeps its old messages, and a source
    /// counts as loaded once it has loaded (Notifier.changes takes its first list as a baseline).
    static func merge(_ fresh: [String: [Message]?], old: Snapshot?) -> (messages: [Message], sources: Set<String>) {
        var out: [Message] = [], sources = Set<String>()
        for (source, list) in fresh {
            if let list {
                out += list
                sources.insert(source)
            } else {
                out += (old?.messageList ?? []).filter { $0.source == source }
                if old?.messageSources.contains(source) == true { sources.insert(source) }
            }
        }
        return (out.sorted { $0.date > $1.date }, sources)
    }
}

extension Snapshot {
    /// Message texts are downloaded one by one while a sync may be running: keep the ones it doesn't know of.
    mutating func keepBodies(from other: Snapshot?) {
        guard let more = other?.messageBodies else { return }
        messageBodies = more.merging(messageBodies ?? [:]) { _, mine in mine }
    }

    /// The messages to show: full texts where downloaded (that counts as read; the school system isn't told),
    /// senders as the user renamed them.
    var messages: [Message] {
        messageList.map { m in
            var m = m
            if let body = messageBodies?[m.id] { m.html = body; m.unread = false }
            m.author = [m.author?.renamedTeacher, m.authorRole].compactMap { $0 }.joined(separator: ", ").nilIfEmpty
            return m
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// The messages screen's filter: which source, and a search.
enum MessageFilter: String, CaseIterable {
    case all = "Mind", inbox = "Üzenetek", notices = "Faliújság", notes = "Feljegyzések"

    func apply(_ all: [Message], search: String) -> [Message] {
        let prefix: String? = switch self { case .all: nil; case .inbox: "p"; case .notices: "n"; case .notes: "f" }
        let q = search.trimmingCharacters(in: .whitespaces)
        return all.filter { m in
            (prefix == nil || m.id.hasPrefix(prefix!))
                && (q.isEmpty || [m.title, m.author ?? "", m.html.strippingTags].contains { $0.localizedStandardContains(q) })
        }
    }
}

// MARK: - Small shared views

struct GradeBadge: View {
    let text: String
    let grade: Int?  // nil: neutral gray (text grades, no average)
    var size: CGFloat = 36
    @ScaledMetric private var scale = 1.0  // grows with the text size setting

    var body: some View {
        let size = size * scale
        Text(text)
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded).monospacedDigit())
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .foregroundStyle(grade.map(Color.onGrade) ?? .secondary)
            .frame(width: size, height: size)
            .background(grade.map(Color.grade) ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: size * 0.25))
    }
}

struct AverageBadge: View {
    let value: Double?
    var size: CGFloat = 36
    @Environment(AppStore.self) private var store

    var body: some View {
        if let value {
            GradeBadge(text: value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "hu_HU"))),
                       grade: store.rounding.grade(value), size: size)
        } else {
            GradeBadge(text: "–", grade: nil, size: size)
        }
    }
}

/// Renders KRÉTA's HTML (homework, messages) with system font and dark-mode-friendly colors.
struct HTMLText: View {
    let html: String
    @State private var text: AttributedString?
    @ScaledMetric(relativeTo: .body) private var size = 17.0  // the body text size, as the text size setting makes it

    var body: some View {
        Group {
            if let text { Text(text).textSelection(.enabled) } else { Text(html.strippingTags) }
        }
        .task(id: "\(size)\(html)") { text = Self.render(html, size: size) }
    }

    static func render(_ html: String, size: Double = 17) -> AttributedString? {
        // no images/scripts: the HTML importer would load remote resources synchronously on the main thread
        let safe = html.replacingOccurrences(of: String.codeBlocks + "|<(img|link|iframe)[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        let styled = "<style>body{font-family:-apple-system;font-size:\(size)px}</style>" + safe
        guard let ns = try? NSMutableAttributedString(
            data: Data(styled.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil) else { return nil }
        ns.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: ns.length))
        ns.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: ns.length))
        // trim trailing newlines the HTML importer adds
        while ns.string.hasSuffix("\n") { ns.deleteCharacters(in: NSRange(location: ns.length - 1, length: 1)) }
        return try? AttributedString(ns, including: \.uiKit)
    }
}

extension String {
    /// `<script>`/`<style>` blocks with their content: code, not text.
    static let codeBlocks = "<(script|style)[^>]*>[\\s\\S]*?</(script|style)\\s*>"

    /// `&eacute;`, `&#337;`, `&#x171;` → é, ő, ű, in one pass (so `&amp;lt;` stays `&lt;`); unknown names stay as they are.
    var decodingEntities: String {
        replacing(Self.entity) { m in
            let name = m.output[1].substring ?? ""
            if name.hasPrefix("#") {
                let hex = name.dropFirst().first.map { $0 == "x" || $0 == "X" } ?? false
                if let n = UInt32(name.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let u = Unicode.Scalar(n) { return String(u) }
            } else if let v = Self.namedEntities[String(name)] {
                return v
            }
            return String(m.output[0].substring ?? "")
        }
    }

    // immutable: matching doesn't change it
    nonisolated(unsafe) private static let entity = try! Regex("&(#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);")
    /// What HTML editors write in Hungarian texts, lower and upper case.
    private static let namedEntities: [String: String] = {
        var e = ["nbsp": " ", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "amp": "&", "ndash": "–", "mdash": "—",
                 "hellip": "…", "bdquo": "„", "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "raquo": "»", "laquo": "«"]
        for (k, v) in ["aacute": "á", "eacute": "é", "iacute": "í", "oacute": "ó", "uacute": "ú", "ouml": "ö", "uuml": "ü",
                       "odblac": "ő", "udblac": "ű"] {
            e[k] = v
            e[k.capitalizedFirst] = v.uppercased()
        }
        return e
    }()

    var strippingTags: String {
        replacingOccurrences(of: Self.codeBlocks, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<br\\s*/?>|</(p|li|div|h\\d)>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>|<[^>]*$", with: "", options: .regularExpression)  // also a tag cut off at the end
            .decodingEntities
            .replacingOccurrences(of: "\\s*\n\\s*", with: "\n", options: .regularExpression)  // no blank lines in previews
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
