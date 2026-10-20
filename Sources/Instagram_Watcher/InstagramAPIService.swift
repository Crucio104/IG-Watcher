import Foundation

/// Errori specifici dell'API di Instagram in lingua inglese standard
public enum InstagramAPIError: LocalizedError, Sendable {
    case notAuthenticated
    case rateLimited
    case checkpointRequired
    case invalidResponse
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Session expired or invalid. Please log in to Instagram again."
        case .rateLimited:
            return "Instagram has temporarily limited requests. Please wait a few minutes."
        case .checkpointRequired:
            return "Instagram security verification required. Open the official app to confirm identity."
        case .invalidResponse:
            return "Invalid response from Instagram. Check your internet connection."
        case .networkError(let description):
            return "Connection error: \(description)"
        }
    }
}

/// Servizio che recupera follower e seguiti in modo protetto con pause umane
public final class InstagramAPIService: Sendable {
    public static let shared = InstagramAPIService()

    private let rateLimiter = AntiBanRateLimiter.shared

    private init() {}

    /// Recupera i dettagli del profilo dell'utente autenticato (username, nome, avatar)
    public func fetchCurrentUserProfile(session: InstagramSession) async throws -> InstagramUser {
        let liveCookies = await InstagramSessionManager.shared.getLiveCookieHeader()
        let endpoints = [
            "https://www.instagram.com/api/v1/users/\(session.userID)/info/",
            "https://i.instagram.com/api/v1/users/\(session.userID)/info/"
        ]

        let lastError: Error = InstagramAPIError.invalidResponse

        for urlStr in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(liveCookies.isEmpty ? session.cookieHeader : liveCookies, forHTTPHeaderField: "Cookie")
            request.setValue(session.csrfToken, forHTTPHeaderField: "x-csrftoken")
            request.setValue("936619743392459", forHTTPHeaderField: "x-ig-app-id")
            request.setValue("129477", forHTTPHeaderField: "x-asbd-id")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "x-requested-with")
            request.setValue(session.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")
            request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
            request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
            request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let userDict = json["user"] as? [String: Any],
                  let username = userDict["username"] as? String else {
                continue
            }

            let fullName = userDict["full_name"] as? String ?? ""
            let isVerified = userDict["is_verified"] as? Bool ?? false
            let isPrivate = userDict["is_private"] as? Bool ?? false
            let picURLString = userDict["profile_pic_url"] as? String
            let picURL = picURLString != nil ? URL(string: picURLString!) : nil

            return InstagramUser(
                id: session.userID,
                username: username,
                fullName: fullName,
                profilePicURL: picURL,
                isVerified: isVerified,
                isPrivate: isPrivate
            )
        }

