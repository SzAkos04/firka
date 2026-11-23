import SwiftUI

/// Swipe left / long-press on a lesson row: hide it (asking for which scope), or show a hidden one again.
struct HideLessonActions: ViewModifier {
    let lesson: Ora
    @Environment(AppStore.self) private var store
    @State private var asking = false

    func body(content: Content) -> some View {
        let hidden = HiddenLessons.shared.isHidden(lesson)
        content
            .swipeActions(edge: .trailing) {
                if hidden {
                    Button { set { HiddenLessons.shared.unhide(lesson) } } label: { Label("Visszaállítás", systemImage: "eye") }
                        .tint(.accentColor)
                } else {
                    Button { asking = true } label: { Label("Elrejtés", systemImage: "eye.slash") }
                        .tint(.gray)
                }
            }
            .contextMenu {
                if hidden {
                    Button { set { HiddenLessons.shared.unhide(lesson) } } label: { Label("Visszaállítás", systemImage: "eye") }
                } else {
                    Button { asking = true } label: { Label("Elrejtés…", systemImage: "eye.slash") }
                }
            }
            .hideLessonDialog(lesson, isPresented: $asking)
    }

    /// Change the rules, then refresh what's built from them outside the app.
    private func set(_ change: () -> Void) {
        withAnimation { change() }
        store.lessonsChanged()
    }
}

extension View {
    func hideLessonActions(_ lesson: Ora) -> some View { modifier(HideLessonActions(lesson: lesson)) }
    func hideLessonDialog(_ lesson: Ora, isPresented: Binding<Bool>) -> some View {
        modifier(HideLessonDialog(lesson: lesson, isPresented: isPresented))
    }
}

/// "Which lessons?" sheet shared by the row actions and the lesson detail button.
struct HideLessonDialog: ViewModifier {
    let lesson: Ora
    @Binding var isPresented: Bool
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        content.confirmationDialog("\(lesson.title) elrejtése", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Csak ez az óra (\(lesson.kezdetIdopont.hu("MMMd")))") { apply { HiddenLessons.shared.hide(.once, lesson) } }
            Button("Minden héten: \(lesson.kezdetIdopont.hu("EEEE")) \(lesson.oraszam.map { "\($0). óra" } ?? lesson.kezdetIdopont.time)") {
                apply { HiddenLessons.shared.hide(.weekly, lesson) }
            }
            Button("A tantárgy összes órája") { apply { HiddenLessons.shared.hide(.subject, lesson) } }
            Button("Mégse", role: .cancel) {}
        } message: {
            Text("Az órát a KRÉTA továbbra is mutatja, de a Firka elrejti az órarendből, a kezdőlapról, a widgetből és az értesítésekből.")
        }
    }

    private func apply(_ change: () -> Void) {
        withAnimation { change() }
        store.lessonsChanged()
    }
}

/// Button on the lesson detail screen.
struct HideLessonButton: View {
    let lesson: Ora
    @Environment(AppStore.self) private var store
    @State private var asking = false

    var body: some View {
        if HiddenLessons.shared.isHidden(lesson) {
            Button("Óra visszaállítása az órarendbe") {
                withAnimation { HiddenLessons.shared.unhide(lesson) }
                store.lessonsChanged()
            }
        } else {
            Button("Óra elrejtése…") { asking = true }
                .hideLessonDialog(lesson, isPresented: $asking)
        }
    }
}

/// "N elrejtett óra · Mutasd" under a day's lessons.
struct HiddenFooter: View {
    let count: Int
    @Binding var showing: Bool

    var body: some View {
        if count > 0 {
            Button { withAnimation { showing.toggle() } } label: {
                (Text("\(count) elrejtett óra · ").foregroundStyle(.secondary)
                 + Text(showing ? "Bezárás" : "Mutasd").foregroundStyle(.tint))
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
    }
}

/// Settings › Elrejtett órák: every rule, removable.
struct HiddenLessonsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let h = HiddenLessons.shared
        List {
            ForEach(h.rules) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Renames.shared.subject(r.subject))
                    Text(r.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onDelete { i in
                h.rules.remove(atOffsets: i)
                store.lessonsChanged()
            }
        }
        .overlay {
            if h.rules.isEmpty {
                ContentUnavailableView("Nincs elrejtett óra", systemImage: "eye",
                                       description: Text("Az órarendben egy órát balra húzva elrejtheted, ha a valóságban nincs megtartva."))
            }
        }
        .navigationTitle("Elrejtett órák")
        .toolbar { if !h.rules.isEmpty { EditButton() } }
    }
}
