import Foundation
@testable import Firka

// Builders for realistic KRÉTA data. JSON shapes follow real responses (keys, nulls, date formats).

let subjectJSON = #"{"Uid":"1,MAT","Nev":"matematika","Kategoria":{"Uid":"1,matematika","Nev":"matematika","Leiras":"Matematika"},"SortIndex":0}"#
let historyJSON = #"{"Uid":"2,TOR","Nev":"történelem","SortIndex":1}"#

func decode<T: Decodable>(_ json: String) throws -> T {
    try Kreta.apiDecoder.decode(T.self, from: Data(json.utf8))
}

/// A grade as KRÉTA sends it. `kind`: "evkozi_jegy_ertekeles", "felevi_jegy_ertekeles", "evvegi_jegy_ertekeles".
func gradeJSON(_ uid: String, _ value: Int?, _ weight: Int?, valueType: String = "Osztalyzat",
               kind: String = "evkozi_jegy_ertekeles", date: String = "2025-10-01T08:00:00Z",
               subject: String = subjectJSON, text: String = "Jeles(5)", short: String? = nil, teacher: String = "Kovács Anna") -> String {
    #"{"Uid":"\#(uid)","RogzitesDatuma":"\#(date)","KeszitesDatuma":"\#(date)","LattamozasDatuma":null,"Tantargy":\#(subject),"Tema":"Törtek","Tipus":{"Uid":"1,\#(kind)","Nev":"\#(kind)","Leiras":"x"},"Mod":{"Uid":"1,irasbeli","Nev":"irasbeli","Leiras":"Írásbeli röpdolgozat"},"ErtekFajta":{"Uid":"1,\#(valueType)","Nev":"\#(valueType)","Leiras":"x"},"ErtekeloTanarNeve":"\#(teacher)","Jelleg":"Ertekeles","SzamErtek":\#(value.map(String.init) ?? "0"),"SzovegesErtek":"\#(text)","SulySzazalekErteke":\#(weight.map(String.init) ?? "null"),"SzovegesErtekelesRovidNev":\#(short.map { "\"\($0)\"" } ?? "null"),"OsztalyCsoport":{"Uid":"123"},"SortIndex":0}"#
}

/// Grades from KRÉTA-shaped JSON, through the mapping the app uses.
func grades(_ items: String...) throws -> [Grade] { try (decode("[\(items.joined(separator: ","))]") as [Ertekeles]).map(Grade.init(kreta:)) }

/// Absences, homework, tests and messages from KRÉTA-shaped JSON, through the app's mapping.
func absences(_ json: String) throws -> [Absence] { try (decode(json) as [Mulasztas]).map(Absence.init(kreta:)) }
func homework(_ json: String) throws -> [Homework] { try (decode(json) as [HaziFeladat]).map(Homework.init(kreta:)) }
func announcedTests(_ json: String) throws -> [AnnouncedTest] { try (decode(json) as [Szamonkeres]).map(AnnouncedTest.init(kreta:)) }
func notices(_ json: String) throws -> [Message] { try (decode(json) as [FaliujsagElem]).map(Message.init(kreta:)) }
func notes(_ json: String) throws -> [Message] { try (decode(json) as [Feljegyzes]).map(Message.init(kreta:)) }
func inbox(_ json: String) throws -> [Message] { try (decode(json) as [PostaladaElem]).map(Message.init(kreta:)) }

/// A lesson built directly; times are minutes after `day` midnight (local).
func lesson(_ uid: String, day: Date, from: Int, minutes: Int = 45, number: Int? = 1, subject: String = "matematika",
            cancelled: Bool = false, substitute: String? = nil, event: Bool = false) -> Lesson {
    let start = day.addingTimeInterval(Double(from) * 60)
    return Lesson(id: uid, kind: event ? .event : .lesson, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                  subject: event ? nil : Subject(id: "s-\(subject)", raw: subject), name: subject, number: number,
                  substitute: substitute, cancelled: cancelled, stateText: cancelled ? "Elmaradt" : "Naplózott")
}

/// Midnight of a date in Budapest, independent of the test machine's time zone.
func budapest(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Budapest")!
    return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

func widgetLesson(_ subject: String, _ start: Date, minutes: Int = 45, cancelled: Bool = false) -> WidgetLesson {
    WidgetLesson(subject: subject, room: nil, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                 number: nil, cancelled: cancelled, substituted: false)
}
