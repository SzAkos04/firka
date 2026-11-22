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

        var focused: WidgetLesson { lessons[focus] }
        var inLesson: Bool { focused.start <= since }
        /// After this the headline is out of date (the system then shows the activity as stale).
        var staleDate: Date { inLesson ? focused.end : focused.start }
    }

    var day: Date
}

extension LessonActivityAttributes.ContentState {
    /// nil when no lesson is left today: then there is nothing to show.
    init?(lessons: [WidgetLesson], now: Date) {
        guard let h = lessons.headline(at: now) else { return nil }
        self.init(lessons: lessons, focus: h.index, since: now)
    }

    /// Same headline and lessons; `since` alone changing needs no update.
    func sameContent(as other: Self) -> Bool { lessons == other.lessons && focus == other.focus }
}
