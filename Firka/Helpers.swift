import SwiftUI

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension Ora {
    var isCancelled: Bool { (allapot?.nev ?? "").lowercased().contains("elmarad") || tipus.nev == "UresOra" }
    var title: String { Renames.shared.subject((tantargy?.nev ?? nev ?? "Óra").capitalizedFirst) }
}

extension Ertekeles {

    var display: String {
        if isClassic, let n = szamErtek { return "\(n)" }
        if ertekFajta.nev == "Szazalekos", let n = szamErtek { return "\(n)%" }
        return szovegesErtekelesRovidNev ?? szovegesErtek ?? "–"
    }

}


extension Mulasztas {
    var isLate: Bool { tipus?.nev?.lowercased() == "keses" || (kesesPercben ?? 0) > 0 }
    var stateLabel: String {
        let kind = isLate ? "késés (\(kesesPercben ?? 0) perc)" : "hiányzás"
        switch igazolasAllapota {
        case "Igazolt": return "Igazolt \(kind)"
        case "Igazolatlan": return "Igazolatlan \(kind)"
        default: return "Igazolandó \(kind)"
        }
    }
    var stateShort: String {
        switch igazolasAllapota {
        case "Igazolt": "Igazolt"
        case "Igazolatlan": "Igazolatlan"
        default: "Igazolandó"
        }
    }
    var stateColor: Color {
        switch igazolasAllapota {
        case "Igazolt": .justified
        case "Igazolatlan": .unjustified
        default: .pending
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

/// Notice-board items and teacher notes shown in one list.
struct Message: Identifiable, Hashable {
    var id: String
    var title: String
    var author: String?
    var date: Date
    var html: String
    var attachments: [Csatolmany] = []
    var unread = false
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

extension Snapshot {
    var messages: [Message] {
        (notices.map { Message(id: "n" + $0.uid, title: $0.cim ?? "Üzenet", author: $0.rogzitoNeve?.renamedTeacher, date: $0.ervenyessegKezdete, html: $0.tartalom ?? "") }
         + notes.map { Message(id: "f" + $0.uid, title: $0.cim ?? $0.tipus?.leiras ?? "Feljegyzés", author: $0.keszitoTanarNeve?.renamedTeacher, date: $0.datum, html: $0.tartalomFormazott ?? $0.tartalom ?? "") }
         + (inbox ?? []).map { p in
             let u = p.uzenet
             return Message(id: p.id, title: u.targy ?? "Üzenet",
                            author: [u.feladoNev?.renamedTeacher, u.feladoTitulus].compactMap { $0 }.joined(separator: ", "),
                            date: u.kuldesDatum, html: inboxBodies?[String(p.azonosito)] ?? u.szoveg ?? "",
                            attachments: u.csatolmanyok ?? [],
                            // opening it here downloads the full text: that counts as read (KRÉTA isn't told)
                            unread: p.isElolvasva == false && inboxBodies?[String(p.azonosito)] == nil)
         })
            .sorted { $0.date > $1.date }
    }
}

// MARK: - Small shared views

struct GradeBadge: View {
    let text: String
    let grade: Int?  // nil: neutral gray (text grades, no average)
    var size: CGFloat = 36

    var body: some View {
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

    var body: some View {
        Group {
            if let text { Text(text).textSelection(.enabled) } else { Text(html.strippingTags) }
        }
        .task(id: html) { text = Self.render(html) }
    }

    static func render(_ html: String) -> AttributedString? {
        // no images/scripts: the HTML importer would load remote resources synchronously on the main thread
        let safe = html.replacingOccurrences(of: String.codeBlocks + "|<(img|link|iframe)[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        let styled = "<style>body{font-family:-apple-system;font-size:17px}</style>" + safe
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

    private static let entity = try! Regex("&(#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);")
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