        throw lastError
    }

    /// Recupera la lista completa dei Follower dell'utente autenticato
    public func fetchFollowers(
        session: InstagramSession,
        onProgress: @escaping @Sendable (Int, String) -> Void
    ) async throws -> [InstagramUser] {
        return try await fetchUserList(
            endpoint: "followers",
            session: session,
            onProgress: onProgress
        )
    }

    /// Recupera la lista completa delle persone seguite (Following)
    public func fetchFollowing(
        session: InstagramSession,
        onProgress: @escaping @Sendable (Int, String) -> Void
    ) async throws -> [InstagramUser] {
        return try await fetchUserList(
            endpoint: "following",
            session: session,
            onProgress: onProgress
        )
    }

    // MARK: - Algoritmo di Paginazione Umana con Anti-Ban
    private func fetchUserList(
        endpoint: String,
        session: InstagramSession,
        onProgress: @escaping @Sendable (Int, String) -> Void
    ) async throws -> [InstagramUser] {
        var allUsers: [InstagramUser] = []
        var nextMaxID: String? = nil
        var hasMore = true
        var pageIndex = 1
        let label = endpoint == "followers" ? "followers" : "following"

        while hasMore {
            // 🛡️ Pausa Anti-Ban tra le pagine consecutive (la pagina 1 parte all'istante!)
            if pageIndex > 1 {
                let currentCount = allUsers.count
                try await rateLimiter.waitHumanDelay(pageIndex: pageIndex) { status in
                    onProgress(currentCount, "\(status) (\(currentCount) \(label))")
                }
            } else {
                onProgress(0, "Fetching \(label) (Page 1)...")
            }

            var urlComponents = URLComponents(string: "https://www.instagram.com/api/v1/friendships/\(session.userID)/\(endpoint)/")!
            var queryItems = [
                URLQueryItem(name: "count", value: "50"),
                URLQueryItem(name: "search_surface", value: "follow_list_page")
            ]
            if let maxID = nextMaxID {
                queryItems.append(URLQueryItem(name: "max_id", value: maxID))
            }
            urlComponents.queryItems = queryItems

            guard let url = urlComponents.url else { break }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
            request.setValue(session.csrfToken, forHTTPHeaderField: "x-csrftoken")
            request.setValue("936619743392459", forHTTPHeaderField: "x-ig-app-id")
            request.setValue("129477", forHTTPHeaderField: "x-asbd-id")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "x-requested-with")
            request.setValue(session.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")
            request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
            request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
            request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw InstagramAPIError.invalidResponse
            }

            // Rileva reindirizzamento alla pagina di login
            if let finalURL = httpResponse.url?.absoluteString, finalURL.contains("accounts/login") {
                throw InstagramAPIError.notAuthenticated
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw InstagramAPIError.notAuthenticated
            }

            if httpResponse.statusCode == 429 {
                let currentCount = allUsers.count
                try await rateLimiter.handleRateLimitWarning(retryCount: 1) { status in
                    onProgress(currentCount, status)
                }
                throw InstagramAPIError.rateLimited
            }

            // Rileva eventuale risposta HTML anziché JSON (es. checkpoint)
            if let str = String(data: data, encoding: .utf8), (str.contains("<!DOCTYPE html") || str.contains("<html")) {
                if str.contains("checkpoint") {
                    throw InstagramAPIError.checkpointRequired
                }
                throw InstagramAPIError.notAuthenticated
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw InstagramAPIError.invalidResponse
            }

            // Parsing della risposta JSON di Instagram
            let decoded = try parseFriendshipResponse(data: data)
            allUsers.append(contentsOf: decoded.users)
            nextMaxID = decoded.nextMaxID
            hasMore = decoded.hasMore && (nextMaxID != nil) && (!decoded.users.isEmpty)

            onProgress(allUsers.count, "Downloaded \(allUsers.count) \(label) (Page \(pageIndex))...")
            pageIndex += 1
        }

        return allUsers
    }

    // MARK: - Decodifica della risposta JSON
    private struct RawResponse {
        let users: [InstagramUser]
        let nextMaxID: String?
        let hasMore: Bool
    }

    private func parseFriendshipResponse(data: Data) throws -> RawResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstagramAPIError.invalidResponse
        }

        // Controllo se Instagram ha risposto con uno status di errore JSON
        if let status = json["status"] as? String, status == "fail" {
            let message = json["message"] as? String ?? ""
            if message.contains("login_required") {
                throw InstagramAPIError.notAuthenticated
            } else if message.contains("checkpoint") {
                throw InstagramAPIError.checkpointRequired
            } else if message.contains("wait") || message.contains("rate") {
                throw InstagramAPIError.rateLimited
            } else {
                throw InstagramAPIError.networkError(message)
            }
        }

        guard let usersArray = json["users"] as? [[String: Any]] else {
            throw InstagramAPIError.invalidResponse
        }

        var users: [InstagramUser] = []
        for item in usersArray {
            guard let pk = item["pk"] ?? item["id"],
                  let username = item["username"] as? String else {
                continue
            }
            let idString = "\(pk)"
            let fullName = item["full_name"] as? String ?? ""
            let isVerified = item["is_verified"] as? Bool ?? false
            let isPrivate = item["is_private"] as? Bool ?? false
            let picURLString = item["profile_pic_url"] as? String
            let picURL = picURLString != nil ? URL(string: picURLString!) : nil
            let mediaCount = item["media_count"] as? Int

            let user = InstagramUser(
                id: idString,
                username: username,
                fullName: fullName,
                profilePicURL: picURL,
                isVerified: isVerified,
                isPrivate: isPrivate,
                mediaCount: mediaCount
            )
            users.append(user)
        }

        let nextMaxID = (json["next_max_id"] as? String) ?? (json["next_max_id"] as? Int).map { "\($0)" }
        let hasMore = (json["has_more"] as? Bool) ?? (json["big_list"] as? Bool) ?? (nextMaxID != nil)

        return RawResponse(users: users, nextMaxID: nextMaxID, hasMore: hasMore)
    }
}
