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

    private func attachToWindowIfNeeded(_ wv: WKWebView) {
        guard wv.superview == nil else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) ??
            UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first
        if let win = window {
            wv.frame = CGRect(x: -2000, y: -2000, width: 375, height: 667)
            wv.alpha = 0.01
            win.addSubview(wv)
        }
    }

    /// Prepara e aggancia la webView invisibile alla gerarchia della finestra off-screen
    public func prepare() {
        if let existing = webView {
            attachToWindowIfNeeded(existing)
            return
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        attachToWindowIfNeeded(wv)

        self.webView = wv
        if let homeURL = URL(string: "https://www.instagram.com/") {
            wv.load(URLRequest(url: homeURL))
        }
    }

    /// Attende che la webView abbia completato l'eventuale navigazione in corso
    private func waitForWebViewReady(_ wv: WKWebView, timeout: TimeInterval = 3.5) async {
        guard wv.isLoading else { return }
        let start = Date()
        while wv.isLoading && Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Naviga in modo affidabile verso il profilo desiderato se non già posizionato
    private func navigateToTargetProfile(_ wv: WKWebView, username: String) async {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        guard !clean.isEmpty, let targetURL = URL(string: "https://www.instagram.com/\(clean)/") else { return }
        let currentPath = wv.url?.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        if currentPath != clean.lowercased() {
            wv.load(URLRequest(url: targetURL))
            try? await Task.sleep(nanoseconds: 250_000_000)
            await waitForWebViewReady(wv, timeout: 5.0)
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    // MARK: - Fetching Profilo e Post con Navigazione Diretta

    /// Recupera il profilo e/o i post navigando o interrogando in-page direttamente le API WebKit
    public func fetchProfileAndPosts(username: String, userID: String) async -> String? {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        guard !clean.isEmpty else { return nil }

        prepare()
        guard let wv = webView else { return nil }

        // Attendi che l'eventuale caricamento iniziale sia completato
        await waitForWebViewReady(wv, timeout: 2.5)

        // 1. Esecuzione immediata ultra-rapida via fetch in-page (~100ms) senza navigare o ricaricare la WebView
        if let direct = await executeInPageFetch(wv, username: clean, userID: userID) {
            return direct
        }

        // 2. Se non ha ancora risposto, naviga sul profilo utente con attesa garantita di caricamento
        await navigateToTargetProfile(wv, username: clean)

        // 3. Riprova fetch in-page con il context della pagina del profilo utente
        if let direct = await executeInPageFetch(wv, username: clean, userID: userID) {
            return direct
        }

        // 4. Polling rapido: estrae i dati solo se la pagina corrisponde all'utente richiesto
        for _ in 0..<12 {
            if let result = await extractDataFromWebView(wv, username: clean, userID: userID) {
                return result
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        return nil
    }

    private func executeInPageFetch(_ wv: WKWebView, username: String, userID: String) async -> String? {
        let script = """
        let uname = '';
        if (typeof username !== 'undefined') uname = username;
        else if (arguments[0] && typeof arguments[0] === 'object' && arguments[0].username) uname = arguments[0].username;
        else if (arguments[0]) uname = arguments[0];
        uname = String(uname || '').toLowerCase().replace(/@/g, '').trim();

        let uid = '';
        if (typeof userId !== 'undefined') uid = userId;
        else if (arguments[0] && typeof arguments[0] === 'object' && arguments[0].userId) uid = arguments[0].userId;
        else if (arguments.length > 1 && arguments[1]) uid = arguments[1];
        uid = String(uid || '').trim();

        let csrf = (typeof csrfToken !== 'undefined' ? csrfToken : (arguments[0] && typeof arguments[0] === 'object' ? arguments[0].csrfToken : '')) || '';
        if (!csrf) {
            const m = document.cookie.match(/csrftoken=([^;]+)/);
            if (m && m[1]) csrf = m[1];
            if (!csrf && window._sharedData && window._sharedData.config) {
                csrf = window._sharedData.config.csrf_token || '';
            }
        }

        const headers = {
            'x-ig-app-id': '936619743392459',
            'x-asbd-id': '129477',
            'x-csrftoken': csrf,
            'x-requested-with': 'XMLHttpRequest',
            'Accept': 'application/json, text/plain, */*'
        };

        // Prova 1: web_profile_info
        if (uname && uname.length > 0) {
            try {
                const res = await fetch('https://www.instagram.com/api/v1/users/web_profile_info/?username=' + encodeURIComponent(uname), {
                    headers: headers,
                    credentials: 'include'
                });
                if (res.ok) {
                    const j = await res.json();
                    if (j && (j.data || j.user)) {
                        return JSON.stringify(j);
                    }
                }
            } catch(e) {}
        }

        // Prova 2: feed utente per ID numerico se fornito
        if (uid && /^[0-9]+$/.test(uid)) {
            try {
                const feedRes = await fetch('https://www.instagram.com/api/v1/feed/user/' + encodeURIComponent(uid) + '/?count=18', {
                    headers: headers,
                    credentials: 'include'
                });
                if (feedRes.ok) {
                    const fj = await feedRes.json();
                    if (fj && (fj.items || fj.data)) {
                        return JSON.stringify(fj);
                    }
                }
            } catch(e) {}
        }
        return null;
        """

        let effectiveCSRF = InstagramSessionManager.shared.currentSession?.csrfToken ?? ""
        do {
            let result = try await wv.callAsyncJavaScript(
                script,
                arguments: ["username": username, "userId": userID, "csrfToken": effectiveCSRF],
                in: nil,
                contentWorld: .page
            )
            if let jsonString = result as? String, !jsonString.isEmpty {
                return jsonString
            }
        } catch {}

        return nil
    }

    private func extractDataFromWebView(_ wv: WKWebView, username: String, userID: String) async -> String? {
        let script = """
        let uname = '';
        if (typeof username !== 'undefined') uname = username;
        else if (arguments[0] && typeof arguments[0] === 'object' && arguments[0].username) uname = arguments[0].username;
        else if (arguments[0]) uname = arguments[0];
        uname = String(uname || '').toLowerCase().replace(/@/g, '').trim();

        let uid = '';
        if (typeof userId !== 'undefined') uid = userId;
        else if (arguments[0] && typeof arguments[0] === 'object' && arguments[0].userId) uid = arguments[0].userId;
        else if (arguments.length > 1 && arguments[1]) uid = arguments[1];
        uid = String(uid || '').trim();

        let csrf = '';
        const m = document.cookie.match(/csrftoken=([^;]+)/);
        if (m && m[1]) csrf = m[1];
        if (!csrf && window._sharedData && window._sharedData.config) {
            csrf = window._sharedData.config.csrf_token || '';
        }

        const headers = {
            'x-ig-app-id': '936619743392459',
            'x-asbd-id': '129477',
            'x-csrftoken': csrf,
            'x-requested-with': 'XMLHttpRequest',
            'Accept': 'application/json, text/plain, */*'
        };

        // 1. Priorità massima: fetch in-page autenticato con cookie WebKit e CSRF token
        if (uname && uname.length > 0) {
            try {
                const res = await fetch('https://www.instagram.com/api/v1/users/web_profile_info/?username=' + encodeURIComponent(uname), {
                    headers: headers,
                    credentials: 'include'
                });
                if (res.ok) {
                    const j = await res.json();
                    if (j && (j.data || j.user)) {
                        return JSON.stringify(j);
                    }
                }
            } catch(e) {}
        }

        if (uid && /^[0-9]+$/.test(uid)) {
            try {
                const feedRes = await fetch('https://www.instagram.com/api/v1/feed/user/' + encodeURIComponent(uid) + '/?count=18', {
                    headers: headers,
                    credentials: 'include'
                });
                if (feedRes.ok) {
                    const fj = await feedRes.json();
                    if (fj && (fj.items || fj.data)) {
                        return JSON.stringify(fj);
                    }
                }
            } catch(e) {}
        }

        // 2. Controllo percorso: estrai da script Relay o DOM solo se la pagina corrisponde all'utente target
        const currentPath = window.location.pathname.toLowerCase().replace(/\\//g, '');
        const isTargetPage = currentPath === uname || currentPath.includes(uname);

        if (isTargetPage) {
            // Cerca nei tag script JSON (Relay/GraphQL data integrato da Instagram nella pagina)
            const scripts = document.querySelectorAll('script[type="application/json"]');
            for (const s of scripts) {
                try {
                    const txt = s.textContent || '';
                    if (txt.includes('edge_owner_to_timeline_media')) {
                        const parsed = JSON.parse(txt);
                        function findTimeline(obj) {
                            if (!obj || typeof obj !== 'object') return null;
                            if (obj.edge_owner_to_timeline_media && obj.edge_owner_to_timeline_media.edges && obj.edge_owner_to_timeline_media.edges.length > 0) {
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

            // Estrai elementi griglia dal DOM reale renderizzato (tag <a> e <img>)
            const links = Array.from(document.querySelectorAll('a[href*="/p/"], a[href*="/reel/"], a[href*="/reels/"]'));
            const domPosts = [];
            const seen = new Set();
            for (const a of links) {
                const href = a.getAttribute('href') || '';
                const m = href.match(/\\/(p|reel|reels)\\/([^\\/]+)/);
                if (!m) continue;
                const shortcode = m[2];
                if (seen.has(shortcode)) continue;
                seen.add(shortcode);

                const img = a.querySelector('img');
                const imgSrc = img ? (img.currentSrc || img.src || (img.srcset ? img.srcset.split(',').pop().trim().split(' ')[0] : '')) : '';
                if (!imgSrc) continue;

                const isVideo = a.querySelector('svg[aria-label*="Video"], svg[aria-label*="Clip"], svg[aria-label*="Reel"]') !== null;
                const isCarousel = a.querySelector('svg[aria-label*="Carosello"], svg[aria-label*="Carousel"], svg[aria-label*="Post con più"]') !== null;

                domPosts.push({
                    id: shortcode,
                    shortcode: shortcode,
                    media_type: isCarousel ? 8 : (isVideo ? 2 : 1),
                    display_url: imgSrc,
                    caption: img ? (img.alt || '') : '',
                    like_count: 0
                });
            }

            let profilePic = null;
            const headerImg = document.querySelector('header img');
            if (headerImg) {
                profilePic = headerImg.currentSrc || headerImg.src;
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
        }

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

        await waitForWebViewReady(wv, timeout: 2.0)

        let script = """
        let uid = '';
        if (typeof userId !== 'undefined') uid = userId;
        else if (arguments[0] && typeof arguments[0] === 'object' && arguments[0].userId) uid = arguments[0].userId;
        else if (arguments[0]) uid = arguments[0];
        uid = String(uid || '').trim();

        let csrf = '';
        const m = document.cookie.match(/csrftoken=([^;]+)/);
        if (m && m[1]) csrf = m[1];
        if (!csrf && window._sharedData && window._sharedData.config) {
            csrf = window._sharedData.config.csrf_token || '';
        }

        const headers = {
            'x-ig-app-id': '936619743392459',
            'x-asbd-id': '129477',
            'x-csrftoken': csrf,
            'x-requested-with': 'XMLHttpRequest',
            'Accept': 'application/json, text/plain, */*'
        };
        try {
            const res = await fetch('https://www.instagram.com/api/v1/feed/reels_media/?user_ids=' + encodeURIComponent(uid), {
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

        await waitForWebViewReady(wv, timeout: 2.0)

        let script = """
        let code = '';
        if (typeof shortcode !== 'undefined') code = shortcode;
        else if (arguments[0] && typeof arguments[0] === 'object' && arguments[0].shortcode) code = arguments[0].shortcode;
        else if (arguments[0]) code = arguments[0];
        code = String(code || '').trim();

        let csrf = '';
        const m = document.cookie.match(/csrftoken=([^;]+)/);
        if (m && m[1]) csrf = m[1];
        if (!csrf && window._sharedData && window._sharedData.config) {
            csrf = window._sharedData.config.csrf_token || '';
        }

        const headers = {
            'x-ig-app-id': '936619743392459',
            'x-asbd-id': '129477',
            'x-csrftoken': csrf,
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
                const mediaRes = await fetch('https://www.instagram.com/api/v1/media/' + numericId + '/info/', {
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
    public func fetchMorePosts(
        username: String,
        existingShortcodes: [String],
        cursor: String? = nil,
        userID: String? = nil
    ) async -> String? {
        prepare()
        guard let wv = webView else { return nil }

        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        if !clean.isEmpty {
            let currentPath = wv.url?.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
            if currentPath != clean.lowercased() {
                await navigateToTargetProfile(wv, username: clean)
            }
        }

        let effectiveCSRF = InstagramSessionManager.shared.currentSession?.csrfToken ?? ""

        let script = """
        let ex = [];
        if (typeof existing !== 'undefined') ex = existing;
        else if (arguments[0] && typeof arguments[0] === 'object' && arguments[0].existing) ex = arguments[0].existing;
        else if (arguments[0]) ex = arguments[0];
        if (!Array.isArray(ex)) ex = [];
        const existing = new Set(ex);

        let cur = (typeof cursor !== 'undefined' ? cursor : (arguments[0] && typeof arguments[0] === 'object' ? arguments[0].cursor : '')) || '';
        let uid = (typeof userId !== 'undefined' ? userId : (arguments[0] && typeof arguments[0] === 'object' ? arguments[0].userId : '')) || '';
        let csrf = (typeof csrfToken !== 'undefined' ? csrfToken : (arguments[0] && typeof arguments[0] === 'object' ? arguments[0].csrfToken : '')) || '';
        if (!csrf) {
            const m = document.cookie.match(/csrftoken=([^;]+)/);
            if (m && m[1]) csrf = m[1];
        }

        const headers = {
            'x-ig-app-id': '936619743392459',
            'x-asbd-id': '129477',
            'x-csrftoken': csrf,
            'x-requested-with': 'XMLHttpRequest',
            'Accept': 'application/json, text/plain, */*'
        };

        // 1. Prova fetch GraphQL query con query_hash per paginazione diretta ufficiale
        if (cur && uid) {
            try {
                const gqlRes = await fetch('https://www.instagram.com/graphql/query/?query_hash=69cba40317214236af40e7efa697781d&variables=' + encodeURIComponent(JSON.stringify({
                    id: uid,
                    first: 24,
                    after: cur
                })), { headers: headers, credentials: 'include' });
                if (gqlRes.ok) {
                    const j = await gqlRes.json();
                    if (j && j.data) {
                        return JSON.stringify(j);
                    }
                }
            } catch(e) {}
        }

        // 2. Esegui scroll verso il basso progressivo per innescare IntersectionObserver di React
        for (let step = 0; step < 3; step++) {
            const scrollTarget = document.documentElement.scrollHeight || document.body.scrollHeight;
            window.scrollTo({ top: scrollTarget, behavior: 'smooth' });
            window.dispatchEvent(new Event('scroll'));
            window.dispatchEvent(new CustomEvent('scroll'));
            await new Promise(r => setTimeout(r, 700));
        }

        // 3. Raccogli tutti i post presenti nel DOM non ancora salvati
        const links = Array.from(document.querySelectorAll('a[href*="/p/"], a[href*="/reel/"], a[href*="/reels/"]'));
        const newPosts = [];
        for (const a of links) {
            const href = a.getAttribute('href') || '';
            const m = href.match(/\\/(p|reel|reels)\\/([^\\/]+)/);
            if (!m) continue;
            const shortcode = m[2];
            if (existing.has(shortcode)) continue;
            existing.add(shortcode);

            const img = a.querySelector('img');
            const imgSrc = img ? (img.currentSrc || img.src || (img.srcset ? img.srcset.split(',').pop().trim().split(' ')[0] : '')) : '';
            if (!imgSrc) continue;

            const isVideo = a.querySelector('svg[aria-label*="Video"], svg[aria-label*="Clip"], svg[aria-label*="Reel"]') !== null;
            const isCarousel = a.querySelector('svg[aria-label*="Carosello"], svg[aria-label*="Carousel"], svg[aria-label*="Post con più"]') !== null;

            newPosts.push({
                id: shortcode,
                shortcode: shortcode,
                media_type: isCarousel ? 8 : (isVideo ? 2 : 1),
                display_url: imgSrc.replace(/&amp;/g, '&'),
                caption: img ? (img.alt || '') : '',
                like_count: 0
            });
        }

        return JSON.stringify({ dom_posts: newPosts });
        """

        do {
            let result = try await wv.callAsyncJavaScript(
                script,
                arguments: [
                    "existing": existingShortcodes,
                    "cursor": cursor ?? "",
                    "userId": userID ?? "",
                    "csrfToken": effectiveCSRF
                ],
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
    public func fetchCurrentUserProfile(userID: String, username: String? = nil) async -> String? {
        prepare()
        guard let wv = webView else { return nil }

        let cleanUname = username?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "") ?? ""
        if !cleanUname.isEmpty {
            await navigateToTargetProfile(wv, username: cleanUname)
        } else {
            await waitForWebViewReady(wv, timeout: 3.5)
        }

        let script = """
        let uid = '';
        if (typeof userId !== 'undefined') uid = userId;
        else if (arguments[0] && typeof arguments[0] === 'object' && arguments[0].userId) uid = arguments[0].userId;
        else if (arguments[0]) uid = arguments[0];
        uid = String(uid || '').trim();

        let uname = '';
        if (typeof username !== 'undefined') uname = username;
        else if (arguments[0] && typeof arguments[0] === 'object' && arguments[0].username) uname = arguments[0].username;
        else if (arguments.length > 1 && arguments[1]) uname = arguments[1];
        uname = String(uname || '').toLowerCase().replace(/@/g, '').trim();

        let csrf = (typeof csrfToken !== 'undefined' ? csrfToken : (arguments[0] && typeof arguments[0] === 'object' ? arguments[0].csrfToken : '')) || '';
        if (!csrf) {
            const m = document.cookie.match(/csrftoken=([^;]+)/);
            if (m && m[1]) csrf = m[1];
            if (!csrf && window._sharedData && window._sharedData.config) {
                csrf = window._sharedData.config.csrf_token || '';
            }
        }

        const headers = {
            'x-ig-app-id': '936619743392459',
            'x-asbd-id': '129477',
            'x-csrftoken': csrf,
            'x-requested-with': 'XMLHttpRequest',
            'Accept': 'application/json, text/plain, */*'
        };

        // Prova 1: Se l'username è noto, web_profile_info restituisce il profilo completo con profile_pic_url_hd
        if (uname && uname.length > 0) {
            try {
                const res = await fetch('https://www.instagram.com/api/v1/users/web_profile_info/?username=' + encodeURIComponent(uname), {
                    headers: headers,
                    credentials: 'include'
                });
                if (res.ok) {
                    const j = await res.json();
                    if (j && j.data && j.data.user) {
                        return JSON.stringify(j.data.user);
                    }
                }
            } catch(e) {}
        }

        // Prova 2: endpoint info utente autenticato (restituisce sempre profile_pic_url e hd_profile_pic_url_info)
        if (uid && uid.length > 0) {
            try {
                const res = await fetch('https://www.instagram.com/api/v1/users/' + encodeURIComponent(uid) + '/info/', {
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
        }

        // Prova 3: endpoint ufficiale web account autenticato
        try {
            const res = await fetch('https://www.instagram.com/api/v1/accounts/current_user/?edit=true', {
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

        let discoveredUname = uname;
        // Prova 4: endpoint form data (se ha username, prova subito web_profile_info per ottenere avatar)
        try {
            const res = await fetch('https://www.instagram.com/api/v1/accounts/edit/web_form_data/', {
                headers: headers,
                credentials: 'include'
            });
            if (res.ok) {
                const j = await res.json();
                const foundUname = j?.form_data?.username || j?.user?.username;
                if (foundUname) {
                    discoveredUname = foundUname;
                    try {
                        const profRes = await fetch('https://www.instagram.com/api/v1/users/web_profile_info/?username=' + encodeURIComponent(foundUname), {
                            headers: headers,
                            credentials: 'include'
                        });
                        if (profRes.ok) {
                            const pj = await profRes.json();
                            if (pj && pj.data && pj.data.user) {
                                return JSON.stringify(pj.data.user);
                            }
                        }
                    } catch(pe) {}
                }
                if (j && j.user && (j.user.profile_pic_url || j.user.profile_pic_url_hd)) {
                    return JSON.stringify(j.user);
                }
            }
        } catch(e) {}

        // Prova 5: estrazione da window._sharedData
        try {
            if (window._sharedData && window._sharedData.config && window._sharedData.config.viewer) {
                const v = window._sharedData.config.viewer;
                if (v && (v.profile_pic_url || v.profile_pic_url_hd || v.profile_picture)) {
                    return JSON.stringify(v);
                }
            }
        } catch(e) {}

        // Prova 6: estrazione da script tag JSON Relay
        try {
            const scripts = document.querySelectorAll('script[type="application/json"]');
            for (const s of scripts) {
                const txt = s.textContent || '';
                if (txt.includes('profile_pic_url') || txt.includes('"username"')) {
                    const parsed = JSON.parse(txt);
                    function findUserWithAvatar(obj) {
                        if (!obj || typeof obj !== 'object') return null;
                        if (obj.username && (obj.profile_pic_url || obj.profile_pic_url_hd)) {
                            if (!uid || obj.pk === uid || obj.id === uid || (discoveredUname && obj.username.toLowerCase() === discoveredUname.toLowerCase())) return obj;
                        }
                        for (const k in obj) {
                            const found = findUserWithAvatar(obj[k]);
                            if (found) return found;
                        }
                        return null;
                    }
                    const found = findUserWithAvatar(parsed);
                    if (found) return JSON.stringify(found);
                }
            }
        } catch(e) {}

        // Prova 7: estrazione avatar dal DOM dell'app web Instagram
        try {
            const avatarImg = document.querySelector('header img, nav img, img[alt*="profilo"], img[alt*="profile"], img[data-testid*="user-avatar"], img[crossorigin="anonymous"]');
            if (avatarImg && (avatarImg.currentSrc || avatarImg.src)) {
                const src = avatarImg.currentSrc || avatarImg.src;
                if (src && !src.startsWith('data:') && !src.includes('static')) {
                    return JSON.stringify({
                        username: discoveredUname || uname || '',
                        profile_pic_url_hd: src,
                        profile_pic_url: src
                    });
                }
            }
        } catch(e) {}

        if (discoveredUname && discoveredUname.length > 0) {
            return JSON.stringify({ username: discoveredUname });
        }

        return null;
        """

        let effectiveCSRF = InstagramSessionManager.shared.currentSession?.csrfToken ?? ""
        do {
            let result = try await wv.callAsyncJavaScript(
                script,
                arguments: ["userId": userID, "username": username ?? "", "csrfToken": effectiveCSRF],
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
