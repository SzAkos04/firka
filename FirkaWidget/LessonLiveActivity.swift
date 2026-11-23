import ActivityKit
import SwiftUI
import WidgetKit

struct LessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonActivityAttributes.self) { ctx in
            // The lock screen hands the activity "dark" whatever the phone's mode: the app passes the real one.
            LockScreenLessons(state: ctx.state, stale: ctx.isStale)
                .padding(16)
                .environment(\.colorScheme, ctx.state.light ? .light : .dark)
                .activityBackgroundTint(Color.liveCard(light: ctx.state.light))
        } dynamicIsland: { ctx in
            let s = ctx.state, l = s.focused
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.subject).font(.headline).lineLimit(1)
                        if let room = l.room { Text(room).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !ctx.isStale { Countdown(state: s).font(.title3.monospacedDigit()) }
                }
                DynamicIslandExpandedRegion(.bottom) { DayBars(lessons: s.lessons) }
            } compactLeading: {
                Text(l.number.map { "\($0)." } ?? "•").foregroundStyle(Color.liveAccent)
            } compactTrailing: {
                if ctx.isStale {
                    Image(systemName: "calendar")
                } else {
                    Countdown(state: s).monospacedDigit().frame(maxWidth: 52)
                }
            } minimal: {
                Image(systemName: "book.closed.fill").foregroundStyle(Color.liveAccent)
            }
        }
    }
}

private struct LockScreenLessons: View {
    let state: LessonActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        if stale {
            PassiveDay(state: state)
        } else if state.inLesson {
            NowAndNext(state: state)
        } else {
            GoToRoom(state: state)
        }
    }
}

/// In a lesson: how long it lasts, and what comes after it (and where).
private struct NowAndNext: View {
    let state: LessonActivityAttributes.ContentState

    var body: some View {
        let l = state.focused
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((["MOST"] + [l.number.map { "\($0). óra" }].compactMap { $0 }).joined(separator: " · "))
                        .font(.caption2.bold()).foregroundStyle(Color.liveAccent)
                    Text(l.subject).font(.headline).lineLimit(1)
                }
                Spacer()
                Countdown(state: state)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                if let room = l.room { Label(room, systemImage: "door.left.hand.open").lineLimit(1) }
                if l.substituted { Text("helyettesítés").foregroundStyle(.orange) }
                Spacer()
                Text("vége \(l.end.time)")
            }
            .font(.caption).foregroundStyle(.secondary)
            LessonBar(lesson: l)
            Divider()
            if let n = state.next {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("UTÁNA").font(.caption2.bold()).foregroundStyle(.secondary)
                    Text(n.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let room = n.room { Text("· \(room)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer(minLength: 4)
                    Text(n.start.time).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            } else {
                Text("Ez a mai utolsó óra").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// In a break (or before the first lesson): where to go, big, and the day's bars.
private struct GoToRoom: View {
    let state: LessonActivityAttributes.ContentState

    var body: some View {
        let l = state.focused
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.inBreak ? "SZÜNET" : "KÖVETKEZŐ").font(.caption2.bold()).foregroundStyle(Color.liveAccent)
                Spacer()
                Countdown(state: state).font(.title3.weight(.semibold).monospacedDigit()).multilineTextAlignment(.trailing)
            }
            HStack(alignment: .center, spacing: 12) {
                if let room = l.room {
                    Image(systemName: "door.left.hand.open").font(.title3).foregroundStyle(.secondary)  // "terem", for any room name
                    Text(room)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(maxWidth: 170, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.subject).font(l.room == nil ? .title3.bold() : .headline).lineLimit(1)
                    Text(([l.number.map { "\($0). óra" }, "kezdés \(l.start.time)"].compactMap { $0 }
                          + (l.substituted ? ["helyettesítés"] : [])).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            DayBars(lessons: state.lessons)
        }
    }
}

/// Counts down to the end of the lesson, or to the start of the next one during a break.
private struct Countdown: View {
    let state: LessonActivityAttributes.ContentState

    var body: some View {
        let l = state.focused
        if state.inLesson {
            Text(timerInterval: l.start...l.end, countsDown: true)
        } else {
            Text(timerInterval: state.since...max(l.start, state.since), countsDown: true)
        }
    }
}

/// One thin bar per lesson; each fills itself from start to end, no app update needed.
/// When the app hasn't run since the headline went out of date: nothing that depends on "now" but the bars,
/// which fill themselves. The filling one is the lesson in progress, with its room underneath.
private struct PassiveDay: View {
    let state: LessonActivityAttributes.ContentState

    var body: some View {
        let held = state.held
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mai órák").font(.headline)
                Spacer()
                if let first = held.first, let last = held.last {
                    Text("\(first.start.time) – \(last.end.time) · \(held.count) óra")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 4) {
                ForEach(state.lessons, id: \.self) { l in
                    let dim = l.cancelled ? AnyShapeStyle(Color.red.opacity(0.8)) : AnyShapeStyle(.secondary)
                    VStack(spacing: 3) {
                        Text(l.number.map(String.init) ?? "").font(.caption2.monospacedDigit()).foregroundStyle(dim)
                        Text(l.shortSubject).font(.caption2.weight(.semibold)).strikethrough(l.cancelled)
                            .foregroundStyle(l.cancelled ? dim : AnyShapeStyle(.primary))
                        Group {
                            if l.cancelled { Capsule().fill(Color.red.opacity(0.5)) } else { LessonBar(lesson: l) }
                        }
                        .frame(height: 5)
                        Text(l.cancelled ? "elmarad" : l.room ?? "").font(.caption2).foregroundStyle(dim)
                    }
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct DayBars: View {
    let lessons: [WidgetLesson]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(lessons, id: \.self) { l in
                VStack(spacing: 3) {
                    Group {
                        if l.cancelled {
                            Capsule().fill(Color.red.opacity(0.5))  // red like a cancelled lesson in the timetable
                        } else {
                            LessonBar(lesson: l)
                        }
                    }
                    .frame(height: 5)  // same height for both, so the numbers line up
                    Text(l.number.map(String.init) ?? "")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(l.cancelled ? AnyShapeStyle(Color.red.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .strikethrough(l.cancelled)
                }
            }
        }
    }
}

/// A lesson's bar, filling itself from start to end. The system's empty track is near black on the dark card,
/// so a track of our own sits under it.
private struct LessonBar: View {
    let lesson: WidgetLesson

    var body: some View {
        ProgressView(timerInterval: lesson.start...lesson.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            .progressViewStyle(.linear)
            .tint(Color.liveAccent)
            .background(Capsule().fill(Color.liveTrack))
    }
}

