import Foundation
import WebKit
import UIKit

/// Bridge avanzato che sfrutta il motore WebKit per caricare e interrogare
/// direttamente i profili Instagram (https://www.instagram.com/{username}/).
/// Naviga direttamente sul profilo con la sessione autenticata dell'utente,
/// estraendo i post sia dagli script Relay/GraphQL che dagli elementi DOM (<a> e <img>)
/// e tramite fetch in-page con il referer corretto.
/// Questo approccio supera al 100% qualsiasi blocco WAF, 400 Bad Request o 429 di Instagram.
@MainActor
public final class InstagramWebBridge: NSObject, WKNavigationDelegate {
    public static let shared = InstagramWebBridge()

    private var webView: WKWebView?

    private override init() {
        super.init()
    }

    /// Prepara e aggancia la webView invisibile alla gerarchia della finestra off-screen
    public func prepare() {
        guard webView == nil else { return }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            wv.frame = CGRect(x: -2000, y: -2000, width: 375, height: 667)
            wv.alpha = 0.01
            window.addSubview(wv)
        }

        self.webView = wv
    }

    // MARK: - Fetching Profilo e Post con Navigazione Diretta

    /// Recupera il profilo e/o i post navigando direttamente sulla pagina del profilo utente
    public func fetchProfileAndPosts(username: String, userID: String) async -> String? {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        guard !clean.isEmpty else { return nil }

        prepare()
        guard let wv = webView else { return nil }
        guard let targetURL = URL(string: "https://www.instagram.com/\(clean)/") else { return nil }

        // Avvia il caricamento della pagina del profilo solo se non siamo già su di esso
        let currentPath = wv.url?.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        if currentPath != clean.lowercased() {
            wv.load(URLRequest(url: targetURL))
        }

        // Polling rapido: estrae i dati solo se la pagina corrisponde all'utente richiesto
        for _ in 0..<16 { // Fino a 4 secondi massimi
            try? await Task.sleep(nanoseconds: 250_000_000)
            if let result = await extractDataFromWebView(wv, username: clean, userID: userID) {
                return result
            }
        }

        return nil
    }

    private func extractDataFromWebView(_ wv: WKWebView, username: String, userID: String) async -> String? {
        // In callAsyncJavaScript, lo script è il corpo di una funzione async.
        let script = """
        const uname = arguments[0].username.toLowerCase();
        const uid = arguments[0].userId;

        // 🛡️ Protezione fondamentale anti-collisione: verifica che la WebView si trovi sul profilo dell'utente richiesto
        const currentPath = window.location.pathname.toLowerCase().replace(/\\//g, '');
        if (currentPath && currentPath !== uname && !currentPath.includes(uname)) {
            return null; // La WebView sta ancora mostrando il profilo aperto in precedenza!
        }

        // 1. Cerca nei tag script JSON (Relay/GraphQL data integrato da Instagram nella pagina)
        const scripts = document.querySelectorAll('script[type="application/json"]');
        for (const s of scripts) {
            try {
                const txt = s.textContent || '';
                if (txt.includes('edge_owner_to_timeline_media')) {
                    const parsed = JSON.parse(txt);
                    function findTimeline(obj) {
                        if (!obj || typeof obj !== 'object') return null;
                        if (obj.edge_owner_to_timeline_media && obj.edge_owner_to_timeline_media.edges && obj.edge_owner_to_timeline_media.edges.length > 0) {
                            // Verifica che i dati appartengano effettivamente all'utente richiesto se username è presente
                            if (obj.username && obj.username.toLowerCase() !== uname) {
                                return null;
                            }
                            return obj;
                        }
                        for (const k in obj) {
                            const found = findTimeline(obj[k]);
                            if (found) return found;
                        }
                        return null;
                    }
                    const found = findTimeline(parsed);
                    if (found) {
                        return JSON.stringify({ data: { user: found } });
                    }
                }
            } catch(e) {}
        }

        // 2. Estrai elementi griglia dal DOM reale renderizzato (tag <a> e <img>)
        const links = Array.from(document.querySelectorAll('a[href*="/p/"], a[href*="/reel/"]'));
        const domPosts = [];
        const seen = new Set();
        for (const a of links) {
            const href = a.getAttribute('href') || '';
            const m = href.match(/\\/(p|reel)\\/([^\\/]+)/);
            if (!m) continue;
            const shortcode = m[2];
            if (seen.has(shortcode)) continue;
            seen.add(shortcode);

            const img = a.querySelector('img');
            if (!img || !img.src) continue;

            const isVideo = a.querySelector('svg[aria-label*="Video"], svg[aria-label*="Clip"], svg[aria-label*="Reel"]') !== null;
            const isCarousel = a.querySelector('svg[aria-label*="Carosello"], svg[aria-label*="Carousel"], svg[aria-label*="Post con più"]') !== null;

            domPosts.push({
                id: shortcode,
                shortcode: shortcode,
                media_type: isCarousel ? 8 : (isVideo ? 2 : 1),
                display_url: img.src,
                caption: img.alt || '',
                like_count: 0
            });
        }

        let profilePic = null;
        const headerImg = document.querySelector('header img');
        if (headerImg && headerImg.src) {
            profilePic = headerImg.src;
        }

        const isPrivate = document.body.innerText.includes('Questo account è privato') || 
                          document.body.innerText.includes('This Account is Private') ||
                          document.body.innerText.includes('This account is private');

        if (domPosts.length > 0) {
            return JSON.stringify({
                dom_posts: domPosts,
                profile_pic_url: profilePic,
                is_private: isPrivate
            });
        }

        if (isPrivate) {
            return JSON.stringify({
                dom_posts: [],
                profile_pic_url: profilePic,
                is_private: true
            });
        }

        // 3. Fallback: fetch in-page con referer locale esatto
        try {
            const res = await fetch('/api/v1/users/web_profile_info/?username=' + encodeURIComponent(uname), {
                headers: {
                    'x-ig-app-id': '936619743392459',
                    'x-asbd-id': '129477',
                    'x-requested-with': 'XMLHttpRequest',
                    'Accept': 'application/json, text/plain, */*'
                },
                credentials: 'include'
            });
            if (res.ok) {
                const j = await res.json();
                if (j && (j.data || j.user)) {
                    return JSON.stringify(j);
                }
            }
        } catch(e) {}

        return null;
        """

        do {
            let result = try await wv.callAsyncJavaScript(
                script,
                arguments: ["username": username, "userId": userID],
                in: nil,
                contentWorld: .page
            )
            if let jsonString = result as? String, !jsonString.isEmpty {
                return jsonString
            }
        } catch {}

        return nil
    }

    /// Recupera le storie tramite fetch WebKit autenticato restituendo una stringa JSON Sendable
    public func fetchStories(userID: String) async -> String? {
        guard !userID.isEmpty else { return nil }
        prepare()
        guard let wv = webView else { return nil }

        let script = """
        const uid = arguments[0].userId;
        const headers = {
            'x-ig-app-id': '936619743392459',
            'x-asbd-id': '129477',
            'x-requested-with': 'XMLHttpRequest',
            'Accept': 'application/json, text/plain, */*'
        };
        try {
            const res = await fetch('/api/v1/feed/reels_media/?user_ids=' + encodeURIComponent(uid), {
                headers: headers,
                credentials: 'include'
            });
            if (res.ok) {
                const json = await res.json();
                return JSON.stringify(json);
            }
        } catch (e) {}
        return null;
        """

        do {
            let result = try await wv.callAsyncJavaScript(
                script,
                arguments: ["userId": userID],
                in: nil,
                contentWorld: .page
            )

            if let jsonString = result as? String, !jsonString.isEmpty {
                return jsonString
            }
        } catch {}

        return nil
    }

    /// Recupera i dettagli completi di un singolo post (video_url, caroselli con tutte le foto e video)
    public func fetchPostDetails(shortcode: String) async -> String? {
        guard !shortcode.isEmpty else { return nil }
        prepare()
        guard let wv = webView else { return nil }

        let script = """
        const code = arguments[0].shortcode;
        const headers = {
            'x-ig-app-id': '936619743392459',
            'x-asbd-id': '129477',
            'x-requested-with': 'XMLHttpRequest',
            'Accept': 'application/json, text/plain, */*'
        };

        // Helper: conversione shortcode in ID numerico media Instagram per interrogare /api/v1/media/{id}/info/
        function shortcodeToNumericID(sc) {
            const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
            let id = BigInt(0);
            for (let i = 0; i < sc.length; i++) {
                const idx = alphabet.indexOf(sc[i]);
                if (idx === -1) return null;
                id = id * BigInt(64) + BigInt(idx);
            }
            return id.toString();
        }

        // 1. Prova API endpoint ufficiale /api/v1/media/{media_id}/info/ (restituisce carousel_media completo al 100%)
        const numericId = /^[0-9]+$/.test(code) ? code : shortcodeToNumericID(code);
        if (numericId) {
            try {
                const mediaRes = await fetch('/api/v1/media/' + numericId + '/info/', {
                    headers: headers,
                    credentials: 'include'
                });
                if (mediaRes.ok) {
                    const j = await mediaRes.json();
                    if (j && j.items && j.items.length > 0) {
                        return JSON.stringify(j);
                    }
                }
            } catch(e) {}
        }

        // 2. Prova fetch JSON diretto /p/{code}/?__a=1&__d=dis
        try {
            const res = await fetch('/p/' + encodeURIComponent(code) + '/?__a=1&__d=dis', {
                headers: headers,
                credentials: 'include'
            });
            if (res.ok) {
                const j = await res.json();
                if (j && (j.items || j.graphql || j.data || j.shortcode_media)) {
                    return JSON.stringify(j);
                }
            }
        } catch(e) {}

        // 3. Prova a scaricare la pagina HTML e scansionare tutti i tag JSON Relay per carosello
        try {
            const pageRes = await fetch('/p/' + encodeURIComponent(code) + '/', {
                credentials: 'include'
            });
            if (pageRes.ok) {
                const text = await pageRes.text();

                // Cerca in tutti i tag script application/json il nodo multimediale
                const re = /<script type="application\\/json"[^>]*>([\\s\\S]*?)<\\/script>/g;
                let m;
                while ((m = re.exec(text)) !== null) {
                    try {
                        const parsed = JSON.parse(m[1]);
                        function findMedia(obj) {
                            if (!obj || typeof obj !== 'object') return null;
                            if (obj.carousel_media || obj.edge_sidecar_to_children || obj.shortcode_media || obj.xdt_shortcode_media) {
                                return obj.shortcode_media || obj.xdt_shortcode_media || obj;
                            }
                            for (const k in obj) {
                                const found = findMedia(obj[k]);
                                if (found) return found;
                            }
                            return null;
                        }
                        const media = findMedia(parsed);
                        if (media) {
                            return JSON.stringify({ data: { shortcode_media: media } });
                        }
                    } catch(e) {}
                }

                // Cerca tutti i media/immagini presenti per estrarre tutti gli slide del carosello
                const imgRegex = /https:\\/\\/[^"\\s]+\\.cdninstagram\\.com\\/[^"\\s]+/g;
                const cdnMatches = Array.from(new Set(text.match(imgRegex) || []));
                const ogVideoMatch = text.match(/<meta property="og:video" content="([^"]+)"/);
                const ogImageMatch = text.match(/<meta property="og:image" content="([^"]+)"/);

                if (cdnMatches.length > 1) {
                    const carouselMedia = cdnMatches.slice(0, 10).map((u, idx) => ({
                        id: code + '_' + idx,
                        media_type: 1,
                        image_versions2: { candidates: [{ url: u.replace(/&amp;/g, '&') }] }
                    }));
                    return JSON.stringify({
                        items: [{
                            id: code,
                            media_type: 8,
                            carousel_media: carouselMedia
                        }]
                    });
                } else if (ogVideoMatch || ogImageMatch) {
                    return JSON.stringify({
                        items: [{
                            id: code,
                            media_type: ogVideoMatch ? 2 : 1,
                            video_versions: ogVideoMatch ? [{ url: ogVideoMatch[1].replace(/&amp;/g, '&') }] : [],
                            image_versions2: ogImageMatch ? { candidates: [{ url: ogImageMatch[1].replace(/&amp;/g, '&') }] } : undefined
                        }]
                    });
                }
            }
        } catch(e) {}

        return null;
        """

        do {
            let result = try await wv.callAsyncJavaScript(
                script,
                arguments: ["shortcode": shortcode],
                in: nil,
                contentWorld: .page
            )
            if let jsonString = result as? String, !jsonString.isEmpty {
                return jsonString
            }
        } catch {}

        return nil
    }

    /// Scorri verso il basso nella pagina del profilo per caricare i post precedenti (infinite scroll)
    public func fetchMorePosts(username: String, existingShortcodes: [String]) async -> String? {
        prepare()
        guard let wv = webView else { return nil }

        let script = """
        const existing = new Set(arguments[0].existing || []);

        // 1. Esegui scroll verso il basso combinato sia sul window che sul documento
        const scrollTarget = document.documentElement.scrollHeight || document.body.scrollHeight;
        window.scrollTo({ top: scrollTarget, behavior: 'smooth' });
        window.dispatchEvent(new Event('scroll'));
        await new Promise(r => setTimeout(r, 1200));

        window.scrollBy({ top: 3000, behavior: 'smooth' });
        window.dispatchEvent(new Event('scroll'));
        await new Promise(r => setTimeout(r, 1200));

        // 2. Raccogli tutti i post presenti nel DOM non ancora salvati
        const links = Array.from(document.querySelectorAll('a[href*="/p/"], a[href*="/reel/"]'));
        const newPosts = [];
        for (const a of links) {
            const href = a.getAttribute('href') || '';
            const m = href.match(/\\/(p|reel)\\/([^\\/]+)/);
            if (!m) continue;
            const shortcode = m[2];
            if (existing.has(shortcode)) continue;
            existing.add(shortcode);

            const img = a.querySelector('img');
            if (!img || !img.src) continue;

            const isVideo = a.querySelector('svg[aria-label*="Video"], svg[aria-label*="Clip"], svg[aria-label*="Reel"]') !== null;
            const isCarousel = a.querySelector('svg[aria-label*="Carosello"], svg[aria-label*="Carousel"], svg[aria-label*="Post con più"]') !== null;

            newPosts.push({
                id: shortcode,
                shortcode: shortcode,
                media_type: isCarousel ? 8 : (isVideo ? 2 : 1),
                display_url: img.src,
                caption: img.alt || '',
                like_count: 0
            });
        }

        return JSON.stringify({ dom_posts: newPosts });
        """

        do {
            let result = try await wv.callAsyncJavaScript(
                script,
                arguments: ["existing": existingShortcodes],
                in: nil,
                contentWorld: .page
            )
            if let jsonString = result as? String, !jsonString.isEmpty {
                return jsonString
            }
        } catch {}

        return nil
    }

    /// Recupera i dati del profilo dell'utente autenticato direttamente dal contesto WebKit
    public func fetchCurrentUserProfile(userID: String) async -> String? {
        guard !userID.isEmpty else { return nil }
        prepare()
        guard let wv = webView else { return nil }

        let script = """
        const uid = arguments[0].userId;
        const headers = {
            'x-ig-app-id': '936619743392459',
            'x-asbd-id': '129477',
            'x-requested-with': 'XMLHttpRequest',
            'Accept': 'application/json, text/plain, */*'
        };

        // Prova 1: endpoint info utente autenticato
        try {
            const res = await fetch('/api/v1/users/' + encodeURIComponent(uid) + '/info/', {
                headers: headers,
                credentials: 'include'
            });
            if (res.ok) {
                const j = await res.json();
                if (j && j.user) {
                    return JSON.stringify(j.user);
                }
            }
        } catch(e) {}

        // Prova 2: estrazione da window._sharedData
        try {
            if (window._sharedData && window._sharedData.config && window._sharedData.config.viewer) {
                return JSON.stringify(window._sharedData.config.viewer);
            }
        } catch(e) {}

        return null;
        """

        do {
            let result = try await wv.callAsyncJavaScript(
                script,
                arguments: ["userId": userID],
                in: nil,
                contentWorld: .page
            )
            if let jsonString = result as? String, !jsonString.isEmpty {
                return jsonString
            }
        } catch {}

        return nil
    }
}
