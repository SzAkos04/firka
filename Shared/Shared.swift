import SwiftUI

// Shared between the app and the widget extension.

enum Shared {
    // "group.$(APP_ID)", set in Config/*-Info.plist and the entitlements.
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "FirkaAppGroup") as? String ?? ""

    static let containerURL: URL = {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return url
        }
        // No App Group (e.g. signing without it): the widget won't see data, the app still works.
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var widgetFile: URL { containerURL.appendingPathComponent("widget.json") }
}

/// What the widget needs about a lesson; written by the app after every refresh.
struct WidgetLesson: Codable, Hashable {
    var subject: String
    var room: String?
    var start: Date
    var end: Date
    var number: Int?
    var cancelled: Bool
    var substituted: Bool
}

extension Array where Element == WidgetLesson {
    /// The lesson to headline at `now`: the one in progress, else the next one. Cancelled lessons are skipped.
    func headline(at now: Date) -> (index: Int, inProgress: Bool)? {
        guard let i = firstIndex(where: { !$0.cancelled && $0.end > now }) else { return nil }
        return (i, self[i].start <= now)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Light-mode / dark-mode pair.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }

    // "Firka-élénk": fresh green, lime, yellow, orange, coral with dark numbers.
    // [grade: (background light, dark, text light, dark)]
    private static let palette: [Int: (UInt32, UInt32, UInt32, UInt32)] = [
        5: (0x8FD07A, 0x3B7A3A, 0x113D0D, 0xD2F5C8),
        4: (0xC9E66E, 0x5E7420, 0x33450A, 0xEAF8B8),
        3: (0xF7D24F, 0x7A6418, 0x4A3800, 0xFFEBA0),
        2: (0xF7AA60, 0x7A4620, 0x5A2606, 0xFFD2AE),
        1: (0xF28A82, 0x7A302C, 0x5C0F0A, 0xFFC4BE),
    ]

    /// The logo's background green, for the main call-to-action (same in both modes, white text like the logo).
    static let firkaLogo = Color(hex: 0x7CA120)

    /// Badge background for a 1–5 grade.
    static func grade(_ value: Int) -> Color {
        let p = palette[min(max(value, 1), 5)]!
        return Color(light: p.0, dark: p.1)
    }

    /// Text on top of `grade(_:)`, and the grade's "ink" color elsewhere (e.g. charts).
    static func onGrade(_ value: Int) -> Color {
        let p = palette[min(max(value, 1), 5)]!
        return Color(light: p.2, dark: p.3)
    }
}

extension Calendar {
    /// Hungarian calendar: weeks start on Monday.
    static let hu: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "hu_HU")
        c.firstWeekday = 2
        return c
    }()
}

extension Date {
    /// Formats with a Hungarian template, e.g. "MMMd" -> "nov. 21."
    func hu(_ template: String) -> String { HUFormat.formatter(template).string(from: self) }

    var time: String { hu("HH:mm") }
    var startOfDay: Date { Calendar.hu.startOfDay(for: self) }
    var startOfWeek: Date { Calendar.hu.dateInterval(of: .weekOfYear, for: self)!.start }
    var startOfMonth: Date { Calendar.hu.dateInterval(of: .month, for: self)!.start }
    func adding(days: Int) -> Date { Calendar.hu.date(byAdding: .day, value: days, to: self)! }
}

/// One DateFormatter per template; creating them is slow and `hu` runs in every list row.
private enum HUFormat {
    private static let lock = NSLock()
    private static var cache: [String: DateFormatter] = [:]

    static func formatter(_ template: String) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let f = cache[template] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.timeZone = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate(template)
        cache[template] = f
        return f
    }
}
