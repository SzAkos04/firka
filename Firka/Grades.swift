import Foundation

// Grade math, kept UI-free so it can be unit tested.

extension Grade {
    var isClassic: Bool { value == .grade }
    /// firka/KRÉTA rule: only weighted 1–5 grades count towards averages.
    var countsInAverage: Bool { weight != nil && isClassic && number != nil }
    var isMidYear: Bool { kind == .midYear }
    /// 1–5 for coloring; nil for text grades.
    var level: Int? {
        if isClassic, let n = number { return n }
        if value == .percent, let n = number { return n >= 90 ? 5 : n >= 75 ? 4 : n >= 60 ? 3 : n >= 50 ? 2 : 1 }
        return nil
    }
}

extension Array where Element == Grade {
    /// Weighted average; falls back to the latest classic (e.g. half-year) grade, as firka does.
    var average: Double? {
        var sum = 0.0, weights = 0.0
        var fallback: Int?
        for g in self.sorted(by: { $0.date < $1.date }) {
            if g.isClassic, let n = g.number { fallback = n }
            guard g.countsInAverage else { continue }
            let w = Double(g.weight!) / 100
            sum += Double(g.number!) * w
            weights += w
        }
        if weights > 0 { return sum / weights }
        return fallback.map(Double.init)
    }

    /// How many of these grades the average is made of ("N jegy alapján", "Jegyek száma").
    var countedInAverage: Int { filter(\.countsInAverage).count }

    /// The weighted average with some made-up 100% grades added ("mi lenne, ha…").
    func average(adding extra: [WhatIf]) -> Double? {
        guard !extra.isEmpty else { return average }
        var sum = extra.reduce(0.0) { $0 + Double($1.grade * $1.weight) / 100 }, weights = extra.reduce(0.0) { $0 + Double($1.weight) / 100 }
        for g in self where g.countsInAverage {
            let w = Double(g.weight!) / 100
            sum += Double(g.number!) * w
            weights += w
        }
        return sum / weights
    }

    /// Mean of subject averages (firka's "összesített átlag").
    var overallAverage: Double? {
        let avgs = Dictionary(grouping: filter(\.isClassic), by: \.subject.id).values.compactMap(\.average)
        return avgs.isEmpty ? nil : avgs.reduce(0, +) / Double(avgs.count)
    }

    /// Whoever gave the newest grade: the subject's teacher now.
    var teacher: String? { self.max { $0.date < $1.date }?.teacher }

    /// Running weighted average after each grade, for charts.
    var runningAverage: [(date: Date, value: Double)] {
        var sum = 0.0, w = 0.0
        var out: [(date: Date, value: Double)] = []
        for g in sorted(by: { $0.date < $1.date }) where g.countsInAverage {
            let weight = Double(g.weight!) / 100
            sum += Double(g.number!) * weight
            w += weight
            guard w > 0 else { continue }  // 0% weighted grades alone have no average
            if out.last?.date == g.date { out.removeLast() }  // one point per moment: the average after all of them
            out.append((g.date, sum / w))
        }
        return out
    }
}

/// firka's rounding thresholds: an average below `n + t[n-1]` rounds to n (n = 1…4), otherwise 5.
struct Rounding: Equatable {
    var t: [Double] = [0.5, 0.5, 0.5, 0.5]

    func grade(_ v: Double) -> Int {
        for n in 1...4 where v < Double(n) + t[n - 1] { return n }
        return 5
    }

    static func load() -> Rounding {
        Rounding(t: (1...4).map { UserDefaults.standard.object(forKey: Pref.rounding($0)) as? Double ?? 0.5 })
    }

    func save() {
        for (i, v) in t.enumerated() { UserDefaults.standard.set(v, forKey: Pref.rounding(i + 1)) }
    }
}

extension Array where Element == Grade {
    /// Mean of the subject averages rounded to whole grades: the expected report-card average.
    func reportCardAverage(_ r: Rounding) -> Double? {
        let grades = Dictionary(grouping: filter(\.isClassic), by: \.subject.id).values.compactMap(\.average).map(r.grade)
        return grades.isEmpty ? nil : Double(grades.reduce(0, +)) / Double(grades.count)
    }
}

extension Double {
    /// "4,39"
    var hu2: String { formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "hu_HU"))) }
}

/// A "Mi lenne, ha…" grade and its weight in percent.
struct WhatIf: Hashable {
    var grade: Int
    var weight = 100
    init(_ grade: Int, weight: Int = 100) { self.grade = grade; self.weight = weight }
}

/// The line shown under a surprise grade once it's revealed: what it did to the subject average.
struct RevealNote: Equatable {
    var text: String
    var good: Bool  // 4–5: shown in the accent color with a sparkle; otherwise neutral
}

