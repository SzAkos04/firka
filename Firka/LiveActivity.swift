import ActivityKit
import Foundation

/// Keeps today's lesson Live Activity in step with the timetable. Cheap to call often:
/// it only talks to ActivityKit when the headline lesson changes.
enum LessonLive {
    static var enabled: Bool { Pref.on(Pref.liveActivity) }

    /// - canStart: iOS only lets an app start an activity while it's in the foreground.
    static func sync(_ all: [WidgetLesson], now: Date = Date(), canStart: Bool) async {
        var lessons = all.filter { Calendar.hu.isDate($0.start, inSameDayAs: now) }
        #if DEBUG
        if ProcessInfo.processInfo.environment["FIRKA_ACTIVITY_DEMO"] != nil { lessons = demoDay(now) }
        #endif
        let running = Activity<LessonActivityAttributes>.activities

        // Nothing left today (or switched off): end what's running.
        guard enabled, let state = LessonActivityAttributes.ContentState(lessons: lessons, now: now) else {
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        // Yesterday's activity, if the phone kept it: replace it.
        for a in running where !Calendar.hu.isDate(a.attributes.day, inSameDayAs: now) {
            await a.end(nil, dismissalPolicy: .immediate)
        }

        let content = ActivityContent(state: state, staleDate: state.staleDate)
        if let a = running.first(where: { Calendar.hu.isDate($0.attributes.day, inSameDayAs: now) }) {
            if !a.content.state.sameContent(as: state) { await a.update(content) }
        } else if canStart, ActivityAuthorizationInfo().areActivitiesEnabled,
                  // iOS ends activities after 8 hours, so don't start long before the first lesson
                  let first = lessons.first(where: { !$0.cancelled }), first.start.timeIntervalSince(now) < 2 * 3600 {
            do {
                let a = try Activity.request(attributes: LessonActivityAttributes(day: now.startOfDay), content: content)
                log.info("live activity started: \(a.id, privacy: .public)")
            } catch {
                log.error("live activity start failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    static func endAll() async {
        for a in Activity<LessonActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// The next moment the headline changes (a lesson starts or ends), for scheduling a background refresh.
    static func nextChange(_ all: [WidgetLesson], after now: Date = Date()) -> Date? {
        all.flatMap { [$0.start, $0.end] }.filter { $0 > now }.min()
    }

    #if DEBUG
    /// FIRKA_ACTIVITY_DEMO=1: a fake day around "now" (2nd lesson running), to see the activity on a weekend
    /// or in the simulator. FIRKA_ACTIVITY_DEMO=break: the same day during the break before the 3rd lesson.
    private static func demoDay(_ now: Date) -> [WidgetLesson] {
        let inBreak = ProcessInfo.processInfo.environment["FIRKA_ACTIVITY_DEMO"] == "break"
        let s = now.addingTimeInterval(inBreak ? -47 * 60 : -20 * 60)
        return [("Történelem", "21"), ("Matematika", "21"), ("Német 2", "7"), ("Testnevelés", "Tornaterem 2.")]
            .enumerated().map { i, x in
                let start = s.addingTimeInterval(Double(i - 1) * 55 * 60)
                return WidgetLesson(subject: x.0, room: x.1, start: start, end: start.addingTimeInterval(45 * 60),
                                    number: i + 1, cancelled: i == 3, substituted: false)
            }
    }
    #endif
}
