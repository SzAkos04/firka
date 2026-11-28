# Neptun in Firka: research and design (Phase 1)

Goal: keep using Firka at university with full KRÉTA support kept. Any university on the new Neptun Web can be
chosen; BME (`neptun.bme.hu/hallgatoi/`) is the one verified first, because that is where real payloads come from.
Status: research done, **waiting for review**. Nothing here is implemented. Every Neptun response field below is
marked by how we know it; nothing that is only guessed may reach a decoder before a real BME payload confirms it.

Confidence marks used below:

- **[BME]** read from BME's own production web client (`neptun.bme.hu/hallgatoi/main-*.js` and its lazy chunks,
  downloaded 2026-11-28) or its public `assets/config/config.json`.
- **[ref]** from the open-source references (other universities' Neptun, same vendor software), not seen at BME.
- **[?]** unknown: must be captured from a real BME login first (section 5).

## 0. The Firka in daily use stays untouched

The owner uses today's KRÉTA Firka every day and stays in secondary school for about a year, so nothing of this may
reach the phone or slow the KRÉTA app down, and no university data exists to test with until then.

- **The `ios` branch and `~/Projects/firka-ios` never get university work.** The launchd job builds whatever is
  checked out there at 9:00 and 19:00 (`scripts/install-renew-schedule.sh` → `renew-on-iphone.sh`, which builds from
  its own folder), so switching that folder to another branch would put a half-done build on the phone.
- University work, if started before university, lives on a **`neptun` branch in its own worktree**
  (`~/Projects/firka-neptun`), is built only for the simulator and never installed on the phone. `ios` is merged into
  it now and then so it doesn't drift; it is merged back into `ios` only when the owner says so (at the start of
  university, after testing on real data).
- Nothing in the KRÉTA path changes on `ios` until then: no refactor, no new cache format, no new settings.
- BME can change its client within a year: before any real use, `scripts/neptun-check.sh` (no login) re-reads the
  public config and bundle and lists which of the endpoints in section 3 are still there.

## 1. What BME runs

- `https://neptun.bme.hu/hallgatoi/` is the new Angular "Neptun Web" (HWEB) **[BME]**: `<base href="/hallgatoi/">`,
  title "Neptun Web", bundles `main-*.js` + ~155 lazy chunks.
- The API base comes from `assets/config/config.json` = `{"apiServer":{"url":"api/"}}` **[BME]**, so the API is
  **`https://neptun.bme.hu/hallgatoi/api/`**. (IdrissaMaiga/neptun-api's README suggests `/ujhallgato/api/` for BME:
  that is wrong or outdated.)
- Every endpoint answers `{ "data": … }` and the client unwraps `.data` **[BME]** (`.pipe(map(t => t.data))`).
- The old mobile API (`MobileService.svc`, documented by GreGamingHUN/Neptun-API and RuzsaGergely/Poszeidon) sends
  the password in every request and is marked deprecated by its own author since the 2024 facelift: **not usable**.

### Any university, not only BME

The new Neptun Web is the same vendor software everywhere; only the address differs, and each instance tells its API
address in the same public file. Checked 2026-11-28 (public files only, no login):

| University | Web address | `assets/config/config.json` |
|---|---|---|
| BME | `neptun.bme.hu/hallgatoi/` | `{"apiServer":{"url":"api/"}}` |
| Óbudai Egyetem | `neptun.uni-obuda.hu/ujhallgato/` | the same (with a UTF-8 BOM) |
| Debreceni Egyetem | `www-h-ng.neptun.unideb.hu/hallgato_ng/` | the same (BOM, pretty-printed) |
| Szegedi Tudományegyetem | `neptun.szte.hu/hallgato/` | the same, plus an internal `apmServer` entry to ignore |
| Pécsi Tudományegyetem | `neptun-web3.tr.pte.hu/hallgatoing/` → redirects to `…/hallgato/` | the same, after the redirect |
| ELTE, Corvinus | the guessed paths were wrong | to find |

