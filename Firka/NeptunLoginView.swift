import SwiftUI
import WebKit

/// Choosing a university: the checked list (searchable), or a typed Neptun address. Then its own login page.
struct UniversityPicker: View {
    let done: () -> Void
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var checking = false
    @State private var error: String?
    @State private var typing = false
    @State private var address = ""
    @State private var chosen: Institution?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(KnownInstitution.search(search, in: KnownInstitution.all)) { u in
                        Button(u.name) { Task { await open(u.web, name: u.name, omCode: u.omCode) } }
                            .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("A Neptun új webes felületét használó intézmények.")
                }
                Section {
                    Button("Cím megadása") { typing = true }.accessibilityIdentifier("neptunAddress")
                } header: { Text("Nincs a listán?") } footer: {
                    Text("A Neptun webes címe, ahol be szoktál lépni, pl. https://neptun.egyetem.hu/hallgato/")
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Egyetem keresése")
            .overlay { if checking { ProgressView() } }
            .disabled(checking)
            .navigationTitle("Egyetem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mégse", action: done) } }
            .alert("Neptun címe", isPresented: $typing) {
                TextField("https://…", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Tovább") {
                    let text = address.trimmingCharacters(in: .whitespaces)
                    if let url = URL(string: text.contains("://") ? text : "https://" + text) {
                        Task { await open(url, name: url.host ?? "Egyetem", omCode: nil) }
                    }
                }
                Button("Mégse", role: .cancel) {}
            }
            .alert("Nem sikerült", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
            .navigationDestination(item: $chosen) { NeptunLoginPage(institution: $0, done: done) }
        }
    }

    private func open(_ web: URL, name: String, omCode: String?) async {
        checking = true
        defer { checking = false }
        do {
            chosen = try await Institution.discover(web: web, name: name, omCode: omCode)
        } catch NeptunError.notNeptun {
            error = "Ezen a címen nem az új Neptun webes felülete van."
        } catch {
            self.error = "Nem érhető el a Neptun. Van internet?"
        }
    }
}

/// The university's own Neptun login page; captcha and the authenticator code are typed there, never in Firka.
struct NeptunLoginPage: View {
    let institution: Institution
    let done: () -> Void
    @Environment(AppStore.self) private var store
    @State private var signingIn = false

    var body: some View {
        NeptunLoginWebView(institution: institution) { session in
            guard !signingIn else { return }
            signingIn = true
            Task {
                await store.signedIn(neptun: session)
                done()
            }
        }
        .overlay { if signingIn { ProgressView("Bejelentkezés…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .navigationTitle(institution.web.host ?? institution.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Watches the page until it holds a logged-in session (BME's client keeps `access_token` in sessionStorage),
/// then hands over that token and the university's cookies (NeptunLogin.session).
struct NeptunLoginWebView: UIViewRepresentable {
    let institution: Institution
    let onSession: (NeptunSession) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(institution: institution, onSession: onSession) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()  // always a clean login
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: institution.web))
        context.coordinator.watch(web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let institution: Institution
        let onSession: (NeptunSession) -> Void
        private var timer: Timer?
        private var handed = false

        init(institution: Institution, onSession: @escaping (NeptunSession) -> Void) {
            self.institution = institution
            self.onSession = onSession
        }

        /// The Angular app logs in without a page load, so look every second too.
        func watch(_ web: WKWebView) {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak web] _ in
                Task { @MainActor in if let web { self?.check(web) } }
            }
        }

        func stop() { timer?.invalidate() }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { check(webView) }

        private func check(_ web: WKWebView) {
            guard !handed else { return }
            let js = "JSON.stringify(Object.assign({}, Object.fromEntries(Object.entries(localStorage)), Object.fromEntries(Object.entries(sessionStorage))))"
            web.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, let text = result as? String,
                      let storage = try? JSONDecoder().decode([String: String].self, from: Data(text.utf8)),
                      storage["access_token"]?.isEmpty == false else { return }
                web.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    Task { @MainActor in
                        guard !self.handed, let s = NeptunLogin.session(storage: storage, cookies: cookies, institution: self.institution) else { return }
                        self.handed = true
                        self.stop()
                        self.onSession(s)
                    }
                }
            }
        }
    }
}
