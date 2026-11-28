import CryptoKit
import Foundation
import Testing
@testable import Firka

@Suite("Login, text, small helpers")
struct MiscTests {
    @Test("PKCE: S256 challenge of a 43-character verifier, both in the login URL")
    func pkce() {
        let p = PKCE()
        #expect(p.verifier.count == 43 && p.state.count == 22)
        #expect(p.challenge == Data(SHA256.hash(data: Data(p.verifier.utf8))).base64URL)
        let url = p.loginURL.absoluteString
        #expect(url.hasPrefix("https://idp.e-kreta.hu/Account/Login") && url.contains(p.challenge) && url.contains(Kreta.clientId))
        #expect(PKCE().verifier != p.verifier)
    }

    @Test("JWT claims, any base64 padding; garbage gives nothing")
    func jwt() {
        for claims in [#"{"kreta:institute_code":"klik000"}"#, #"{"kreta:institute_code":"klik0001"}"#, #"{"kreta:institute_code":"klik00012"}"#] {
            let token = "h." + Data(claims.utf8).base64URL + ".s"
            #expect((Kreta.jwtPayload(token)["kreta:institute_code"] as? String)?.hasPrefix("klik") == true)
        }
        #expect(Kreta.jwtPayload("nem-jwt").isEmpty && Kreta.jwtPayload("a.!!!.b").isEmpty)
    }

    @Test("HTML previews", arguments: [
        ("<p>Kedves Diákok!</p><p>Holnap</p>", "Kedves Diákok!\nHolnap"),
        ("A &amp; B &quot;C&quot; &lt;3", "A & B \"C\" <3"),
        ("Kedves Tanulók! <strong style=\"color: rgba(34, 3", "Kedves Tanulók!"),  // cut off by KRÉTA's 100-character preview
        ("sor<br>  \n\n  másik<br/>", "sor\nmásik"),
        ("<style>p { color: red }</style><p>Szia</p><SCRIPT type=\"x\">alert(1)</SCRIPT>", "Szia"),  // code isn't text
        ("H&aacute;zi &eacute;s &ouml;r&ouml;m, &Eacute;va &Uuml;", "Házi és öröm, Éva Ü"),  // editors write accents as entities
        ("&#337;sz &#x171;r &apos;x&apos; &ndash; v&eacute;ge&hellip;", "ősz űr 'x' – vége…"),
        ("&amp;lt; &unknown;", "&lt; &unknown;"),  // decoded once; unknown names stay
    ])
    func stripTags(_ html: String, _ text: String) {
        #expect(html.strippingTags == text)
    }

    @Test func cancellationIsNotAnError() {
        #expect(isCancellation(CancellationError()) && isCancellation(URLError(.cancelled)))
        #expect(!isCancellation(URLError(.timedOut)) && !isCancellation(KretaError.http(500)))
    }

    @Test("notice board items and teacher notes with the same KRÉTA id stay separate")
    func messageIds() {
        var s = Snapshot()
        s.notices = [FaliujsagElem(uid: "1", ervenyessegKezdete: .now, cim: "Faliújság")]
        s.notes = [Feljegyzes(uid: "1", cim: "Feljegyzés", datum: .now)]
        #expect(Set(s.messages.map(\.id)).count == 2)
    }

    @Test func absences() throws {
        let late: [Mulasztas] = try decode(#"[{"Uid":"1","Tantargy":\#(subjectJSON),"Datum":"2025-11-09T23:00:00Z","Tipus":{"Nev":"Keses"},"KesesPercben":7,"IgazolasAllapota":"Igazolt"},{"Uid":"2","Tantargy":\#(subjectJSON),"Datum":"2025-11-09T23:00:00Z","Tipus":{"Nev":"hianyzas"},"IgazolasAllapota":"Igazolatlan"}]"#)
        #expect(late[0].isLate && late[0].stateLabel == "Igazolt késés (7 perc)")
        #expect(!late[1].isLate && late[1].stateShort == "Igazolatlan")
    }

    // Pure check: other tests run in parallel and read the shared renames, so don't change them here.
    @Test("renames: trimmed; blank or missing means the original")
    func renames() {
        #expect(Renames.pick("  Matek ", "Matematika") == "Matek")
        #expect(Renames.pick("   ", "Kovács Anna") == "Kovács Anna")
        #expect(Renames.pick(nil, "Kovács Anna") == "Kovács Anna")
    }

    @Test func hungarianNumbers() {
        #expect(4.386.hu2 == "4,39" && 4.384.hu2 == "4,38" && 5.0.hu2 == "5,00")
    }
}

@Suite("Background refresh")
struct BackgroundTests {
    @Test("its task id follows the app's own id (APP_ID), the same in the code and in Info.plist")
    func taskID() throws {
        let permitted = try #require(Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])
        #expect(Background.id == (Bundle.main.bundleIdentifier ?? "") + ".refresh")
        #expect(permitted == [Background.id])
    }
}
