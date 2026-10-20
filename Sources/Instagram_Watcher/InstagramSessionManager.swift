import Foundation
import WebKit

/// Modello delle credenziali di sessione estratte dal browser sicuro
public struct InstagramSession: Codable, Sendable {
    public let userID: String
    public let sessionID: String
    public let csrfToken: String
    public let userAgent: String
    public let rawCookieHeader: String?

    public var cookieHeader: String {
        if let raw = rawCookieHeader, !raw.isEmpty {
            return raw
        }
        return "ds_user_id=\(userID); sessionid=\(sessionID); csrftoken=\(csrfToken);"
    }

    public init(
        userID: String,
        sessionID: String,
        csrfToken: String,
        userAgent: String,
        rawCookieHeader: String? = nil
    ) {
        self.userID = userID
        self.sessionID = sessionID
        self.csrfToken = csrfToken
        self.userAgent = userAgent
        self.rawCookieHeader = rawCookieHeader
    }
}

/// Gestore dello stato di autenticazione e memorizzazione sicura della sessione
@MainActor
public final class InstagramSessionManager: ObservableObject {
    public static let shared = InstagramSessionManager()

    private let sessionKey = "com.instagramwatcher.session"
    private let profileKey = "com.instagramwatcher.user_profile"
    private let usernameKey = "com.instagramwatcher.cached_username"

    @Published public private(set) var currentSession: InstagramSession?
    @Published public private(set) var currentUserProfile: InstagramUser?

    public var isLoggedIn: Bool {
        return currentSession != nil
    }

    private init() {
        loadSession()
    }

    private var cachedCookieHeader: String = ""
    private var lastCookieSync: Date = .distantPast

    /// Restituisce l'header cookie più recente estraendolo direttamente dallo store WebKit se disponibile
    public func getLiveCookieHeader() async -> String {
        let fallbackHeader = currentSession?.cookieHeader ?? ""

        // Se abbiamo già sincronizzato i cookie reali negli ultimi 30 secondi, usa la cache
        if !cachedCookieHeader.isEmpty && Date().timeIntervalSince(lastCookieSync) < 30 {
            return cachedCookieHeader
        }

        // Interroga WKHTTPCookieStore in modo rigorosamente sicuro con timeout di salvaguardia
        let result: String = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let lock = NSLock()
            var hasResumed = false

            let resumeOnce: (String) -> Void = { header in
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: header)
            }

            // Timeout di salvaguardia dopo 650ms: sblocca istantaneamente senza far attendere le API
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                resumeOnce(fallbackHeader)
            }

            DispatchQueue.main.async {
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    let igCookies = cookies.filter { $0.domain.contains("instagram.com") }
                    for cookie in igCookies {
                        HTTPCookieStorage.shared.setCookie(cookie)
                    }

                    // Se il cookie contiene ds_user (il nickname reale), impostalo subito sul profilo se assente!
                    if let dsUser = igCookies.first(where: { $0.name == "ds_user" })?.value, !dsUser.isEmpty {
                        UserDefaults.standard.set(dsUser, forKey: self.usernameKey)
                        if self.currentUserProfile == nil {
                            let user = InstagramUser(
                                id: self.currentSession?.userID ?? "",
                                username: dsUser,
                                fullName: "",
                                profilePicURL: nil,
                                isVerified: false
                            )
                            self.updateUserProfile(user)
                        }
                    }

                    if !igCookies.isEmpty {
                        let header = igCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                        resumeOnce(header)
                    } else {
                        resumeOnce(fallbackHeader)
                    }
                }
            }
        }

        if !result.isEmpty {
            self.cachedCookieHeader = result
            self.lastCookieSync = Date()
            return result
        }

        return fallbackHeader
    }

    /// Salva la sessione estratta dopo il login completato in WKWebView
    public func saveSession(
        userID: String,
        sessionID: String,
        csrfToken: String,
        userAgent: String,
        rawCookieHeader: String? = nil
    ) {
        let session = InstagramSession(
            userID: userID,
            sessionID: sessionID,
            csrfToken: csrfToken,
            userAgent: userAgent,
            rawCookieHeader: rawCookieHeader
        )
        if let encoded = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(encoded, forKey: sessionKey)
        }
        self.currentSession = session
    }

    /// Aggiorna e salva il profilo utente connesso (username, nome, avatar)
    public func updateUserProfile(_ profile: InstagramUser) {
        if profile.profilePicURL == nil, let existingPic = self.currentUserProfile?.profilePicURL {
            let merged = InstagramUser(
                id: profile.id,
                username: profile.username,
                fullName: profile.fullName.isEmpty ? (self.currentUserProfile?.fullName ?? "") : profile.fullName,
                profilePicURL: existingPic,
                isVerified: profile.isVerified || (self.currentUserProfile?.isVerified ?? false),
                isPrivate: profile.isPrivate,
                mediaCount: profile.mediaCount ?? self.currentUserProfile?.mediaCount
            )
            self.currentUserProfile = merged
            if !merged.username.isEmpty {
                UserDefaults.standard.set(merged.username, forKey: usernameKey)
            }
            if let encoded = try? JSONEncoder().encode(merged) {
                UserDefaults.standard.set(encoded, forKey: profileKey)
            }
        } else {
            self.currentUserProfile = profile
            if !profile.username.isEmpty {
                UserDefaults.standard.set(profile.username, forKey: usernameKey)
            }
            if let encoded = try? JSONEncoder().encode(profile) {
                UserDefaults.standard.set(encoded, forKey: profileKey)
            }
        }
    }

    /// Carica la sessione e il profilo precedentemente memorizzati
    public func loadSession() {
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let session = try? JSONDecoder().decode(InstagramSession.self, from: data) {
            self.currentSession = session
        }

        if let profileData = UserDefaults.standard.data(forKey: profileKey),
           let profile = try? JSONDecoder().decode(InstagramUser.self, from: profileData) {
            self.currentUserProfile = profile
        } else if let cachedUname = UserDefaults.standard.string(forKey: usernameKey), !cachedUname.isEmpty, let sid = self.currentSession?.userID {
            self.currentUserProfile = InstagramUser(
                id: sid,
                username: cachedUname,
                fullName: "",
                profilePicURL: nil,
                isVerified: false
            )
        }

        // Se abbiamo una sessione ma il profilo non è ancora salvato, controlla subito i cookie WebKit per ds_user
        if self.currentSession != nil && self.currentUserProfile == nil {
            DispatchQueue.main.async { [weak self] in
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    guard let self = self, self.currentUserProfile == nil else { return }
                    let igCookies = cookies.filter { $0.domain.contains("instagram.com") }
                    if let dsUser = igCookies.first(where: { $0.name == "ds_user" })?.value, !dsUser.isEmpty {
                        UserDefaults.standard.set(dsUser, forKey: self.usernameKey)
                        let user = InstagramUser(
                            id: self.currentSession?.userID ?? "",
                            username: dsUser,
                            fullName: "",
                            profilePicURL: nil,
                            isVerified: false
                        )
                        self.updateUserProfile(user)
                    }
                }
            }
        }
    }

    /// Disconnette l'utente e pulisce cookie e cache di sistema
    public func logout() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
        UserDefaults.standard.removeObject(forKey: profileKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        self.currentSession = nil
        self.currentUserProfile = nil

        // Pulisce i cookie dalla WKWebsiteDataStore
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            let instagramRecords = records.filter { $0.displayName.contains("instagram") }
            dataStore.removeData(ofTypes: dataTypes, for: instagramRecords) {
                print("Cookie Instagram rimossi con successo.")
            }
        }
    }
}