So Firka needs only the web address: follow redirects, read `<address>assets/config/config.json` (tolerating a BOM
and extra keys), and the API is `<address>` + `apiServer.url`. A wrong address fails there, before any login.

Where the addresses come from: GreGamingHUN/Neptun-API's `Institutes.json` lists **56 institutions** with name,
OM code and their old mobile URL (`…/hallgatoi/MobileService.svc` for BME, `…/Hallgatoi/MobileService.svc` for
Corvinus …). Dropping `MobileService.svc` gives a **candidate** web address; candidates are only offered after the
config check passes (a build-time script checks them all and keeps the working ones), and anything missing can be
typed in by hand.

What differs between universities and can't be checked from outside: whether they ask for a second factor or a
captcha, which modules they switched off (some answer 403, per neptun-api's README), and how they fill the calendar.
Firka handles a 403 module as "not available here" instead of an error. Payloads are verified only at BME; other
universities are best effort until someone from there sends a capture.

## 2. Login, 2FA and the session

What the BME client does **[BME]** (chunk with `AuthenticateEndpoint`):

| Step | Request | Notes |
|---|---|---|
| Log in | `POST api/Account/Authenticate`, JSON = the login form + `LCID` (1038 = Hungarian) | Field names of the form: `userName`, `password` **[ref]**; 2FA code in `token` **[ref]** |
| Second factor | same request again with the code | Debrecen answers the first try with **HTTP 202** + `isTwoFactorRequired: true` **[ref]**; captcha flag `isCaptchaRequired` **[ref]**; an enum value `TokenRegistrationRequired = 256` exists in BME's bundle **[BME]** |
| Result | `data.accessToken` (JWT), `data.sessionTimeoutInMinutes`, `data.neptunCode` | `sessionTimeoutInMinutes` is read by BME's client **[BME]**; `refreshToken` also in the body at PTE **[ref]** |
| Every call | `Authorization: Bearer <access>` **and** `withCredentials: true` (cookies) | **[BME]** |
| Renewal | `POST api/Account/GetNewTokens` with body `{}` and cookies, 30 s before `access_token_expiration_date` | **[BME]**: the empty body means the refresh token travels as a **cookie** (likely HttpOnly) **[?]** |
| Storage in the browser | `sessionStorage`: `access_token`, `access_token_expiration_date`, `refresh_token` | **[BME]** |

Access tokens live about **10 minutes** (PTE, 2024) **[ref]**. A user script that kept renewing them forever
reports that "the loophole was noticed and fixed" **[ref]**: there is probably an absolute session limit
after which `GetNewTokens` fails and a full login (with 2FA) is needed. **How long that is at BME is the key
unknown [?].** BME's client also listens for a "logout alert" push and an idle timer.

### How Firka would log in (no password stored)

Like the KRÉTA login: Neptun's own login page in a `WKWebView` (non-persistent store), so the user types the
password, solves a captcha and enters the authenticator code on Neptun's page, never in Firka. After the redirect to
the dashboard Firka takes:

- the access token and its expiry from the page's `sessionStorage` (`evaluateJavaScript`), and
- the cookies of the university's Neptun host from `WKHTTPCookieStore` (HttpOnly cookies are readable there),

saves them in the Keychain (like `Token` today) and from then on calls `api/` itself with `URLSession`, renewing
through `GetNewTokens` with the saved cookies, one renewal at a time (the `TokenRefresher` pattern). When renewal
fails, the app asks to log in again, exactly like `KretaError.reauth` today. Firka never sees or keeps the password
or the TOTP secret.

### Background refresh and server push

- **iOS background refresh**: works only while the session can still be renewed. If BME's absolute limit is
  hours, background refreshes overnight will find a dead session and the app will ask for a login (with 2FA) every
  morning. Measured in section 5 before we promise anything.
- **`server/push` for Neptun: not realistic** unless the refresh cookie turns out to last days. The only way around
  a short session is keeping the password and the TOTP secret on the server and logging in unattended (what
  neptun-api's `totp_secret` does). That puts both factors on one machine and defeats 2FA: I recommend against it.
  Recommendation: Neptun accounts use phone-only notifications; the server keeps doing KRÉTA.

## 3. Endpoints for what Firka shows

All exist in BME's bundle **[BME]**; parameters from the bundle or the references; **response fields [?] unless noted**.

| Firka needs | Endpoint (under `api/`) | Parameters | Known response fields |
|---|---|---|---|
| Profile, trainings | `MyTrainings`, `Account/GetUserInfo` (name per bundle) | – | `studentTrainingId`, `code`, `faculty`, `enrolmentYear` **[ref]** |
| Semesters | `TakenSubjects/Terms` | – | list of `{value, text}`; `[0]` may be a "0. félév" placeholder **[ref]** |
| Courses + credits | `TakenSubjects` | `request.termId`, `sortAndPage.firstRow/lastRow` | `subjectId`, `subjectCode`, `subjectName`, `subjectCredit`, `requirementType`, `termId` **[ref]** |
| Grade of a subject | `SubjectCourse/GetSubjectDetails` | `subjectId` | `subjectResult.{resultValue, resultName, passed}` **[ref]**; one request per subject |
| Averages, credit index | `Advancement/GetTermAveragesByTraining`, `Dashboard/GetAverages` | – | `termAveragesByTrainings[].{average, creditIndex}` **[ref]** |
| Timetable (+ exams, deadlines) | `Calendar/GetCalendarEvents` | `startDate`, `endDate` (`yyyy-MM-ddTHH:mm:ss.000`), `displayClasses/Exams/Periods/Tasks/OnlineMeetings/OtherEvents`, `studentTrainingIds[i]` **[ref]** | `classInstanceId`, `courseCode`, `courseType`, `rooms` **[ref]**; **start, end, title: [?]** (candidate names in the bundle: `start`, `end`, `title`, `location`, `lecturers`, `allDay`, `type`) |
| Registered exams | `ExamRegisteredExams/GetRegisteredExamsList` | `sortAndPage.firstRow/lastRow` | [?] |
| Exam results | `ExamResults/GetTermsForGetExamResultsList`, `ExamResults/GetExamResultsList` | `termId` | [?] |
| Messages | `Message/GetReceivedMessages`; unread count `Message/GetUnreadedMessagesCount` | `firstRow`, `lastRow`, `filterType` | `messageId`, `subject`, `sendDate`, `isNew`, `senderUserId` **[ref]** |
| A message's text | `Messages/{id}/Posts` | `messageId` | [?] |

Notes: a full sync is ~1 + terms + (subjects of the current term) requests because grades come per subject; keep
it to the current semester plus a cached history, and sync no more often than KRÉTA (5 minutes in front).

## 4. Architecture: one app, two providers

### What changes

Today `Snapshot` stores KRÉTA's DTOs (`Ertekeles`, `Ora`, `Mulasztas`, …, ~150 references in 12 files) and every
screen, the widget, the Live Activity, `Notifier.changes`, `HiddenLessons`, `Renames` and the surprise grades read
them directly.

### Domain models (provider-neutral, in `Firka/Domain.swift`)

```swift
enum AccountKind: Codable, Hashable { case kreta, neptun(Institution) }
struct Institution: Codable, Hashable { var name: String; var omCode: String?; var web: URL; var api: URL }  // api from config.json

struct Subject: Codable, Hashable { var id: String; var name: String; var code: String? }
struct Lesson: Codable, Identifiable, Hashable {        // KRÉTA Ora, Neptun class event
    var id: String; var subject: Subject?; var title: String; var start: Date; var end: Date
    var number: Int?; var room: String?; var teacher: String?; var substitute: String?
    var cancelled: Bool; var isEvent: Bool; var topic: String?; var testID: String?; var homeworkID: String?
}
struct Grade: Codable, Identifiable, Hashable {         // KRÉTA Ertekeles, Neptun subject result
    enum Weight: Codable, Hashable { case percent(Int), credit(Int) }
    var id: String; var subject: Subject; var date: Date; var recorded: Date; var value: Int?; var text: String?
    var percent: Int?; var weight: Weight?; var kind: Kind; var teacher: String?; var topic: String?; var mode: String?
    enum Kind: Codable, Hashable { case midYear, halfYear, yearEnd, final /* Neptun: end-of-term grade */ }
}
struct Exam: Codable, Identifiable, Hashable { var id: String; var subject: Subject; var start: Date; var room: String?; var kind: String?; var registered: Bool; var result: Int? }
struct Absence …, Homework …, Test … (KRÉTA only; empty for Neptun)
struct Message: …  // already neutral (Helpers.swift), gains `source`
struct Semester: Codable, Hashable { var id: String; var name: String; var current: Bool }
```

`Snapshot` becomes `{ kind, studentName, schoolName, lessons, grades, absences, homework, tests, exams, messages,
semesters, currentSemester, classAverages, updated }` and is saved as `snapshot-v2.json`: on the first launch after
the update the old file is dropped and one sync fills the new one (it's a cache; the first sync after it sends no
alerts, as today). Grade ids stay KRÉTA's uids, so "seen" surprise grades survive.

### Providers

```swift
protocol SchoolProvider: Sendable {
    var kind: AccountKind { get }
    func fetch(old: Snapshot?) async throws -> Snapshot      // throws ProviderError.reauth when a login is needed
    func week(_ start: Date) async throws -> [Lesson]
    func fullMessage(_ id: String) async throws -> String?
    func download(_ attachment: Attachment) async throws -> URL
}
```

- `KretaProvider`: today's `KretaClient` + `Snapshot.fetch` + a mapping file `KretaMapping.swift` (`Ora → Lesson`,
  `Ertekeles → Grade`, …). The DTOs stay as they are, only for decoding.
- `NeptunProvider(institution:)`: `NeptunClient` on the institution's API address (Bearer + cookies,
  `GetNewTokens` renewal, single-flight), `NeptunDTO.swift` (decoders written only from captured payloads),
  `NeptunMapping.swift`. Nothing in it is BME-specific; `Institution.discover(web:)` reads the config file.
