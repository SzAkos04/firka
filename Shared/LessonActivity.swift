import ActivityKit
import Foundation

/// Live Activity for the school day: today's lessons on the lock screen (and Dynamic Island).
struct LessonActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Today's lessons in order. The per-lesson progress bars run on their own from these dates.
        var lessons: [WidgetLesson]
        /// Index of the lesson in the headline: the one in progress, or the next one during a break.
        var focus: Int
        /// When this state was made; the start of the "until the next lesson" countdown.
        var since: Date
        /// The phone's light/dark mode when the app made this state: the lock screen gives the activity dark in both.
        var light: Bool

        var focused: WidgetLesson { lessons[focus] }
        var inLesson: Bool { focused.start <= since }
        /// After this the headline is out of date (the system then shows the activity as stale).
        var staleDate: Date { inLesson ? focused.end : focused.start }
    }

    var day: Date
}

extension LessonActivityAttributes.ContentState {
    /// nil when no lesson is left today: then there is nothing to show.
    init?(lessons: [WidgetLesson], now: Date, light: Bool = false) {
        guard let h = lessons.headline(at: now) else { return nil }
        self.init(lessons: lessons, focus: h.index, since: now, light: light)
    }

    /// The held lesson after the headline one ("Utána"), nil if it's the last today.
    var next: WidgetLesson? { lessons[(focus + 1)...].first { !$0.cancelled } }
    /// Between two lessons (not before the first held one): the room to go to is what matters.
    var inBreak: Bool { !inLesson && lessons[..<focus].contains { !$0.cancelled } }

    /// Same headline and lessons; `since` alone changing needs no update.
    func sameContent(as other: Self) -> Bool { lessons == other.lessons && focus == other.focus && light == other.light }
}
