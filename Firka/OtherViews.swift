import SwiftUI
import UserNotifications

struct AbsencesView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let all = store.data.absences.sorted { $0.datum > $1.datum }
        let stats = AbsenceStats(all)
        let byDay = Dictionary(grouping: all) { $0.datum.startOfDay }.sorted { $0.key > $1.key }

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Stat(value: stats.justified, label: "Igazolt", color: .green)
                        Stat(value: stats.unjustified, label: "Igazolatlan", color: .red)
                        Stat(value: stats.pending, label: "Igazolandó", color: .orange)
                        Stat(value: stats.lateMinutes, label: "Késés, perc", color: nil)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                ForEach(byDay, id: \.key) { day, items in
                    Section(day.hu("yMMMMd EEEE")) {
                        ForEach(items.sorted { ($0.ora?.oraszam ?? 0) < ($1.ora?.oraszam ?? 0) }) { a in
                            HStack(spacing: 12) {
                                Text(a.ora?.oraszam.map { "\($0)." } ?? "")
                                    .font(.headline.monospacedDigit()).frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.tantargy.name)
                                    Text([a.isLate ? "Késés, \(a.kesesPercben ?? 0) perc" : "Hiányzás",
                                          a.igazolasAllapota == "Igazolt" ? a.igazolasTipusa?.leiras : nil]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(a.stateShort)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(a.stateColor)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(a.stateColor.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                }
            }
            .overlay { if all.isEmpty { ContentUnavailableView("Nincs hiányzásod", systemImage: "checkmark.seal") } }
            .navigationTitle("Hiányzások")
            .refreshable { await store.refresh() }
        }
    }
}

private struct Stat: View {
    let value: Int
    let label: String
    let color: Color?  // only non-zero counts get their color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.bold().monospacedDigit())
                .foregroundStyle(value > 0 ? color ?? .primary : .secondary)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MoreView: View {
    enum Page: Hashable { case homework, tests, messages, settings, rename, hidden }
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading) {
                        Text(store.data.studentName).font(.headline)
                        if let s = store.data.schoolName { Text(s).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    NavigationLink(value: Page.homework) { Label("Házi feladatok", systemImage: "house") }
                    NavigationLink(value: Page.tests) { Label("Számonkérések", systemImage: "exclamationmark.bubble") }
                    NavigationLink(value: Page.messages) { Label("Üzenetek, feljegyzések", systemImage: "envelope") }
                }
                Section {
                    NavigationLink(value: Page.rename) { Label("Tantárgyak, tanárok átnevezése", systemImage: "pencil") }
                    NavigationLink(value: Page.hidden) { Label("Elrejtett órák", systemImage: "eye.slash") }
                    NavigationLink(value: Page.settings) { Label("Beállítások", systemImage: "gear") }
                }
            }
            .navigationTitle("Egyebek")
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .homework: HomeworkList()
                case .tests: TestsList()
                case .messages: MessagesList()
                case .settings: SettingsView()
                case .rename: RenameView()
                case .hidden: HiddenLessonsView()
                }
            }
            .navigationDestination(for: HaziFeladat.self) { HomeworkDetail(hw: $0) }
            .navigationDestination(for: Szamonkeres.self) { TestDetail(test: $0) }
            .navigationDestination(for: Message.self) { MessageDetail(message: $0) }
        }
    }
}

struct HomeworkList: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let today = Date().startOfDay
        let (upcoming, past) = HomeLogic.split(store.data.homework, today: today, date: \.hataridoDatuma)
        List {
            if !upcoming.isEmpty { Section("Közelgő") { ForEach(upcoming) { h in NavigationLink(value: h) { HomeworkRow(hw: h) } } } }
            if !past.isEmpty { Section("Korábbi") { ForEach(past) { h in NavigationLink(value: h) { HomeworkRow(hw: h) } } } }
        }
        .overlay { if store.data.homework.isEmpty { ContentUnavailableView("Nincs házi feladat", systemImage: "party.popper") } }
        .navigationTitle("Házi feladatok")
        .refreshable { await store.refresh() }
    }
}

struct TestsList: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let today = Date().startOfDay
        let (upcoming, past) = HomeLogic.split(store.data.tests, today: today, date: \.datum)
        List {
            if !upcoming.isEmpty { Section("Közelgő") { ForEach(upcoming) { t in NavigationLink(value: t) { TestRow(test: t) } } } }
            if !past.isEmpty { Section("Korábbi") { ForEach(past) { t in NavigationLink(value: t) { TestRow(test: t) } } } }
        }
        .overlay { if store.data.tests.isEmpty { ContentUnavailableView("Nincs bejelentett számonkérés", systemImage: "checkmark") } }
        .navigationTitle("Számonkérések")
        .refreshable { await store.refresh() }
    }
}