- `AppStore` holds `provider: SchoolProvider?` instead of `client: KretaClient?`; the token in the Keychain carries its
  `AccountKind`. **One app for both, one account at a time** (decided 2026-11-28): logging out and choosing the
  other kind switches, like today; no account picker, no per-account caches.

### University-specific UI

- **Login**: the first screen asks "KRÉTA (középiskola)" or "Egyetem (Neptun)". For Neptun a searchable list of
  institutions comes next (`Firka/Institutions.json`, built from the 56 known ones and kept to those whose config
  check passes), with "Nincs a listán? Cím megadása" for typing the Neptun web address. Firka checks the address
  (config file), then opens that university's own login page. The chosen university is shown in Settings and kept
  with the token. Demo mode gets `FIRKA_DEMO=neptun` (a made-up university with BME-shaped data).
- **Semester switcher** on the Grades tab (Neptun only): a menu with the semesters; the current one by default.
- **Averages** (pure functions in `Grades.swift`, tested): KRÉTA keeps its percentage-weighted average; Neptun shows
  - súlyozott tanulmányi átlag = Σ(kredit × jegy) / Σ(kredit) over passed subjects,
  - kreditindex = Σ(kredit × jegy, passed) / 30,
  - korrigált kreditindex = kreditindex × teljesített kredit / felvett kredit,
  preferring Neptun's own numbers from `GetTermAveragesByTraining` when present and using ours for "Mi lenne, ha…"
  (pick a grade for a subject not graded yet).
