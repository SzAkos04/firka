import WidgetKit
import SwiftUI

struct Entry: TimelineEntry {
    let date: Date
    let current: WidgetLesson?
    let upcoming: [WidgetLesson]  // later lessons on the same day as the first one shown
}

struct Provider: TimelineProvider {
    private func lessons() -> [WidgetLesson] {
        guard let data = try? Data(contentsOf: Shared.widgetFile) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode([WidgetLesson].self, from: data)) ?? []
    }

    private func entry(at now: Date, _ all: [WidgetLesson]) -> Entry {
        guard let h = all.headline(at: now) else { return Entry(date: now, current: nil, upcoming: []) }
        let first = all[h.index]
        let later = all[(h.index + 1)...].filter { !$0.cancelled && $0.start > now && $0.start.startOfDay == first.start.startOfDay }
        return Entry(date: now, current: h.inProgress ? first : nil, upcoming: h.inProgress ? later : [first] + later)
    }

    func placeholder(in context: Context) -> Entry {
        let s = Date()
        return Entry(date: s, current: WidgetLesson(subject: "Matematika", room: "112", start: s, end: s.addingTimeInterval(2700), number: 2, cancelled: false, substituted: false),
                     upcoming: [WidgetLesson(subject: "Történelem", room: "204", start: s.addingTimeInterval(3300), end: s.addingTimeInterval(6000), number: 3, cancelled: false, substituted: false)])
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let all = lessons()
        completion(all.isEmpty ? placeholder(in: context) : entry(at: Date(), all))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let all = lessons()
        let now = Date()
        // A new entry at every lesson start/end so the widget flips without the app running.
        let changes = Set(all.flatMap { [$0.start, $0.end] }).filter { $0 > now }.sorted().prefix(40)
        let entries = [entry(at: now, all)] + changes.map { entry(at: $0, all) }
        completion(Timeline(entries: entries, policy: .after(changes.last ?? now.addingTimeInterval(3600 * 6))))
    }
}

struct FirkaWidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    private var main: WidgetLesson? { entry.current ?? entry.upcoming.first }
    private var later: [WidgetLesson] { entry.current == nil ? Array(entry.upcoming.dropFirst()) : entry.upcoming }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let m = main { Text("\(m.start.time) \(m.subject)") } else { Text("Nincs több óra") }
        case .accessoryRectangular:
            if let m = main {
                VStack(alignment: .leading) {
                    Text(entry.current != nil ? "Most" : m.start.hu("EEEE HH:mm")).font(.caption2)
                    Text(m.subject).font(.headline).widgetAccentable()
                    Text([m.room, "\(m.start.time)–\(m.end.time)"].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                }
            } else { Text("Nincs több óra") }
        default:
            if let m = main {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.current != nil ? "MOST" : m.start.startOfDay == entry.date.startOfDay ? "KÖVETKEZŐ" : m.start.hu("EEEE").uppercased())
                        .font(.caption2.bold()).foregroundStyle(Color(light: 0x3A7A0C, dark: 0xA7DC22))  // same sage as the app accent
                    Text(m.subject).font(.headline).lineLimit(2)
                        .foregroundStyle(m.substituted ? .orange : .primary)
                    Text([m.room, "\(m.start.time)–\(m.end.time)"].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if entry.current != nil {
                        Text(timerInterval: m.start...m.end, countsDown: true).font(.caption.monospacedDigit())
                    }
                    if family != .systemSmall || entry.current == nil {
                        Divider()
                        ForEach(later.prefix(family == .systemSmall ? 1 : family == .systemMedium ? 2 : 6), id: \.self) { l in
                            HStack {
                                Text(l.number.map { "\($0)." } ?? "").frame(width: 20, alignment: .leading)
                                Text(l.subject).lineLimit(1)
                                Spacer()
                                Text(l.start.time).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack {
                    Image(systemName: "sun.max.fill").font(.title).foregroundStyle(.yellow)
                    Text("Nincs több óra").font(.caption)
                }
            }
        }
    }
}

@main
struct FirkaWidgets: WidgetBundle {
    var body: some Widget {
        FirkaWidget()
        LessonLiveActivity()
    }
}

struct FirkaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FirkaNextLesson", provider: Provider()) { entry in
            FirkaWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Következő óra")
        .description("A mostani és a következő óráid.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}
