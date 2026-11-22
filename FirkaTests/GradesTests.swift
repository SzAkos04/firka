import Foundation
import Testing
@testable import Firka

@Suite("Averages, rounding, report card")
struct GradesTests {
    let r = Rounding()

    @Test("weighted: 5@200% + 3@100% = 4,33; weightless and text grades don't count")
    func weighted() throws {
        let g = try grades(gradeJSON("a", 5, 200), gradeJSON("b", 3, 100), gradeJSON("c", 1, nil), gradeJSON("d", nil, 100, valueType: "Szoveges"))
        #expect(abs(g.average! - 13.0 / 3) < 0.0001)
        #expect(g.runningAverage.map(\.value) == [5, 13.0 / 3])
        #expect(g.overallAverage == g.average)
    }

    @Test("only a half-year grade: the average falls back to it, like firka")
    func fallback() throws {
        #expect(try grades(gradeJSON("h", 4, nil, kind: "felevi_jegy_ertekeles")).average == 4)
    }

    @Test("0% weight alone: no NaN in the chart, average falls back to the grade")
    func zeroWeight() throws {
        let g = try grades(gradeJSON("z", 5, 0))
        #expect(g.runningAverage.isEmpty && g.average == 5)
    }

    @Test func empty() {
        let none: [Ertekeles] = []
        #expect(none.average == nil && none.overallAverage == nil && none.runningAverage.isEmpty)
        #expect(none.average(adding: [5, 5]) == 5)
    }

    @Test("what-if grades count at 100%")
    func whatIf() throws {
        let g = try grades(gradeJSON("a", 5, 200), gradeJSON("b", 2, 100))  // 4,00
        #expect(g.average(adding: []) == g.average)
        #expect(g.average(adding: [5]) == 4.25)
        #expect(abs(g.average(adding: [1, 1])! - 14.0 / 5) < 0.0001)
    }

    @Test("overall = mean of subject averages, not of all grades")
    func overall() throws {
        let hist = gradeJSON("t1", 3, 100, subject: historyJSON)
        let g = try grades(gradeJSON("m1", 5, 100), gradeJSON("m2", 5, 100), gradeJSON("m3", 5, 100), hist)
        #expect(g.overallAverage == 4)
    }

    @Test("rounding thresholds: x,50 by default", arguments: [(1.49, 1), (1.5, 2), (2.49, 2), (3.5, 4), (4.49, 4), (4.5, 5), (5.0, 5)])
    func defaultRounding(_ v: Double, _ expected: Int) {
        #expect(r.grade(v) == expected)
    }

    @Test func strictRounding() {
        let strict = Rounding(t: [0.5, 0.5, 0.85, 0.75])
        #expect(strict.grade(3.8) == 3 && strict.grade(3.85) == 4 && strict.grade(4.7) == 4 && strict.grade(4.75) == 5)
    }

    @Test func reportCardAverage() throws {
        let g = try grades(gradeJSON("m", 5, 100), gradeJSON("t", 3, 100, subject: historyJSON))
        #expect(g.reportCardAverage(r) == 4)
    }

    @Test("report card: expected grade only in the next term without a grade")
    func reportCard() throws {
        let g = try grades(gradeJSON("h1", 4, nil, kind: "felevi_jegy_ertekeles"), gradeJSON("a1", 5, 100),
                           gradeJSON("b1", 5, 100, subject: historyJSON), gradeJSON("b2", 4, 100, subject: historyJSON))
        let card = g.reportCard(r)
        #expect(card.upcoming == .end)
        let math = card.rows.first { $0.subject.uid == "1,MAT" }!, hist = card.rows.first { $0.subject.uid == "2,TOR" }!
        #expect(math.half?.szamErtek == 4 && math.expected == 5)
        #expect(hist.half == nil && hist.expected == 5)  // 4,5 → 5
        #expect(card.rows.map(\.subject.uid) == ["1,MAT", "2,TOR"])  // KRÉTA's sort order
    }

    @Test func reportCardBeforeAnyTerm() throws {
        let card = try grades(gradeJSON("x", 3, 100)).reportCard(r)
        #expect(card.upcoming == .half && card.rows[0].expected == 3)
    }

    @Test func gradeDisplay() throws {
        let pct = try grades(gradeJSON("p", 85, 100, valueType: "Szazalekos"))[0]
        #expect(pct.display == "85%" && pct.level == 4 && !pct.countsInAverage)
        let text = try grades(gradeJSON("t", nil, nil, valueType: "Szoveges", text: "Nem írt", short: "-"))[0]
        #expect(text.display == "-" && text.level == nil)
    }
}

@Suite("Surprise grade reveal notes")
struct RevealNoteTests {
    let r = Rounding()

    @Test func badGradeSaysHowToRecover() throws {
        let g = try grades(gradeJSON("m1", 5, 200), gradeJSON("m2", 2, 100))
        let note = g[1].revealNote(previous: [g[0]], rounding: r)
        #expect(note == RevealNote(text: "Átlag 5,00 → 4,00 · 3 ötössel újra 5-ös", good: false))
    }

    @Test func goodGrades() throws {
        let m = try grades(gradeJSON("m1", 5, 200), gradeJSON("m2", 2, 100), gradeJSON("m3", 4, 100))
        #expect(m[2].revealNote(previous: Array(m[0...1]), rounding: r)?.text == "Átlag 4,00, tartod a szintet")
        #expect(m[2].revealNote(previous: [m[1]], rounding: r)?.text == "Átlag 2,00 → 3,00 ▲")
        #expect(m[0].revealNote(previous: [], rounding: r)?.text == "Átlag: 5,00")
        let fives = try grades(gradeJSON("g1", 5, 50), gradeJSON("g2", 5, 100), gradeJSON("g3", 5, 50))
        #expect(fives[2].revealNote(previous: Array(fives[0...1]), rounding: r) == RevealNote(text: "Hibátlan maradt: 3/3 ötös", good: true))
    }

    @Test("text grade shows its text; half-year grade without weight has no note")
    func noAverage() throws {
        let text = try grades(gradeJSON("t", nil, nil, valueType: "Szoveges", text: "Nem írt", short: "-"))[0]
        #expect(text.revealNote(previous: [], rounding: r)?.text == "Nem írt")
        let half = try grades(gradeJSON("h", 4, nil, kind: "felevi_jegy_ertekeles"))[0]
        #expect(half.revealNote(previous: [], rounding: r) == nil)
    }
}