- **Tabs**: Neptun replaces "Hiányzások" with **"Vizsgák"** (registered exams, upcoming first; results per semester),
  "Egyebek" keeps Messages and Settings, hides Homework/Tests. Timetable, widget, Live Activity, hidden lessons and
  renames work unchanged on `Lesson`.
- **Notifications** (`Notifier.changes` on neutral types): new grade, cancelled/changed class, new exam date or
  exam result, new message. Phone-only for Neptun (section 2).

### Debug capture: real BME payloads before any decoder

Two ways, the first needs no app code:

1. **HAR from Safari** (recommended first): log in at `neptun.bme.hu/hallgatoi/` in Safari on the Mac, open the
   pages (Órarend, Tárgyak, Vizsgák, Üzenetek, Átlagok), Web Inspector › Network › Export HAR. A script
   `scripts/neptun-har-to-fixtures.mjs` keeps only `/hallgatoi/api/` responses, **redacts** names, Neptun code,
   e-mails, ids that identify a person and every token/cookie, and writes `FirkaTests/Fixtures/neptun/*.json`.
   You review the diff before anything is committed.
2. **`FIRKA_NEPTUN_PROBE=1`** (DEBUG builds, like `DebugProbe.swift`): after the in-app login it calls the endpoints
   of section 3 and saves the raw JSON into the app's Documents (pulled with `xcrun devicectl … copy`), then logs
   the token's expiry and retries `GetNewTokens` every 10 minutes to **measure the session's absolute lifetime**.
   Its output goes through the same redaction script.