extension Grade {
    /// `previous`: the subject's grades already visible before this one.
    func revealNote(previous: [Grade], rounding r: Rounding) -> RevealNote? {
        if value == .percent, let n = number {
            // percentages: their own plain mean in the subject, apart from the 1–5 average
            let before = previous.filter { $0.value == .percent }.compactMap(\.number)
            let good = (level ?? 0) >= 4
            guard !before.isEmpty else { return RevealNote(text: "Eredmény: \(n)%", good: good) }
            let pct = { (xs: [Int]) in Int((Double(xs.reduce(0, +)) / Double(xs.count)).rounded()) }
            return RevealNote(text: "Átlag \(pct(before))% → \(pct(before + [n]))%", good: good)
        }
        guard countsInAverage, let n = number else {
            if level == nil, let s = text { return RevealNote(text: s, good: false) }  // text grade
            return nil  // e.g. half-year grade without weight
        }
        let after = previous + [self]
        let counted = after.filter(\.countsInAverage)
        if n == 5, counted.count > 1, counted.allSatisfy({ $0.number == 5 }) {
            return RevealNote(text: "Hibátlan maradt: \(counted.count)/\(counted.count) ötös", good: true)
        }
        guard let a = after.average else { return nil }
        guard let b = previous.average else { return RevealNote(text: "Átlag: \(a.hu2)", good: n >= 4) }

        if n >= 4 {
            if a > b + 0.005 { return RevealNote(text: "Átlag \(b.hu2) → \(a.hu2) ▲", good: true) }
            if abs(a - b) <= 0.005 { return RevealNote(text: "Átlag \(a.hu2), tartod a szintet", good: true) }
            return RevealNote(text: "Átlag \(b.hu2) → \(a.hu2)", good: true)
        }

        // Low grade: no fuss, just how many 100% fives bring the expected grade back.
        var text = "Átlag \(b.hu2) → \(a.hu2)"
        let was = r.grade(b)
        if r.grade(a) < was, was >= 2 {
            let target = Double(was - 1) + r.t[was - 2]
            var sum = counted.reduce(0.0) { $0 + Double($1.number! * $1.weight!) / 100 }
            var weight = counted.reduce(0.0) { $0 + Double($1.weight!) / 100 }
            for k in 1...10 {
                sum += 5; weight += 1
                if sum / weight >= target {
                    text += " · \(k) ötössel újra \(was)-\(["es", "es", "as", "es", "ös"][was - 1])"
                    break
                }
            }
        }
        return RevealNote(text: text, good: false)
    }
}

// MARK: - Report card (félévi / év végi jegyek)

enum Term { case half, end }

struct ReportRow: Identifiable {
    var subject: Subject
    var half: Grade?
    var end: Grade?
    /// Expected grade for the next term without a grade yet, from the current mid-year average.
    var expected: Int?
    var id: String { subject.id }
}

extension Grade {
    var term: Term? {
        switch kind {
        case .halfYear: .half
        case .yearEnd: .end
        default: nil
        }
    }
}

extension Array where Element == Grade {
    /// One row per subject. `upcoming` is the term still without grades (first the half-year, then the year end).
    func reportCard(_ r: Rounding) -> (rows: [ReportRow], upcoming: Term?) {
        let upcoming: Term? = !contains { $0.term == .half } ? .half : !contains { $0.term == .end } ? .end : nil
        let rows = Dictionary(grouping: self, by: \.subject.id).values.map { g in
            let latest = { (t: Term) in g.filter { $0.term == t }.max { $0.date < $1.date } }
            let row = ReportRow(subject: g[0].subject, half: latest(.half), end: latest(.end))
            let missing = upcoming == .half ? row.half == nil : upcoming == .end ? row.end == nil : false
            let avg = g.filter(\.isMidYear).average
            return ReportRow(subject: row.subject, half: row.half, end: row.end,
                             expected: missing ? avg.map(r.grade) : nil)
        }
        .sorted { ($0.subject.order ?? 0, $0.subject.raw) < ($1.subject.order ?? 0, $1.subject.raw) }
        return (rows, upcoming)
    }
}

// MARK: - University (Neptun): credits instead of weights

/// A term's averages as Hungarian universities count them (51/2007. Korm. rendelet):
/// súlyozott tanulmányi átlag, kreditindex, korrigált kreditindex.
struct CreditAverages: Equatable {
    var taken = 0, completed = 0
    var average: Double?
    var creditIndex = 0.0
    var correctedCreditIndex = 0.0

    /// One grade per subject of the term, with its credits; no grade yet counts as taken, not completed.
    init(_ grades: [Grade]) {
        var points = 0
        for g in grades {
            let credit = g.credit ?? 0
            taken += credit
            guard let n = g.number, n >= 2 else { continue }  // 1 (elégtelen) is a fail
            completed += credit
            points += credit * n
        }
        average = completed > 0 ? Double(points) / Double(completed) : nil
        creditIndex = Double(points) / 30
        correctedCreditIndex = taken > 0 ? creditIndex * Double(completed) / Double(taken) : 0
    }
}