struct MessagesList: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let messages = store.data.messages
        List(messages) { m in
            NavigationLink(value: m) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(m.title).font(.headline).lineLimit(1)
                        Spacer()
                        if !m.attachments.isEmpty {
                            Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("Csatolmány")
                        }
                        Text(m.date.hu(Calendar.hu.isDate(m.date, equalTo: Date(), toGranularity: .year) ? "MMMd" : "yMMMd"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let a = m.author { Text(a).font(.caption).foregroundStyle(.secondary) }
                    Text(m.html.strippingTags).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .overlay { if messages.isEmpty { ContentUnavailableView("Nincs üzenet", systemImage: "envelope.open") } }
        .navigationTitle("Üzenetek")
        .refreshable { await store.refresh() }
    }
}

struct MessageDetail: View {
    let message: Message
    @Environment(AppStore.self) private var store
    @State private var html: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(message.title).font(.title2.bold())
                Text([message.author, message.date.hu("yMMMMd")].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                Divider()
                HTMLText(html: html ?? message.html)
                if !message.attachments.isEmpty {
                    AttachmentList(attachments: message.attachments).padding(.top, 8)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
        // teacher messages arrive shortened in the list; fetch the whole text
        .task(id: message.id) { if let full = await store.fullMessage(message.id) { html = full } }
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmLogout = false
    @State private var notifStatus: UNAuthorizationStatus?
    @AppStorage(Pref.liveActivity) private var liveActivity = true

    var body: some View {
        Form {
            Section {
                ForEach(Notifier.kinds, id: \.key) { k in NotifToggle(key: k.key, label: k.label) }
                if notifStatus == .denied {
                    Button("Értesítések engedélyezése a Beállításokban") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
            } header: {
                Text("Értesítések")
            } footer: {
                Text("Az iOS dönti el, milyen gyakran frissülhet az app a háttérben (általában néhányszor óránként, ha gyakran használod). Az alacsony fogyasztású mód kikapcsolja.")
            }

            Section {
                Toggle("Mai órák a zárolt képernyőn", isOn: $liveActivity)
                    .onChange(of: liveActivity) { Task { await LessonLive.sync(store.data.widgetLessons, canStart: true) } }
            } header: {
                Text("Élő tevékenység")
            } footer: {
                Text("Tanítási napon a zárolt képernyőn látod a mostani vagy következő órát visszaszámlálással, alatta a nap óráit. Az óránkénti sávok maguktól haladnak; a fejléc akkor frissül, amikor a Firka fut (megnyitod, vagy az iOS háttérben frissíti).")
            }

            Section {
                Toggle("Meglepetés jegyek", isOn: Binding(get: { store.surpriseGrades }, set: { store.surpriseGrades = $0 }))
            } header: {
                Text("Jegyek")
            } footer: {
                Text("Az új jegyek elmosva látszanak a kezdőlapon, amíg rá nem koppintasz. Addig az átlagba sem számítanak bele, és az értesítés sem árulja el az értéküket.")
            }

            Section {
                ForEach(0..<4, id: \.self) { i in
                    Stepper(value: Binding(get: { store.rounding.t[i] },
                                           set: { store.rounding.t[i] = ($0 * 100).rounded() / 100 }),
                            in: 0.1...0.95, step: 0.05) {
                        LabeledContent("\(i + 2)-\(["es", "as", "es", "ös"][i]) ettől",
                                       value: (Double(i + 1) + store.rounding.t[i]).hu2)
                    }
                }
                if store.rounding != Rounding() {
                    Button("Visszaállítás (x,50)") { store.rounding = Rounding() }
                }
            } header: {
                Text("Kerekítés")
            } footer: {
                Text("Mekkora átlagtól számít a következő jegynek. Ebből jön a tantárgyak várható jegye, a várható bizonyítvány és az átlagok színe.")
            }

            Section {
                Button("Kijelentkezés", role: .destructive) { confirmLogout = true }
            }

            Section("Névjegy") {
                // the build number is the install time (scripts/renew-on-iphone.sh), so it shows which build is on the phone
                LabeledContent("Verzió", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                Link("Az eredeti Firka (QwIT Development)", destination: URL(string: "https://github.com/QwIT-Development/firka")!)
                Text("Ez a Firka iOS-re átírt, nem hivatalos változata. Licenc: CC BY-NC-SA 4.0. Nem áll kapcsolatban az eKRÉTA Informatikai Zrt.-vel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Beállítások")
        .task { notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        .alert("Biztosan kijelentkezel?", isPresented: $confirmLogout) {
            Button("Mégse", role: .cancel) {}
            Button("Kijelentkezés", role: .destructive) { store.logout() }
        } message: {
            Text("A letöltött adatok törlődnek erről a telefonról.")
        }
    }
}

private struct NotifToggle: View {
    let label: String
    @AppStorage private var on: Bool

    init(key: String, label: String) {
        self.label = label
        _on = AppStorage(wrappedValue: true, key)
    }

    var body: some View { Toggle(label, isOn: $on) }
}
