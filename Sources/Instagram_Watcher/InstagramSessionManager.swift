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

    @Published public private(set) var currentSession: InstagramSession?
    @Published public private(set) var currentUserProfile: InstagramUser?

    public var isLoggedIn: Bool {
        return currentSession != nil
    }

    private init() {
        loadSession()
    }

    /// Restituisce l'header cookie più recente estraendolo direttamente dallo store WebKit se disponibile
    public func getLiveCookieHeader() async -> String {
        return await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let igCookies = cookies.filter { $0.domain.contains("instagram.com") }
                for cookie in igCookies {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                if !igCookies.isEmpty {
                    let header = igCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    continuation.resume(returning: header)
                } else {
                    continuation.resume(returning: self.currentSession?.cookieHeader ?? "")
                }
            }
        }
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
        self.currentUserProfile = profile
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: profileKey)
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
        }
    }

    /// Disconnette l'utente e pulisce cookie e cache di sistema
    public func logout() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
        UserDefaults.standard.removeObject(forKey: profileKey)
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
