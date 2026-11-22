#if DEBUG
import Foundation

// FIRKA_PROBE=1: saves raw KRÉTA responses into the app's Documents/probe folder, to look at real payloads.
enum DebugProbe {
    static func run(_ c: KretaClient) async {
        let iss = await c.institute
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("probe")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let e = "https://\(iss).e-kreta.hu/ellenorzo/v3/sajat/"
        let u = "https://eugyintezes.e-kreta.hu/api/v1/kommunikacio/postaladaelemek/"
        let probes = [
            ("hazi", e + "HaziFeladatok?datumTol=2025-09-01"),
            ("faliujsag", e + "FaliujsagElemek"),
            ("feljegyzes", e + "Feljegyzesek"),
            ("orarend", e + "OrarendElemek?datumTol=2025-11-10&datumIg=2025-11-21"),
            ("postalada_beerkezett", u + "beerkezett"),
            ("postalada_sajat", u + "sajat"),
            ("att_a.pdf", "https://eugyintezes.e-kreta.hu/api/v1/dokumentumok/uzenetek/98472557"),
            ("att_b.pdf", "https://eugyintezes.e-kreta.hu/api/v1/dokumentumok/uzenetek/98472557?fileName=x"),
            ("att_c.pdf", "https://eugyintezes.e-kreta.hu/api/v1/kommunikacio/csatolmanyok/98472557"),
            ("uzenet_detail", "https://eugyintezes.e-kreta.hu/api/v1/kommunikacio/postaladaelemek/334594519"),
        ]
        for (name, s) in probes {
            do {
                let d = try await c.raw(URL(string: s)!)
                try d.write(to: dir.appendingPathComponent(name + ".json"))
                log.info("probe \(name, privacy: .public): \(d.count, privacy: .public) bytes")
            } catch {
                log.info("probe \(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
#endif
