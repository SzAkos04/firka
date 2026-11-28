import Observation
import SwiftUI

/// The user's own names for subjects and teachers, keyed by the name KRÉTA sends.
/// Observable, so every screen that shows a name updates as soon as one is changed.
@Observable
final class Renames {
    // changed from the UI (main thread); the background task only reads it while the UI is away
    nonisolated(unsafe) static let shared = Renames()

    var subjects: [String: String] { didSet { UserDefaults.standard.set(subjects, forKey: Pref.renameSubjects) } }
    var teachers: [String: String] { didSet { UserDefaults.standard.set(teachers, forKey: Pref.renameTeachers) } }

    private init() {
        subjects = UserDefaults.standard.dictionary(forKey: Pref.renameSubjects) as? [String: String] ?? [:]
        teachers = UserDefaults.standard.dictionary(forKey: Pref.renameTeachers) as? [String: String] ?? [:]
    }

    func subject(_ original: String) -> String { Self.pick(subjects[original], original) }
    func teacher(_ original: String) -> String { Self.pick(teachers[original], original) }

    /// A blank custom name means "use the original".
    static func pick(_ custom: String?, _ original: String) -> String {
        let c = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return c.isEmpty ? original : c
    }
}

extension Tantargy {
    /// The subject name to show: the user's own, or KRÉTA's with a capital first letter.
    var name: String { Renames.shared.subject(nev.capitalizedFirst) }
}

extension String {
    /// A teacher's name as the user renamed it.
    var renamedTeacher: String { Renames.shared.teacher(self) }
}

/// Settings › Átnevezés: every subject and teacher from the cached data, with a field for an own name.
struct RenameView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""

    var body: some View {
        @Bindable var r = Renames.shared
        let (subjects, teachers) = Renames.names(in: store.data)
        Form {
            Section {
                ForEach(filtered(subjects), id: \.self) { s in RenameRow(original: s, custom: $r.subjects[s]) }
            } header: {
                Text("Tantárgyak")
            } footer: {
                Text("Az új név mindenhol megjelenik: órarend, jegyek, widget, értesítések. Üresen hagyva a KRÉTA-beli név marad.")
            }
            Section("Tanárok") {
                ForEach(filtered(teachers), id: \.self) { t in RenameRow(original: t, custom: $r.teachers[t]) }
            }
        }
        .searchable(text: $search, prompt: "Keresés")
        .navigationTitle("Átnevezés")
        // the widget and the Live Activity get their lesson names from the saved data
        .onDisappear { store.lessonsChanged() }
    }

    private func filtered(_ names: [String]) -> [String] {
        names.filter { Renames.matches($0, search: search, custom: Renames.shared.subjects[$0] ?? Renames.shared.teachers[$0]) }
    }
}

private struct RenameRow: View {
    let original: String
    @Binding var custom: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(original).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(original, text: Binding(get: { custom ?? "" }, set: { custom = $0.isEmpty ? nil : $0 }))
                    .autocorrectionDisabled()
                if custom != nil {
                    Button { custom = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Eredeti név visszaállítása")
                }
            }
        }
    }
}
