import SwiftUI
import UIKit

// firka's "meglepetés jegyek", kept light: new grades sit blurred at the top of the home screen,
// a tap reveals one and shows what it did to the subject average.

struct NewGradesSection: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let rows = store.newGradeRows
        let hidden = store.hiddenGrades.count
        if !rows.isEmpty {
            Section {
                ForEach(rows) { g in
                    NewGradeRow(grade: g, hidden: store.isHidden(g), note: store.revealNotes[g.uid]) { reveal(g) }
                }
            } header: {
                HStack {
                    Text(hidden == 0 ? "Új jegyek" : "\(hidden) új jegy")
                    Spacer()
                    if hidden > 1 {
                        Button("Mind felfedése") { revealAll() }
                            .font(.subheadline)
                            .textCase(nil)
                    }
                }
            }
        }
    }

    private func reveal(_ g: Ertekeles) {
        withAnimation(.snappy) { store.reveal(g) }
        RevealFeel.of([g])?.play()
    }

    /// Oldest first, slightly staggered, so each average change builds on the previous one; one buzz at the end.
    private func revealAll() {
        let all = store.hiddenGrades
        Task {
            for g in all {
                withAnimation(.snappy) { store.reveal(g) }  // skips one a sync took away meanwhile
                try? await Task.sleep(for: .milliseconds(180))
            }
            RevealFeel.of(all)?.play()
        }
    }
}

/// The haptic for revealing grades: one, however many at once.
enum RevealFeel: Equatable {
    case success, light
    static func of(_ grades: [Ertekeles]) -> RevealFeel? {
        grades.isEmpty ? nil : grades.contains { ($0.level ?? 0) >= 4 } ? .success : .light
    }

    func play() {
        switch self {
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

private struct NewGradeRow: View {
    let grade: Ertekeles
    let hidden: Bool
    let note: RevealNote?
    let onReveal: () -> Void

    private var good: Bool { (grade.level ?? 0) >= 4 }

    var body: some View {
        HStack(spacing: 12) {
            // hidden: neutral "?" so neither the number nor the color gives it away
            GradeBadge(text: hidden ? "?" : grade.display, grade: hidden ? nil : grade.level)
                .accessibilityHidden(hidden)
                // short pop when revealed; bigger for good grades
                .keyframeAnimator(initialValue: 1.0, trigger: hidden) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(good ? 1.18 : 1.05, duration: 0.12)
                        SpringKeyframe(1.0, duration: 0.3)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(grade.tantargy.name)
                    if !hidden && good {
                        Image(systemName: "sparkle")
                            .font(.footnote)
                            .foregroundStyle(.tint)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !hidden, let note {
                    Text(note.text)
                        .font(.caption)
                        .foregroundStyle(note.good ? Color.accentColor : .secondary)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
            if hidden {
                Text("Felfedés").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if hidden { onReveal() } }
        .accessibilityElement(children: hidden ? .ignore : .combine)
        .accessibilityLabel(hidden ? "Új \(grade.tantargy.name) jegy, rejtve" : "")
        .accessibilityAddTraits(hidden ? .isButton : [])
        .accessibilityAction { if hidden { onReveal() } }
    }

    private var details: String { grade.details }
}
