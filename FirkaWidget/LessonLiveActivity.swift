import ActivityKit
import SwiftUI
import WidgetKit

struct LessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonActivityAttributes.self) { ctx in
            LockScreenLessons(state: ctx.state, stale: ctx.isStale)
                .padding(16)
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
        let l = state.focused
        VStack(alignment: .leading, spacing: 10) {
            if stale {
                // The headline may be outdated; the bars below are always right.
                Text("Mai órák").font(.headline)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.inLesson ? "MOST" : "KÖVETKEZŐ")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.liveAccent)
                        Text(l.subject).font(.headline).lineLimit(1)
                        Text(details(l)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Countdown(state: state)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                        Text(state.inLesson ? "vége \(l.end.time)" : "kezdés \(l.start.time)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            DayBars(lessons: state.lessons)
        }
    }

    private func details(_ l: WidgetLesson) -> String {
        [l.number.map { "\($0). óra" }, l.room, l.substituted ? "helyettesítés" : nil].compactMap { $0 }.joined(separator: " · ")
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
                            ProgressView(timerInterval: l.start...l.end, countsDown: false) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .progressViewStyle(.linear)
                            .tint(Color.liveAccent)
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

private extension Color {
    static let liveAccent = Color(light: 0x3A7A0C, dark: 0xA7DC22)
}
