import SwiftUI
import WebKit

struct LoginScreen: View {
    var reauth = false
    @Environment(AppStore.self) private var store
    @State private var showWeb = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("Logo")
                .resizable()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28))
            Text("Firka").font(.largeTitle.bold())
            Text(reauth ? "A bejelentkezésed lejárt. Jelentkezz be újra a KRÉTA fiókoddal."
                        : "Nem hivatalos KRÉTA napló. Jelentkezz be a KRÉTA fiókoddal.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote).multilineTextAlignment(.center)
            }
            Spacer()
            Button { showWeb = true } label: {
                Text("Bejelentkezés").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(.firkaLogo)  // exactly the logo's background
            if reauth {
                Button("Kijelentkezés", role: .destructive) { store.needsReauth = false; store.logout() }
            }
            #if DEBUG
            if !reauth { Button("Demó mód (teszt adatok)") { store.startDemo() }.font(.footnote) }
            #endif
        }
        .padding(24)
        .sheet(isPresented: $showWeb) {
            LoginSheet { result in
                showWeb = false
                if case .failure(let e) = result { error = e.localizedDescription }
            }
        }
    }
}

/// KRÉTA's own login page in a web view; we catch the OAuth redirect and swap the code for tokens.
struct LoginSheet: View {
    let done: (Result<Void, Error>) -> Void
    @Environment(AppStore.self) private var store
    @State private var pkce = PKCE()
    @State private var exchanging = false
    @State private var pageLoaded = false

    var body: some View {
        NavigationStack {
            LoginWebView(url: pkce.loginURL, state: pkce.state, onLoaded: { pageLoaded = true }) { code in
                exchanging = true
                Task {
                    do {
                        try await store.login(code: code, pkce: pkce)
                        done(.success(()))
                    } catch {
                        log.error("login failed: \(String(describing: error), privacy: .public)")
                        done(.failure(error))
                    }
                }
            }
            .overlay { if !pageLoaded { ProgressView() } }
            .overlay { if exchanging { ProgressView("Bejelentkezés…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
            .navigationTitle("idp.e-kreta.hu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mégse") { done(.success(())) } } }
        }
    }
}

struct LoginWebView: UIViewRepresentable {
    let url: URL
    let state: String  // the login's own: a redirect carrying another one isn't ours
    let onLoaded: () -> Void
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(state: state, onLoaded: onLoaded, onCode: onCode) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()  // always a clean login, like firka
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: String
        let onLoaded: () -> Void
        let onCode: (String) -> Void
        private var handled = false
        init(state: String, onLoaded: @escaping () -> Void, onCode: @escaping (String) -> Void) {
            self.state = state; self.onLoaded = onLoaded; self.onCode = onCode
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onLoaded() }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, Kreta.isRedirect(url) else { return decisionHandler(.allow) }
            decisionHandler(.cancel)
            if !handled, let code = Kreta.code(fromRedirect: url, state: state) {
                handled = true
                onCode(code)
            }
        }
    }
}
