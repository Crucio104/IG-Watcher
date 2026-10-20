import SwiftUI
import WebKit

/// Vista modale con WKWebView che consente l'accesso sicuro direttamente sulla pagina ufficiale di Instagram.
/// Intercetta automaticamente tutti i cookie di sessione (inclusi datr, mid, ig_did, rur) una volta completato il login.
struct InstagramLoginWebView: UIViewRepresentable {
    @Environment(\.dismiss) var dismiss
    var onLoginSuccess: @MainActor (InstagramSession) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Usa il dataStore predefinito persistente così i token del dispositivo (datr, mid, ig_did) rimangono salvati
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Registra l'observer dei cookie per rilevare il login in tempo reale
        context.coordinator.setupCookieObserver(in: webView)
        context.coordinator.targetWebView = webView

        if let loginURL = URL(string: "https://www.instagram.com/accounts/login/") {
            var request = URLRequest(url: loginURL)
            request.setValue("it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
            webView.load(request)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        var parent: InstagramLoginWebView
        weak var targetWebView: WKWebView?
        private var hasExtractedSession = false
        private weak var observedCookieStore: WKHTTPCookieStore?

        init(_ parent: InstagramLoginWebView) {
            self.parent = parent
        }

        func setupCookieObserver(in webView: WKWebView) {
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            self.observedCookieStore = cookieStore
            cookieStore.add(self)
        }

        isolated deinit {
            observedCookieStore?.remove(self)
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in
                self.checkCookies(in: cookieStore)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            checkCookies(in: cookieStore)
        }

        private func checkCookies(in cookieStore: WKHTTPCookieStore) {
            guard !hasExtractedSession else { return }

            cookieStore.getAllCookies { [weak self] cookies in
                guard let self = self, !self.hasExtractedSession else { return }

                var dsUserID: String?
                var sessionID: String?
                var csrfToken: String?
                var dsUser: String?

                for cookie in cookies {
                    if cookie.name == "ds_user_id" {
                        dsUserID = cookie.value
                    } else if cookie.name == "sessionid" {
                        sessionID = cookie.value
                    } else if cookie.name == "csrftoken" {
                        csrfToken = cookie.value
                    } else if cookie.name == "ds_user" {
                        dsUser = cookie.value
                    }
                }

                // Quando tutti e tre i cookie chiave di sessione sono presenti, il login è valido
                if let uid = dsUserID, let sid = sessionID, let csrf = csrfToken {
                    self.hasExtractedSession = true

                    // Cattura tutti i cookie attivi del dominio instagram per superare i controlli WAF/Anti-Bot di Meta
                    let igCookies = cookies.filter { $0.domain.contains("instagram.com") }
                    let rawCookieHeader = igCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

                    // Rileva lo User Agent autentico nativo del WebKit senza manomissioni per evitare l'avviso di accesso sospetto
                    self.targetWebView?.evaluateJavaScript("navigator.userAgent") { [weak self] uaResult, _ in
                        guard let self = self else { return }
                        let authenticUA = (uaResult as? String) ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            InstagramSessionManager.shared.saveSession(
                                userID: uid,
                                sessionID: sid,
                                csrfToken: csrf,
                                userAgent: authenticUA,
                                rawCookieHeader: rawCookieHeader
                            )
                            if let u = dsUser, !u.isEmpty {
                                let initialUser = InstagramUser(id: uid, username: u)
                                InstagramSessionManager.shared.updateUserProfile(initialUser)
                            }
                            let session = InstagramSession(
                                userID: uid,
                                sessionID: sid,
                                csrfToken: csrf,
                                userAgent: authenticUA,
                                rawCookieHeader: rawCookieHeader
                            )

                            // Risolve e salva subito il profilo per mostrare nickname e avatar senza ritardi
                            if let profile = try? await InstagramAPIService.shared.fetchCurrentUserProfile(session: session) {
                                InstagramSessionManager.shared.updateUserProfile(profile)
                            } else if let jsonString = await InstagramWebBridge.shared.fetchCurrentUserProfile(userID: session.userID),
                                      let data = jsonString.data(using: .utf8),
                                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                      let uname = json["username"] as? String, !uname.isEmpty {
                                let fullName = (json["full_name"] as? String) ?? ""
                                let isVerified = (json["is_verified"] as? Bool) ?? false
                                let picURLStr = (json["profile_pic_url"] as? String)
                                let picURL = picURLStr != nil ? URL(string: picURLStr!) : nil
                                let profile = InstagramUser(
                                    id: session.userID,
                                    username: uname,
                                    fullName: fullName,
                                    profilePicURL: picURL,
                                    isVerified: isVerified
                                )
                                InstagramSessionManager.shared.updateUserProfile(profile)
                            }

                            self.parent.onLoginSuccess(session)
                            self.parent.dismiss()
                        }
                    }
                }
            }
        }
    }
}
