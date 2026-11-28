import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmLogout = false
    @State private var notifStatus: UNAuthorizationStatus?
    @Environment(\.scenePhase) private var phase
    @AppStorage(Pref.liveActivity) private var liveActivity = true
    @AppStorage(Pref.serverPush) private var serverPush = false
    @State private var serverStatus: Result<ServerPush.Status, Error>?
    @State private var testSent: Bool?  // the test button's outcome

    var body: some View {
        Form {
            Section {
                if ServerPush.base != nil {
                    Toggle("Értesítések a szerverről", isOn: $serverPush)
                        .accessibilityIdentifier("serverPushToggle")
                        .onChange(of: serverPush) { Task { await ServerPush.sync() } }
                }
                ForEach(Notifier.kinds, id: \.key) { k in NotifToggle(key: k.key, label: k.label) }
                if serverPush, ServerPush.base != nil {
                    switch serverStatus {
                    case .success(let st) where !st.loggedIn:
                        Label("A szerver nincs bejelentkezve a KRÉTA-ba", systemImage: "exclamationmark.triangle.fill")
                    case .success(let st):
                        LabeledContent("Szerver utolsó lekérdezése", value: st.lastPoll?.hu("MMMd. HH:mm") ?? "még nem volt")
                    case .failure:
                        Label("A szerver nem érhető el (Tailscale be van kapcsolva?)", systemImage: "exclamationmark.triangle.fill")
                    case nil:
                        LabeledContent("Szerver utolsó lekérdezése", value: "…")
                    }
                    Button("Teszt értesítés küldése") {
                        guard let base = ServerPush.base else { return }
                        testSent = nil
                        Task { testSent = (try? await ServerPush.sendTest(to: base)) != nil }
                    }
                    .accessibilityIdentifier("serverPushTest")
                    if let testSent {
                        Text(testSent ? "Elküldve: pár másodpercen belül meg kell jönnie." : "Nem sikerült elküldeni (Tailscale be van kapcsolva?)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if let notifStatus, let why = Notifier.blocker(auth: notifStatus, refresh: UIApplication.shared.backgroundRefreshStatus,
                                                               lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled) {
                    Label { Text(why) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        .accessibilityIdentifier("notificationBlocker")
                    Button(notifStatus == .notDetermined ? "Értesítések engedélyezése" : "Megnyitás a Beállításokban") {
                        Task {
                            if notifStatus == .notDetermined {
                                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                                self.notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                            } else {
                                await UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                            }
                        }
                    }
                }
                if !serverPush {
                    LabeledContent("Utolsó háttérfrissítés",
                                   value: (UserDefaults.standard.object(forKey: Pref.lastBackgroundRun) as? Date)?.hu("MMMd. HH:mm") ?? "még nem volt")
                }
            } header: {
                Text("Értesítések")
            } footer: {
                if serverPush, ServerPush.base != nil {
                    Text("A saját szervered néhány percenként megnézi a KRÉTÁ-t, és az ntfy appon keresztül értesít. A Firka ilyenkor nem küld saját értesítést, csak a fenti beállításokat, az átnevezéseket és a rejtett órákat küldi el a szervernek.")
                } else {
                    Text("Értesítés akkor jön, ha az iOS a háttérben frissíti a Firkát. Hogy milyen gyakran, azt az iOS dönti el (ha gyakran használod, néhányszor óránként). Ha az appváltóban felfelé húzva bezárod, addig nem frissül, amíg újra meg nem nyitod.")
                }
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
        // again on return from the iOS Settings
        .task(id: phase) { notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        .task(id: serverPush) {
            guard serverPush, let base = ServerPush.base else { return }
            do { serverStatus = .success(try await ServerPush.status(from: base)) } catch { serverStatus = .failure(error) }
        }
        .onDisappear { Task { await ServerPush.sync() } }  // renames, toggles: the server should know before the next poll
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
