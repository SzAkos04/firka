import Foundation

// Downloading from KRÉTA and turning it into the app's models (KretaMapping.swift).

extension Snapshot {
    /// Downloads everything from KRÉTA in parallel. Student, grades and timetable must succeed;
    /// the rest fall back to `old` so one flaky endpoint doesn't block the whole refresh.
    static func fetch(_ c: KretaClient, old: Snapshot?) async throws -> Snapshot {
        let now = Date()
        let week = now.startOfWeek
        let sept1 = Calendar.hu.date(from: DateComponents(year: Calendar.hu.component(.year, from: now), month: 9, day: 1))!
        let schoolStart = sept1 > now ? Calendar.hu.date(byAdding: .year, value: -1, to: sept1)! : sept1

        async let student: TanuloAdatlap = c.get("TanuloAdatlap")
        async let grades: [Ertekeles] = c.list("Ertekelesek")
        async let w1 = c.week(week)
        async let w2 = c.week(week.adding(days: 7))
        async let absences = soft("Mulasztasok", nil) { try await (c.list("Mulasztasok") as [Mulasztas]).map(Absence.init(kreta:)) }
        async let homework = soft("HaziFeladatok", nil) {
            try await (c.list("HaziFeladatok", from: schoolStart) as [HaziFeladat]).map(Homework.init(kreta:))
        }
        async let tests = soft("BejelentettSzamonkeresek", nil) {
            try await (c.list("BejelentettSzamonkeresek") as [Szamonkeres]).map(AnnouncedTest.init(kreta:))
        }
        // messages: nil when a source fails, so it keeps what it had (Message.merge)
        async let notices = soft("FaliujsagElemek", nil) { try await (c.list("FaliujsagElemek") as [FaliujsagElem]).map(Message.init(kreta:)) }
        async let notes = soft("Feljegyzesek", nil) { try await (c.list("Feljegyzesek") as [Feljegyzes]).map(Message.init(kreta:)) }
        async let inbox = soft("postaladaelemek", nil) {
            let all: [PostaladaElem] = try await c.list(fullURL: "https://eugyintezes.e-kreta.hu/api/v1/kommunikacio/postaladaelemek/sajat")
            return all.filter { $0.tipus?.kod == "BEERKEZETT" && $0.isToroltElem != true }.map(Message.init(kreta:))
        }
        async let classAvg = classAverages(c)

        let s = try await student
        let (messages, sources) = try await Message.merge(["n": notices, "f": notes, "p": inbox], old: old)
        return try await Snapshot(studentName: s.nev, schoolName: s.intezmenyNev, grades: grades.map(Grade.init(kreta:)),
                                  lessons: (w1 + w2).map(Lesson.init(kreta:)), absences: absences ?? old?.absences ?? [],
                                  homework: homework ?? old?.homework ?? [], tests: tests ?? old?.tests ?? [],
                                  messageList: messages, messageSources: sources,
                                  classAverages: classAvg ?? old?.classAverages,  // keep the last known ones on failure
                                  messageBodies: old?.messageBodies, updated: now)
    }

    static func soft<T>(_ name: String, _ fallback: T, _ op: () async throws -> T) async throws -> T {
        do {
            return try await op()
        } catch KretaError.reauth {
            throw KretaError.reauth
        } catch where isCancellation(error) {
            throw CancellationError()
        } catch {
            log.error("\(name, privacy: .public) failed, keeping cached: \(String(describing: error), privacy: .public)")
            return fallback
        }
    }

    /// Optional extra: a failure here (or a school that hides class averages) must not fail the sync.
    static func classAverages(_ c: KretaClient) async -> [String: Double]? {
        do {
            let groups: [OsztalyCsoport] = try await c.get("OsztalyCsoportok")
            let tasks = Set(groups.filter { $0.isAktiv != false }
                .compactMap { $0.oktatasNevelesiFeladat?.uid?.split(separator: ",").first.map(String.init) })
            var result: [String: Double] = [:]
            for t in tasks {
                // the parameter is sent twice, like firka (and the official app) do
                let q = [URLQueryItem(name: "oktatasiNevelesiFeladatUid", value: t), URLQueryItem(name: "oktatasiNevelesiFeladatUid", value: t)]
                let avgs: [OsztalyAtlag] = try await c.list("Ertekelesek/Atlagok/OsztalyAtlagok", query: q)
                for a in avgs { if let v = a.osztalyCsoportAtlag, v > 0 { result[a.tantargy.uid] = v } }
            }
            log.info("class averages: \(result.count, privacy: .public) subjects from \(tasks.count, privacy: .public) groups")
            return result
        } catch {
            log.error("class averages failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
