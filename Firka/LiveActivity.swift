import ActivityKit
import UIKit

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
        guard enabled, let state = LessonActivityAttributes.ContentState(lessons: lessons, now: now, light: await phoneIsLight()) else {
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        // Yesterday's activity, if the phone kept it: replace it.
        for a in running where !Calendar.hu.isDate(a.attributes.day, inSameDayAs: now) {
            await a.end(nil, dismissalPolicy: .immediate)
        }

        var staleDate = state.staleDate
        #if DEBUG
        // FIRKA_ACTIVITY_DEMO=stale: already out of date, to see the passive view without waiting for a lesson to end
        if ProcessInfo.processInfo.environment["FIRKA_ACTIVITY_DEMO"] == "stale" { staleDate = now.addingTimeInterval(-1) }
        #endif
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let a = running.first(where: { Calendar.hu.isDate($0.attributes.day, inSameDayAs: now) }) {
            if canStart, needsRestart(started: a.attributes.started, lastEnd: state.held.last?.end ?? now, now: now) {
                await a.end(nil, dismissalPolicy: .immediate)
                start(content, now: now)
            } else if !a.content.state.sameContent(as: state) {
                await a.update(content)
            }
        } else if canStart, ActivityAuthorizationInfo().areActivitiesEnabled, shouldStart(lessons, now: now) {
            start(content, now: now)
        }
    }

    private static func start(_ content: ActivityContent<LessonActivityAttributes.ContentState>, now: Date) {
        do {
            let a = try Activity.request(attributes: LessonActivityAttributes(day: now.startOfDay, started: now), content: content)
            log.info("live activity started: \(a.id, privacy: .public)")
        } catch {
            log.error("live activity start failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The phone's appearance, as the app's window sees it (the activity itself can't tell on the lock screen).
    @MainActor private static func phoneIsLight() -> Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return (scene?.traitCollection ?? UITraitCollection.current).userInterfaceStyle != .dark
    }

    /// iOS ends activities after 8 hours, so don't start long before the first held lesson.
    static func shouldStart(_ today: [WidgetLesson], now: Date) -> Bool {
        guard let first = today.first(where: { !$0.cancelled }) else { return false }
        return first.start.timeIntervalSince(now) < 2 * 3600
    }

    /// iOS ends an activity 8 hours after it started: one started early in the morning would go before the last
    /// lesson. Restart it (only the app in front can) when that keeps it longer by at least half an hour.
    static func needsRestart(started: Date?, lastEnd: Date, now: Date) -> Bool {
        guard let started else { return false }
        let cutoff = started.addingTimeInterval(8 * 3600)
        return cutoff < lastEnd && now.timeIntervalSince(started) >= 30 * 60
    }

    static func endAll() async {
        for a in Activity<LessonActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// The next moment the headline changes (a lesson starts or ends), for scheduling a background refresh.
    static func nextChange(_ all: [WidgetLesson], after now: Date = Date()) -> Date? {
        all.changeTimes(after: now).first
    }

    #if DEBUG
    /// FIRKA_ACTIVITY_DEMO=1: a fake day around "now" (2nd lesson running), to see the activity on a weekend
    /// or in the simulator. FIRKA_ACTIVITY_DEMO=break: the same day during the break before the 3rd lesson.
    /// FIRKA_ACTIVITY_DEMO=stale: the first day, already out of date (the passive view). Run it after =1:
    /// iOS starts no activity that is out of date, it only updates a running one to it.
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