## 5. What must be answered with a real BME login (before Phase 2 step B)

1. Does BME ask for a second factor every time, sometimes, or never? Captcha?
2. Where the refresh token lives (cookie name, HttpOnly?) and the real `sessionTimeoutInMinutes`.
3. How long `GetNewTokens` keeps working: after 1 h, 8 h, 24 h idle? (decides background refresh and push)
4. The response shapes of every endpoint in section 3 (fixtures).
5. Whether BME's calendar holds class times for the whole term, and how a cancelled class looks.

## 6. Plan for Phase 2 (after review)

- **Step A** (no Neptun code): `Domain.swift`, `KretaMapping.swift`, `SchoolProvider`, `KretaProvider`;
  `Snapshot` v2; screens, widget, Live Activity, `Notifier.changes`, hidden lessons and renames on the neutral types.
  Tests first for the mapping (KRÉTA fixtures → domain) and the cache migration; every existing unit and UI test
  stays green; no visible change. Committed in small steps (models + mapping; store; screens; widget/activity).
- **Step B**: capture (section 4) → fixtures → `NeptunClient` against `Stub.swift` (login capture, renewal,
  reauth), `Institution.discover` (redirects, BOM, extra keys, wrong address) and the institution list script,
  decoders from the fixtures, credit math, login picker, semester switcher, Vizsgák tab,
  `FIRKA_DEMO=neptun` with UI tests and the contrast audit in light and dark.

## Open questions for you

1. ~~One account at a time or side by side?~~ Decided: one app, one account at a time, log out to switch.
2. Neptun notifications phone-only (no password/TOTP on the server): agreed?
3. Capture by HAR from Safari first: is that fine for you to do once you can log in?
4. Which averages do you want to see: tanulmányi átlag, kreditindex, korrigált kreditindex, all three?

## Sources

- BME production client: `https://neptun.bme.hu/hallgatoi/` (bundle and `assets/config/config.json`), read 2026-11-28.
- IdrissaMaiga/neptun-api (Python, new Angular API, tested at Óbuda and Debrecen): `neptun_api/client.py`, `models.py`, `README.md`.
- ProgrammerGnome/NeptunMod (PTE, 2024): access token lifetime and the renewal loophole being closed.
- GreGamingHUN/Neptun-API, RuzsaGergely/Poszeidon: the old mobile API (deprecated, password in every request);
  `Institutes.json` (56 institutions with OM codes and old addresses).
- The public `assets/config/config.json` of BME, Óbuda, Debrecen, Szeged and Pécs, read 2026-11-28.
