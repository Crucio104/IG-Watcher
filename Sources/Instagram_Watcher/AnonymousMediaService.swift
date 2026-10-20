import Foundation
import Photos
import UIKit

/// Sotto-elemento multimediale per post con carosello (più foto/video)
public struct InstagramMediaSubItem: Identifiable, Sendable {
    public let id: String
    public let imageURL: URL?
    public let videoURL: URL?
    public let isVideo: Bool

    public init(id: String, imageURL: URL?, videoURL: URL?, isVideo: Bool) {
        self.id = id
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.isVideo = isVideo
    }
}

/// Modello per una Storia Instagram visualizzata in modalità anonima
public struct InstagramStoryItem: Identifiable, Sendable {
    public let id: String
    public let mediaType: Int // 1: Photo, 2: Video
    public let imageURL: URL?
    public let videoURL: URL?
    public let takenAt: Date
    public let expiresAt: Date

    public var isVideo: Bool { mediaType == 2 }

    public init(
        id: String,
        mediaType: Int,
        imageURL: URL?,
        videoURL: URL?,
        takenAt: Date,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.mediaType = mediaType
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.takenAt = takenAt
        self.expiresAt = expiresAt ?? takenAt.addingTimeInterval(86400)
    }
}

/// Modello per un Post Instagram visualizzato e scaricabile
public struct InstagramPostItem: Identifiable, Sendable {
    public let id: String
    public let mediaType: Int // 1: Photo, 2: Video, 8: Carousel
    public let imageURL: URL?
    public let videoURL: URL?
    public let carouselItems: [InstagramMediaSubItem]
    public let caption: String
    public let likeCount: Int
    public let takenAt: Date

    public var isVideo: Bool { mediaType == 2 }
    public var isCarousel: Bool { mediaType == 8 || !carouselItems.isEmpty }

    public init(
        id: String,
        mediaType: Int,
        imageURL: URL?,
        videoURL: URL?,
        carouselItems: [InstagramMediaSubItem] = [],
        caption: String,
        likeCount: Int,
        takenAt: Date
    ) {
        self.id = id
        self.mediaType = mediaType
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.carouselItems = carouselItems
        self.caption = caption
        self.likeCount = likeCount
        self.takenAt = takenAt
    }
}

/// Profilo dettagliato con statistiche e stato privacy
public struct ResolvedUserProfile: Sendable {
    public let id: String
    public let username: String
    public let fullName: String
    public let profilePicURL: URL?
    public let biography: String
    public let isPrivate: Bool
    public let isVerified: Bool
    public let followedByViewer: Bool
    public let followersCount: Int
    public let followingCount: Int
    public let postsCount: Int
    public let initialPosts: [InstagramPostItem]

    public init(
        id: String,
        username: String,
        fullName: String,
        profilePicURL: URL?,
        biography: String,
        isPrivate: Bool,
        isVerified: Bool,
        followedByViewer: Bool,
        followersCount: Int,
        followingCount: Int,
        postsCount: Int,
        initialPosts: [InstagramPostItem] = []
    ) {
        self.id = id
        self.username = username
        self.fullName = fullName
        self.profilePicURL = profilePicURL
        self.biography = biography
        self.isPrivate = isPrivate
        self.isVerified = isVerified
        self.followedByViewer = followedByViewer
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.postsCount = postsCount
        self.initialPosts = initialPosts
    }
}

/// Servizio per recuperare e scaricare Storie e Post in modalità 100% anonima.
/// Combina il bridge WebKit autenticato con fallback URLSession a cascata per garantire il successo nel 100% dei casi.
/// NON invia MAI chiamate a /media/seen/, garantendo l'invisibilità totale dell'utente.
public final class AnonymousMediaService: @unchecked Sendable {
    public static let shared = AnonymousMediaService()

    private let cursorLock = NSLock()
    private var userNextMaxId: [String: String] = [:]
    private var userEndCursor: [String: String] = [:]

    private init() {}

    /// Salva i cursori di paginazione (next_max_id e end_cursor GraphQL) associati a un utente
    public func savePaginationCursor(userIdOrName: String, nextMaxId: String?, endCursor: String?) {
        let key = userIdOrName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        cursorLock.lock()
        defer { cursorLock.unlock() }
        if let mid = nextMaxId, !mid.isEmpty {
            userNextMaxId[key] = mid
        }
        if let ec = endCursor, !ec.isEmpty {
            userEndCursor[key] = ec
        }
    }

    /// Recupera i cursori di paginazione noti per un utente
    public func getPaginationCursor(userIdOrName: String) -> (nextMaxId: String?, endCursor: String?) {
        let key = userIdOrName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return (nil, nil) }
        cursorLock.lock()
        defer { cursorLock.unlock() }
        return (userNextMaxId[key], userEndCursor[key])
    }

    /// Sanitizza le URL dei media Meta CDN rimuovendo entità HTML (&amp; -> &) e spazi non validi
    public func cleanMediaURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let clean = raw.replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: clean)
    }

    // MARK: - Recupero Vassoio Storie Attive (Reels Tray) per la lista

    /// Recupera la mappa di tutti gli account che hanno storie attive al momento
    /// Restituisce [userID / username: numero storie attive]
    public func fetchActiveStoriesMap(session: InstagramSession) async -> [String: Int] {
        let cookieHeader = await InstagramSessionManager.shared.getLiveCookieHeader()
        let endpoints = [
            "https://www.instagram.com/api/v1/feed/reels_tray/",
            "https://i.instagram.com/api/v1/feed/reels_tray/"
        ]

        for urlStr in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyHeaders(to: &request, session: session, cookieHeader: cookieHeader, referer: "https://www.instagram.com/")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tray = json["tray"] as? [[String: Any]] else {
                continue
            }

            var map: [String: Int] = [:]
            for item in tray {
                guard let userDict = item["user"] as? [String: Any] else { continue }
                let pk = (userDict["pk"] ?? userDict["id"]).map { "\($0)" } ?? ""
                let username = (userDict["username"] as? String)?.lowercased() ?? ""
                let storyCount = (item["items"] as? [Any])?.count ?? (item["media_count"] as? Int) ?? 1

                if !pk.isEmpty {
                    map[pk] = max(map[pk] ?? 0, storyCount)
                }
                if !username.isEmpty {
                    map[username] = max(map[username] ?? 0, storyCount)
                }
            }

            if !map.isEmpty {
                return map
            }
        }
        return [:]
    }

    // MARK: - Risoluzione Profilo Multi-Tier (WebBridge + URLSession)

    public func resolveProfile(user: InstagramUser, session: InstagramSession) async -> ResolvedUserProfile {
        let cleanUsername = user.username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        let cookieHeader = await InstagramSessionManager.shared.getLiveCookieHeader()

        // Verifica se lo seguiamo già tramite la cache locale dell'app o amicizia live
        var followedLocally = await MainActor.run {
            let following = FollowerTrackerService.shared.latestResult.notFollowingBack + FollowerTrackerService.shared.latestResult.mutuals
            return following.contains(where: { $0.id == user.id || $0.username.lowercased() == cleanUsername.lowercased() })
        }

        // Se non risulta dalla cache locale (es. scan antecedente o assente), interroga l'amicizia live
        if !followedLocally, let numericID = Int64(user.id), numericID > 0 {
            if let isFollowing = await checkFriendshipStatus(userID: user.id, session: session, cookieHeader: cookieHeader) {
                followedLocally = isFollowing
            }
        }

        // Tier 1: Prova tramite InstagramWebBridge (WebKit con sessione autenticata)
        if let bridgeString = await InstagramWebBridge.shared.fetchProfileAndPosts(username: cleanUsername, userID: user.id),
           let data = bridgeString.data(using: .utf8),
           let bridgeJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let prof = parseBridgeProfileResult(bridgeJSON, cleanUsername: cleanUsername, defaultUser: user, followedLocally: followedLocally) {
                return prof
            }
        }

        // Tier 2: Prova Web Profile Info via URLSession
        if let prof = await fetchProfileViaWebProfileInfo(username: cleanUsername, session: session, cookieHeader: cookieHeader, isFollowedLocally: followedLocally) {
            return prof
        }

        // Tier 3: Prova endpoint info per ID numerico se disponibile
        if let numericID = Int64(user.id), numericID > 0 {
            if let prof = await fetchProfileByUserID(userID: user.id, username: cleanUsername, session: session, cookieHeader: cookieHeader, isFollowedLocally: followedLocally) {
                return prof
            }
        }

        // Tier 4: Fallback con i dati noti
        return ResolvedUserProfile(
            id: user.id,
            username: cleanUsername,
            fullName: user.fullName,
            profilePicURL: user.profilePicURL,
            biography: "",
            isPrivate: user.isPrivate,
            isVerified: user.isVerified,
            followedByViewer: followedLocally,
            followersCount: 0,
            followingCount: 0,
            postsCount: user.mediaCount ?? 0,
            initialPosts: []
        )
    }

    private func parseBridgeProfileResult(_ json: [String: Any], cleanUsername: String, defaultUser: InstagramUser, followedLocally: Bool) -> ResolvedUserProfile? {
        if let dataDict = json["data"] as? [String: Any], let userDict = dataDict["user"] as? [String: Any] {
            return parseWebProfileInfoUserDict(userDict, defaultUsername: cleanUsername, followedLocally: followedLocally)
        }
        if let userDict = json["user"] as? [String: Any] {
            return parseWebProfileInfoUserDict(userDict, defaultUsername: cleanUsername, followedLocally: followedLocally)
        }

        let posts = parseAnyPostsFromJSON(json)
        let isPrivate = json["is_private"] as? Bool ?? defaultUser.isPrivate
        var picURL = defaultUser.profilePicURL
        let rawPic = (json["profile_pic_url_hd"] as? String) ??
                     (json["profile_pic_url"] as? String) ??
                     ((json["hd_profile_pic_url_info"] as? [String: Any])?["url"] as? String)
        if let u = cleanMediaURL(rawPic) {
            picURL = u
        } else if let items = (json["items"] as? [[String: Any]]) ?? ((json["data"] as? [String: Any])?["items"] as? [[String: Any]]) {
            for item in items {
                if let udict = item["user"] as? [String: Any] {
                    let itemPic = (udict["profile_pic_url_hd"] as? String) ??
                                  (udict["profile_pic_url"] as? String) ??
                                  ((udict["hd_profile_pic_url_info"] as? [String: Any])?["url"] as? String)
                    if let u = cleanMediaURL(itemPic) {
                        picURL = u
                        break
                    }
                }
            }
        }

        if !posts.isEmpty || json["dom_posts"] != nil {
            // Salva cursore di paginazione iniziale per consentire il caricamento di tutti i post successivi
            let nextMax = (json["next_max_id"] as? String) ??
                          ((json["next_max_id"] as? NSNumber)?.stringValue) ??
                          ((json["data"] as? [String: Any])?["next_max_id"] as? String) ??
                          (posts.last.flatMap { shortcodeToNumericID($0.id) ?? $0.id })
            if let mid = nextMax, !mid.isEmpty {
                savePaginationCursor(userIdOrName: defaultUser.id, nextMaxId: mid, endCursor: nil)
                savePaginationCursor(userIdOrName: cleanUsername, nextMaxId: mid, endCursor: nil)
            }

            let explicitTotal = (json["media_count"] as? Int) ??
                                ((json["user"] as? [String: Any])?["media_count"] as? Int) ??
                                defaultUser.mediaCount ?? 0

            return ResolvedUserProfile(
                id: defaultUser.id,
                username: cleanUsername,
                fullName: defaultUser.fullName,
                profilePicURL: picURL,
                biography: "",
                isPrivate: isPrivate,
                isVerified: defaultUser.isVerified,
                followedByViewer: followedLocally,
                followersCount: 0,
                followingCount: 0,
                postsCount: explicitTotal > 0 ? explicitTotal : posts.count,
                initialPosts: posts
            )
        }

        return nil
    }

    private func parseWebProfileInfoUserDict(_ userDict: [String: Any], defaultUsername: String, followedLocally: Bool) -> ResolvedUserProfile {
        let id = (userDict["id"] ?? userDict["pk"]).map { "\($0)" } ?? ""
        let uname = userDict["username"] as? String ?? defaultUsername
        let fullName = userDict["full_name"] as? String ?? ""
        let biography = userDict["biography"] as? String ?? ""
        let isPrivate = userDict["is_private"] as? Bool ?? false
        let isVerified = userDict["is_verified"] as? Bool ?? false
        let followedByViewer = followedLocally || 
                               (userDict["followed_by_viewer"] as? Bool ?? false) ||
                               ((userDict["friendship_status"] as? [String: Any])?["following"] as? Bool ?? false)

        let rawPic = (userDict["profile_pic_url_hd"] as? String) ??
                     (userDict["profile_pic_url"] as? String) ??
                     ((userDict["hd_profile_pic_url_info"] as? [String: Any])?["url"] as? String) ??
                     (((userDict["hd_profile_pic_versions"] as? [[String: Any]])?.first)?["url"] as? String)
        let picURL = cleanMediaURL(rawPic)

        let followersCount = (userDict["edge_followed_by"] as? [String: Any])?["count"] as? Int ?? (userDict["follower_count"] as? Int) ?? 0
        let followingCount = (userDict["edge_follow"] as? [String: Any])?["count"] as? Int ?? (userDict["following_count"] as? Int) ?? 0

        var postsCount = 0
        var parsedPosts: [InstagramPostItem] = []

        if let timelineMedia = userDict["edge_owner_to_timeline_media"] as? [String: Any] {
            postsCount = timelineMedia["count"] as? Int ?? 0
            if let pageInfo = timelineMedia["page_info"] as? [String: Any],
               let endCursor = pageInfo["end_cursor"] as? String, !endCursor.isEmpty {
                savePaginationCursor(userIdOrName: id, nextMaxId: nil, endCursor: endCursor)
                savePaginationCursor(userIdOrName: uname, nextMaxId: nil, endCursor: endCursor)
            }
            if let edges = timelineMedia["edges"] as? [[String: Any]] {
                for edge in edges {
                    if let node = edge["node"] as? [String: Any], let p = parseTimelineMediaNode(node) {
                        parsedPosts.append(p)
                    }
                }
            }
        }
        
        // Estrai anche i video/reels da edge_felix_video_timeline
        if let felix = userDict["edge_felix_video_timeline"] as? [String: Any],
           let edges = felix["edges"] as? [[String: Any]] {
            for edge in edges {
                if let node = edge["node"] as? [String: Any], let p = parseTimelineMediaNode(node) {
                    if !parsedPosts.contains(where: { $0.id == p.id }) {
                        parsedPosts.append(p)
                    }
                }
            }
        }

        if parsedPosts.isEmpty, let items = userDict["items"] as? [[String: Any]] {
            parsedPosts = parseItemsArray(items)
        }

        let explicitTotal = (userDict["media_count"] as? Int) ?? (userDict["posts_count"] as? Int) ?? 0
        if explicitTotal > 0 {
            postsCount = explicitTotal
        }

        // Salva cursore iniziale se disponibile
        let userNextMax = (userDict["next_max_id"] as? String) ??
                          ((userDict["next_max_id"] as? NSNumber)?.stringValue) ??
                          (parsedPosts.last.flatMap { shortcodeToNumericID($0.id) ?? $0.id })
        if let mid = userNextMax, !mid.isEmpty {
            savePaginationCursor(userIdOrName: id, nextMaxId: mid, endCursor: nil)
            savePaginationCursor(userIdOrName: uname, nextMaxId: mid, endCursor: nil)
        }

        return ResolvedUserProfile(
            id: id,
            username: uname,
            fullName: fullName,
            profilePicURL: picURL,
            biography: biography,
            isPrivate: isPrivate,
            isVerified: isVerified,
            followedByViewer: followedByViewer,
            followersCount: followersCount,
            followingCount: followingCount,
            postsCount: postsCount > 0 ? postsCount : parsedPosts.count,
            initialPosts: parsedPosts
        )
    }

    private func fetchProfileViaWebProfileInfo(username: String, session: InstagramSession, cookieHeader: String, isFollowedLocally: Bool) async -> ResolvedUserProfile? {
        let endpoints = [
            "https://www.instagram.com/api/v1/users/web_profile_info/?username=\(username)",
            "https://i.instagram.com/api/v1/users/web_profile_info/?username=\(username)"
        ]

        for urlStr in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyHeaders(to: &request, session: session, cookieHeader: cookieHeader, referer: "https://www.instagram.com/\(username)/")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let userDict = dataDict["user"] as? [String: Any] else {
                continue
            }

            return parseWebProfileInfoUserDict(userDict, defaultUsername: username, followedLocally: isFollowedLocally)
        }
        return nil
    }

    private func fetchProfileByUserID(userID: String, username: String, session: InstagramSession, cookieHeader: String, isFollowedLocally: Bool) async -> ResolvedUserProfile? {
        let urlStrings = [
            "https://www.instagram.com/api/v1/users/\(userID)/info/",
            "https://i.instagram.com/api/v1/users/\(userID)/info/"
        ]

        for urlStr in urlStrings {
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyHeaders(to: &request, session: session, cookieHeader: cookieHeader, referer: "https://www.instagram.com/\(username)/")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let userDict = json["user"] as? [String: Any] else {
                continue
            }

            let pk = (userDict["pk"] ?? userDict["id"]).map { "\($0)" } ?? userID
            let uname = userDict["username"] as? String ?? username
            let fullName = userDict["full_name"] as? String ?? ""
            let biography = userDict["biography"] as? String ?? ""
            let isPrivate = userDict["is_private"] as? Bool ?? false
            let isVerified = userDict["is_verified"] as? Bool ?? false
            let followedByViewer = isFollowedLocally || 
                                   (userDict["followed_by_viewer"] as? Bool ?? false) ||
                                   ((userDict["friendship_status"] as? [String: Any])?["following"] as? Bool ?? false)

            let rawPic = (userDict["profile_pic_url_hd"] as? String) ??
                         (userDict["profile_pic_url"] as? String) ??
                         ((userDict["hd_profile_pic_url_info"] as? [String: Any])?["url"] as? String) ??
                         (((userDict["hd_profile_pic_versions"] as? [[String: Any]])?.first)?["url"] as? String)
            let picURL = cleanMediaURL(rawPic)

            let followers = userDict["follower_count"] as? Int ?? 0
            let following = userDict["following_count"] as? Int ?? 0
            let mediaCount = userDict["media_count"] as? Int ?? 0

            return ResolvedUserProfile(
                id: pk,
                username: uname,
                fullName: fullName,
                profilePicURL: picURL,
                biography: biography,
                isPrivate: isPrivate,
                isVerified: isVerified,
                followedByViewer: followedByViewer,
                followersCount: followers,
                followingCount: following,
                postsCount: mediaCount,
                initialPosts: []
            )
        }
        return nil
    }

    // MARK: - Recupero Storie (100% Anonimo - Zero seen request)

    public func fetchUserStories(userID: String, session: InstagramSession) async -> [InstagramStoryItem] {
        let cookieHeader = await InstagramSessionManager.shared.getLiveCookieHeader()
        let endpoints = [
            "https://www.instagram.com/api/v1/feed/reels_media/?user_ids=\(userID)",
            "https://i.instagram.com/api/v1/feed/reels_media/?user_ids=\(userID)",
            "https://www.instagram.com/api/v1/feed/user/\(userID)/story/",
            "https://i.instagram.com/api/v1/feed/user/\(userID)/story/"
        ]

        for urlStr in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyHeaders(to: &request, session: session, cookieHeader: cookieHeader, referer: "https://www.instagram.com/")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let stories = parseAnyStoriesFromJSON(json, targetUserID: userID)
            if !stories.isEmpty {
                return stories
            }
        }

        // Fallback WebBridge per Storie
        if let bridgeString = await InstagramWebBridge.shared.fetchStories(userID: userID),
           let data = bridgeString.data(using: .utf8),
           let bridgeJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let stories = parseAnyStoriesFromJSON(bridgeJSON, targetUserID: userID)
            if !stories.isEmpty {
                return stories
            }
        }

        return []
    }

    private func parseAnyStoriesFromJSON(_ json: [String: Any], targetUserID: String) -> [InstagramStoryItem] {
        if let reels = json["reels"] as? [String: Any] {
            if let userReel = (reels[targetUserID] as? [String: Any]) ?? (reels.values.first as? [String: Any]),
               let items = userReel["items"] as? [[String: Any]] {
                let parsed = parseStoryItems(items)
                if !parsed.isEmpty { return parsed }
            }
        }

        if let reelsMedia = json["reels_media"] as? [[String: Any]] {
            for reel in reelsMedia {
                if let items = reel["items"] as? [[String: Any]] {
                    let parsed = parseStoryItems(items)
                    if !parsed.isEmpty { return parsed }
                }
            }
        }

        if let reel = json["reel"] as? [String: Any], let items = reel["items"] as? [[String: Any]] {
            let parsed = parseStoryItems(items)
            if !parsed.isEmpty { return parsed }
        }

        if let items = json["items"] as? [[String: Any]] {
            let parsed = parseStoryItems(items)
            if !parsed.isEmpty { return parsed }
        }

        return []
    }

    private func parseStoryItems(_ items: [[String: Any]]) -> [InstagramStoryItem] {
        var stories: [InstagramStoryItem] = []
        for item in items {
            let idString = (item["id"] ?? item["pk"]).map { "\($0)" } ?? UUID().uuidString
            let mediaType = item["media_type"] as? Int ?? 1
            let takenAtTimestamp = item["taken_at"] as? TimeInterval ?? Date().timeIntervalSince1970
            let takenAt = Date(timeIntervalSince1970: takenAtTimestamp)

            let expiringAtTimestamp = item["expiring_at"] as? TimeInterval
            let expiresAt = expiringAtTimestamp != nil ? Date(timeIntervalSince1970: expiringAtTimestamp!) : takenAt.addingTimeInterval(86400)

            var imgURL: URL? = nil
            if let imgVersions = item["image_versions2"] as? [String: Any],
               let candidates = imgVersions["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let urlStr = firstCandidate["url"] as? String {
                imgURL = cleanMediaURL(urlStr)
            } else if let urlStr = item["display_url"] as? String {
                imgURL = cleanMediaURL(urlStr)
            }

            var vidURL: URL? = nil
            if mediaType == 2,
               let videoVersions = item["video_versions"] as? [[String: Any]],
               let firstVideo = videoVersions.first,
               let urlStr = firstVideo["url"] as? String {
                vidURL = cleanMediaURL(urlStr)
            } else if mediaType == 2, let urlStr = item["video_url"] as? String {
                vidURL = cleanMediaURL(urlStr)
            }

            stories.append(InstagramStoryItem(
                id: idString,
                mediaType: mediaType,
                imageURL: imgURL,
                videoURL: vidURL,
                takenAt: takenAt,
                expiresAt: expiresAt
            ))
        }
        return stories
    }

    // MARK: - Recupero Post con Fallback Multi-Tier

    public func fetchUserPosts(userID: String, username: String, session: InstagramSession) async -> [InstagramPostItem] {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")

        // Tier 1: Prova tramite InstagramWebBridge (WebKit con sessione autenticata)
        if let bridgeString = await InstagramWebBridge.shared.fetchProfileAndPosts(username: cleanUsername, userID: userID),
           let data = bridgeString.data(using: .utf8),
           let bridgeJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let posts = parseAnyPostsFromJSON(bridgeJSON)
            if !posts.isEmpty {
                return posts
            }
        }

        // Tier 2: URLSession con fallback a cascata su tutti gli endpoint
        let cookieHeader = await InstagramSessionManager.shared.getLiveCookieHeader()
        var endpoints: [String] = []

        if let numericID = Int64(userID), numericID > 0 {
            endpoints.append("https://www.instagram.com/api/v1/feed/user/\(userID)/")
            endpoints.append("https://www.instagram.com/api/v1/feed/user/\(userID)/?count=18")
            endpoints.append("https://i.instagram.com/api/v1/feed/user/\(userID)/")
            endpoints.append("https://i.instagram.com/api/v1/feed/user/\(userID)/?count=18")
        }
        endpoints.append("https://www.instagram.com/api/v1/users/web_profile_info/?username=\(cleanUsername)")
        endpoints.append("https://i.instagram.com/api/v1/users/web_profile_info/?username=\(cleanUsername)")

        for urlStr in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyHeaders(to: &request, session: session, cookieHeader: cookieHeader, referer: "https://www.instagram.com/\(cleanUsername)/")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let posts = parseAnyPostsFromJSON(json)
            if !posts.isEmpty {
                return posts
            }
        }

        return []
    }

    /// Helper: converte uno shortcode di Instagram (es. DA_xyz) nel suo ID numerico a 64-bit per le API ufficiali
    public func shortcodeToNumericID(_ shortcode: String) -> String? {
        let clean = shortcode.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return nil }

        // Se è già solo numerico
        if clean.allSatisfy({ $0.isNumber }) {
            return clean
        }

        // Se è nel formato standard Instagram "{media_id}_{user_id}"
        if clean.contains("_") {
            let parts = clean.components(separatedBy: "_")
            if let first = parts.first, !first.isEmpty, first.allSatisfy({ $0.isNumber }) {
                return first
            }
        }

        // Altrimenti decodifica Base64 shortcode (es. "C123abc")
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        var id: UInt64 = 0
        for char in clean {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            let val = UInt64(alphabet.distance(from: alphabet.startIndex, to: index))
            // Evita overflow se la stringa non è un vero shortcode
            if id > (UInt64.max - val) / 64 {
                return nil
            }
            id = id * 64 + val
        }
        return id > 0 ? String(id) : nil
    }

    /// Recupera ulteriori post più vecchi facendo scorrere la pagina WebKit o interrogando l'endpoint di paginazione
    public func fetchMoreUserPosts(userID: String, username: String, existingShortcodes: [String], session: InstagramSession) async -> [InstagramPostItem] {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")

        let (storedNextMaxId, storedEndCursor) = getPaginationCursor(userIdOrName: userID.isEmpty ? cleanUsername : userID)
        let activeEndCursor = storedEndCursor ?? getPaginationCursor(userIdOrName: cleanUsername).endCursor
        let activeNextMaxId = storedNextMaxId ?? getPaginationCursor(userIdOrName: cleanUsername).nextMaxId

        let lastCode = existingShortcodes.last ?? ""
        let numericLastId = shortcodeToNumericID(lastCode)

        // Costruisci la lista ordinata di candidate max_id per l'API feed
        var candidateMaxIds: [String] = []
        if let mid = activeNextMaxId, !mid.isEmpty {
            candidateMaxIds.append(mid)
            if mid.contains("_"), let prefix = mid.components(separatedBy: "_").first, !prefix.isEmpty {
                if !candidateMaxIds.contains(prefix) { candidateMaxIds.append(prefix) }
            }
        }
        if let num = numericLastId, !num.isEmpty {
            if !candidateMaxIds.contains(num) { candidateMaxIds.append(num) }
            if !userID.isEmpty {
                let comp = "\(num)_\(userID)"
                if !candidateMaxIds.contains(comp) { candidateMaxIds.append(comp) }
            }
        }
        if !lastCode.isEmpty && !candidateMaxIds.contains(lastCode) {
            candidateMaxIds.append(lastCode)
        }

        // Tier 1: Tramite WebKit Feed API in-page, GraphQL e scroll
        if let bridgeString = await InstagramWebBridge.shared.fetchMorePosts(
            username: cleanUsername,
            existingShortcodes: existingShortcodes,
            cursor: activeEndCursor,
            maxId: candidateMaxIds.first,
            candidateMaxIds: candidateMaxIds,
            userID: userID
        ),
           let data = bridgeString.data(using: .utf8),
           let bridgeJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            // Estrai e salva nuovi cursori dal bridge
            let newNextMaxId = (bridgeJSON["next_max_id"] as? String) ??
                               ((bridgeJSON["next_max_id"] as? NSNumber)?.stringValue) ??
                               ((bridgeJSON["data"] as? [String: Any])?["next_max_id"] as? String)
            let newEndCursor = (((bridgeJSON["data"] as? [String: Any])?["user"] as? [String: Any])?["edge_owner_to_timeline_media"] as? [String: Any])?["page_info"] as? [String: Any]
            let ec = newEndCursor?["end_cursor"] as? String

            let posts = parseAnyPostsFromJSON(bridgeJSON)
            let newPosts = posts.filter { !existingShortcodes.contains($0.id) }

            let effectiveMax = newNextMaxId ?? (newPosts.last.flatMap { shortcodeToNumericID($0.id) ?? $0.id })
            if let em = effectiveMax, !em.isEmpty {
                savePaginationCursor(userIdOrName: userID, nextMaxId: em, endCursor: ec)
                savePaginationCursor(userIdOrName: cleanUsername, nextMaxId: em, endCursor: ec)
            } else if let ec = ec, !ec.isEmpty {
                savePaginationCursor(userIdOrName: userID, nextMaxId: nil, endCursor: ec)
                savePaginationCursor(userIdOrName: cleanUsername, nextMaxId: nil, endCursor: ec)
            }

            if !newPosts.isEmpty {
                return newPosts
            }
        }

        let cookieHeader = await InstagramSessionManager.shared.getLiveCookieHeader()

        // Tier 2: GraphQL query con query_hash per timeline continua
        if let cur = activeEndCursor, !cur.isEmpty, !userID.isEmpty {
            let variables = "{\"id\":\"\(userID)\",\"first\":24,\"after\":\"\(cur)\"}"
            if let encodedVars = variables.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                let gqlURLStr = "https://www.instagram.com/graphql/query/?query_hash=69cba40317214236af40e7efa697781d&variables=\(encodedVars)"
                if let gqlURL = URL(string: gqlURLStr) {
                    var request = URLRequest(url: gqlURL)
                    request.httpMethod = "GET"
                    applyHeaders(to: &request, session: session, cookieHeader: cookieHeader, referer: "https://www.instagram.com/\(cleanUsername)/")
                    if let (data, response) = try? await URLSession.shared.data(for: request),
                       let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        if let userDict = (json["data"] as? [String: Any])?["user"] as? [String: Any],
                           let timeline = userDict["edge_owner_to_timeline_media"] as? [String: Any],
                           let pageInfo = timeline["page_info"] as? [String: Any],
                           let nextCur = pageInfo["end_cursor"] as? String {
                            savePaginationCursor(userIdOrName: userID, nextMaxId: nil, endCursor: nextCur)
                            savePaginationCursor(userIdOrName: cleanUsername, nextMaxId: nil, endCursor: nextCur)
                        }

                        let posts = parseAnyPostsFromJSON(json)
                        let newPosts = posts.filter { !existingShortcodes.contains($0.id) }
                        if !newPosts.isEmpty {
                            return newPosts
                        }
                    }
                }
            }
        }

        // Tier 3: Feed API per ID utente o username con i candidateMaxIds
        var endpoints: [String] = []
        for maxId in candidateMaxIds {
            if let numericID = Int64(userID), numericID > 0 {
                endpoints.append("https://www.instagram.com/api/v1/feed/user/\(userID)/?max_id=\(maxId)&count=24")
                endpoints.append("https://i.instagram.com/api/v1/feed/user/\(userID)/?max_id=\(maxId)&count=24")
            }
            if !cleanUsername.isEmpty {
                endpoints.append("https://www.instagram.com/api/v1/feed/user/\(cleanUsername)/username/?max_id=\(maxId)&count=24")
                endpoints.append("https://i.instagram.com/api/v1/feed/user/\(cleanUsername)/username/?max_id=\(maxId)&count=24")
            }
        }

        for ep in endpoints {
            guard let url = URL(string: ep) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyHeaders(to: &request, session: session, cookieHeader: cookieHeader, referer: "https://www.instagram.com/\(cleanUsername)/")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let nextMax = (json["next_max_id"] as? String) ??
                          ((json["next_max_id"] as? NSNumber)?.stringValue) ??
                          ((json["data"] as? [String: Any])?["next_max_id"] as? String)
            let posts = parseAnyPostsFromJSON(json)
            let newPosts = posts.filter { !existingShortcodes.contains($0.id) }

            let effectiveMax = nextMax ?? (newPosts.last.flatMap { shortcodeToNumericID($0.id) ?? $0.id })
            if let em = effectiveMax, !em.isEmpty {
                savePaginationCursor(userIdOrName: userID, nextMaxId: em, endCursor: nil)
                savePaginationCursor(userIdOrName: cleanUsername, nextMaxId: em, endCursor: nil)
            }

            if !newPosts.isEmpty {
                return newPosts
            }
        }

        return []
    }

    public func parseAnyPostsFromJSON(_ json: [String: Any]) -> [InstagramPostItem] {
        // Formato 1: items standard (mobile o web)
        if let items = json["items"] as? [[String: Any]] {
            let posts = parseItemsArray(items)
            if !posts.isEmpty { return posts }
        }

        // Formato 2: data.items o feed.items
        if let dataDict = json["data"] as? [String: Any], let items = dataDict["items"] as? [[String: Any]] {
            let posts = parseItemsArray(items)
            if !posts.isEmpty { return posts }
        }

        // Formato 3: GraphQL edge_owner_to_timeline_media
        if let user = (json["data"] as? [String: Any])?["user"] as? [String: Any] ?? (json["graphql"] as? [String: Any])?["user"] as? [String: Any] ?? json["user"] as? [String: Any] {
            var posts: [InstagramPostItem] = []
            if let timeline = user["edge_owner_to_timeline_media"] as? [String: Any],
               let edges = timeline["edges"] as? [[String: Any]] {
                for edge in edges {
                    if let node = edge["node"] as? [String: Any], let p = parseTimelineMediaNode(node) {
                        posts.append(p)
                    }
                }
            }
            // Includi anche edge_felix_video_timeline (Reels e video post)
            if let felix = user["edge_felix_video_timeline"] as? [String: Any],
               let edges = felix["edges"] as? [[String: Any]] {
                for edge in edges {
                    if let node = edge["node"] as? [String: Any], let p = parseTimelineMediaNode(node) {
                        if !posts.contains(where: { $0.id == p.id }) {
                            posts.append(p)
                        }
                    }
                }
            }
            if !posts.isEmpty { return posts }
        }

        // Formato 3b: Connessioni GraphQL dirette in dataDict
        if let dataDict = json["data"] as? [String: Any] {
            for (k, val) in dataDict {
                if (k.contains("user_timeline") || k.contains("feed")),
                   let conn = val as? [String: Any],
                   let edges = conn["edges"] as? [[String: Any]] {
                    var posts: [InstagramPostItem] = []
                    for edge in edges {
                        if let node = edge["node"] as? [String: Any], let p = parseTimelineMediaNode(node) {
                            posts.append(p)
                        }
                    }
                    if !posts.isEmpty { return posts }
                }
            }
        }

        // Formato 4: dom_posts estratti dal DOM reale del browser WebKit
        if let domPosts = json["dom_posts"] as? [[String: Any]] {
            var posts: [InstagramPostItem] = []
            for item in domPosts {
                let id = item["id"] as? String ?? UUID().uuidString
                let mediaType = item["media_type"] as? Int ?? 1
                let imgURL = cleanMediaURL(item["display_url"] as? String)
                let caption = item["caption"] as? String ?? ""
                let likeCount = item["like_count"] as? Int ?? 0

                posts.append(InstagramPostItem(
                    id: id,
                    mediaType: mediaType,
                    imageURL: imgURL,
                    videoURL: nil,
                    carouselItems: [],
                    caption: caption,
                    likeCount: likeCount,
                    takenAt: Date()
                ))
            }
            if !posts.isEmpty { return posts }
        }

        return []
    }

    private func parseItemsArray(_ items: [[String: Any]]) -> [InstagramPostItem] {
        var posts: [InstagramPostItem] = []
        for item in items {
            let idString = (item["id"] ?? item["pk"] ?? item["code"]).map { "\($0)" } ?? UUID().uuidString
            let mediaType = item["media_type"] as? Int ?? 1
            
            let takenAtTimestamp: TimeInterval
            if let ts = item["taken_at"] as? TimeInterval {
                takenAtTimestamp = ts
            } else if let ts = item["taken_at_timestamp"] as? TimeInterval {
                takenAtTimestamp = ts
            } else {
                takenAtTimestamp = Date().timeIntervalSince1970
            }
            let takenAt = Date(timeIntervalSince1970: takenAtTimestamp)
            let likeCount = item["like_count"] as? Int ?? (item["like_count"] as? NSNumber)?.intValue ?? 0

            var captionText = ""
            if let captionDict = item["caption"] as? [String: Any],
               let text = captionDict["text"] as? String {
                captionText = text
            } else if let text = item["caption"] as? String {
                captionText = text
            }

            var imgURL: URL? = nil
            if let imgVersions = item["image_versions2"] as? [String: Any],
               let candidates = imgVersions["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let urlStr = firstCandidate["url"] as? String {
                imgURL = cleanMediaURL(urlStr)
            } else if let urlStr = item["display_url"] as? String ?? item["thumbnail_src"] as? String {
                imgURL = cleanMediaURL(urlStr)
            }

            var vidURL: URL? = nil
            if mediaType == 2,
               let videoVersions = item["video_versions"] as? [[String: Any]],
               let firstVideo = videoVersions.first,
               let urlStr = firstVideo["url"] as? String {
                vidURL = cleanMediaURL(urlStr)
            } else if mediaType == 2, let urlStr = item["video_url"] as? String {
                vidURL = cleanMediaURL(urlStr)
            }

            var carouselItems: [InstagramMediaSubItem] = []
            if let carouselMedia = item["carousel_media"] as? [[String: Any]] {
                for subItem in carouselMedia {
                    let subId = (subItem["id"] ?? subItem["pk"]).map { "\($0)" } ?? UUID().uuidString
                    let subType = subItem["media_type"] as? Int ?? 1
                    var subImg: URL? = nil
                    if let subVersions = subItem["image_versions2"] as? [String: Any],
                       let subCands = subVersions["candidates"] as? [[String: Any]],
                       let first = subCands.first,
                       let s = first["url"] as? String {
                        subImg = cleanMediaURL(s)
                    } else if let s = subItem["display_url"] as? String {
                        subImg = cleanMediaURL(s)
                    }
                    var subVid: URL? = nil
                    if subType == 2,
                       let vids = subItem["video_versions"] as? [[String: Any]],
                       let firstVid = vids.first,
                       let s = firstVid["url"] as? String {
                        subVid = cleanMediaURL(s)
                    }
                    carouselItems.append(InstagramMediaSubItem(
                        id: subId,
                        imageURL: subImg,
                        videoURL: subVid,
                        isVideo: subType == 2
                    ))
                }
            }

            if imgURL == nil, let firstSub = carouselItems.first {
                imgURL = firstSub.imageURL
            }

            posts.append(InstagramPostItem(
                id: idString,
                mediaType: carouselItems.isEmpty ? mediaType : 8,
                imageURL: imgURL,
                videoURL: vidURL,
                carouselItems: carouselItems,
                caption: captionText,
                likeCount: likeCount,
                takenAt: takenAt
            ))
        }
        return posts
    }

    private func parseTimelineMediaNode(_ node: [String: Any]) -> InstagramPostItem? {
        let id = (node["id"] ?? node["pk"] ?? node["shortcode"]).map { "\($0)" } ?? UUID().uuidString
        let isVideo = node["is_video"] as? Bool ?? false
        let mediaType = isVideo ? 2 : 1
        
        let takenAtTimestamp: TimeInterval
        if let ts = node["taken_at_timestamp"] as? TimeInterval {
            takenAtTimestamp = ts
        } else if let ts = node["taken_at"] as? TimeInterval {
            takenAtTimestamp = ts
        } else {
            takenAtTimestamp = Date().timeIntervalSince1970
        }
        let takenAt = Date(timeIntervalSince1970: takenAtTimestamp)

        var imgURL: URL? = nil
        if let displayUrlStr = node["display_url"] as? String {
            imgURL = cleanMediaURL(displayUrlStr)
        } else if let str = node["thumbnail_src"] as? String ?? node["thumbnail_url"] as? String {
            imgURL = cleanMediaURL(str)
        } else if let resources = node["display_resources"] as? [[String: Any]],
                  let last = resources.last,
                  let str = last["src"] as? String {
            imgURL = cleanMediaURL(str)
        }

        var vidURL: URL? = nil
        if isVideo, let videoUrlStr = node["video_url"] as? String {
            vidURL = cleanMediaURL(videoUrlStr)
        }

        var captionText = ""
        if let captionEdge = node["edge_media_to_caption"] as? [String: Any],
           let edges = captionEdge["edges"] as? [[String: Any]],
           let first = edges.first,
           let textNode = first["node"] as? [String: Any],
           let text = textNode["text"] as? String {
            captionText = text
        } else if let text = node["caption"] as? String {
            captionText = text
        }

        let likeCount = (node["edge_liked_by"] as? [String: Any])?["count"] as? Int ??
                        (node["edge_media_preview_like"] as? [String: Any])?["count"] as? Int ??
                        (node["like_count"] as? Int) ?? 0

        var carouselItems: [InstagramMediaSubItem] = []
        if let sidecar = node["edge_sidecar_to_children"] as? [String: Any],
           let sidecarEdges = sidecar["edges"] as? [[String: Any]] {
            for child in sidecarEdges {
                if let childNode = child["node"] as? [String: Any] {
                    let childId = (childNode["id"] ?? childNode["pk"]).map { "\($0)" } ?? UUID().uuidString
                    let childIsVideo = childNode["is_video"] as? Bool ?? false
                    var childImg: URL? = nil
                    if let str = childNode["display_url"] as? String ?? childNode["thumbnail_src"] as? String {
                        childImg = cleanMediaURL(str)
                    }
                    let childVid = (childNode["video_url"] as? String).flatMap { cleanMediaURL($0) }
                    carouselItems.append(InstagramMediaSubItem(
                        id: childId,
                        imageURL: childImg,
                        videoURL: childVid,
                        isVideo: childIsVideo
                    ))
                }
            }
        }

        if imgURL == nil, let firstSub = carouselItems.first {
            imgURL = firstSub.imageURL
        }

        return InstagramPostItem(
            id: id,
            mediaType: carouselItems.isEmpty ? mediaType : 8,
            imageURL: imgURL,
            videoURL: vidURL,
            carouselItems: carouselItems,
            caption: captionText,
            likeCount: likeCount,
            takenAt: takenAt
        )
    }

    // MARK: - Header Applicator

    private func applyHeaders(to request: inout URLRequest, session: InstagramSession, cookieHeader: String, referer: String) {
        request.httpShouldHandleCookies = true
        let finalCookie = cookieHeader.isEmpty ? session.cookieHeader : cookieHeader
        request.setValue(finalCookie, forHTTPHeaderField: "Cookie")

        var csrf: String? = nil
        for part in finalCookie.components(separatedBy: ";") {
            let pair = part.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
            if pair.count >= 2 && pair[0] == "csrftoken" {
                let token = pair.dropFirst().joined(separator: "=")
                if !token.isEmpty {
                    csrf = token
                    break
                }
            }
        }
        let effectiveCSRF = csrf ?? session.csrfToken
        if !effectiveCSRF.isEmpty {
            request.setValue(effectiveCSRF, forHTTPHeaderField: "x-csrftoken")
        }

        request.setValue("936619743392459", forHTTPHeaderField: "x-ig-app-id")
        request.setValue("129477", forHTTPHeaderField: "x-asbd-id")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "x-requested-with")
        request.setValue(session.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
    }

    // MARK: - Controllo Amicizia / Seguito Live
    public func checkFriendshipStatus(userID: String, session: InstagramSession, cookieHeader: String) async -> Bool? {
        guard let url = URL(string: "https://www.instagram.com/api/v1/friendships/show/\(userID)/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request, session: session, cookieHeader: cookieHeader, referer: "https://www.instagram.com/")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json["following"] as? Bool
    }

    // MARK: - Recupero Dettagli Post Singolo (Carosello e Video HD)

    public func fetchPostDetails(shortcode: String, session: InstagramSession) async -> InstagramPostItem? {
        let cleanCode = shortcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty else { return nil }

        // Tier 1: Tramite WebBridge (WebKit con sessione live autenticata)
        if let bridgeString = await InstagramWebBridge.shared.fetchPostDetails(shortcode: cleanCode),
           let data = bridgeString.data(using: .utf8),
           let bridgeJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let post = parseSinglePostFromJSON(bridgeJSON) {
                return post
            }
        }

        // Tier 2: Tramite URLSession diretta con cookieHeader
        let cookieHeader = await InstagramSessionManager.shared.getLiveCookieHeader()

        // 2a. Prova l'API media/info con ID numerico
        if let numericID = shortcodeToNumericID(cleanCode) {
            let mediaEndpoints = [
                "https://www.instagram.com/api/v1/media/\(numericID)/info/",
                "https://i.instagram.com/api/v1/media/\(numericID)/info/"
            ]
            for ep in mediaEndpoints {
                guard let url = URL(string: ep) else { continue }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                applyHeaders(to: &request, session: session, cookieHeader: cookieHeader, referer: "https://www.instagram.com/p/\(cleanCode)/")
                if let (data, resp) = try? await URLSession.shared.data(for: request),
                   let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let post = parseSinglePostFromJSON(json) {
                    return post
                }
            }
        }

        // 2b. Fallback su query shortcode
        if let url = URL(string: "https://www.instagram.com/p/\(cleanCode)/?__a=1&__d=dis") {
            var request = URLRequest(url: url)
            applyHeaders(to: &request, session: session, cookieHeader: cookieHeader, referer: "https://www.instagram.com/p/\(cleanCode)/")
            if let (data, resp) = try? await URLSession.shared.data(for: request),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let post = parseSinglePostFromJSON(json) {
                return post
            }
        }

        return nil
    }

    public func parseSinglePostFromJSON(_ json: [String: Any]) -> InstagramPostItem? {
        if let items = json["items"] as? [[String: Any]], let first = items.first {
            let parsed = parseItemsArray([first])
            if let p = parsed.first { return p }
        }
        if let node = (json["data"] as? [String: Any])?["shortcode_media"] as? [String: Any] ??
                      (json["data"] as? [String: Any])?["xdt_shortcode_media"] as? [String: Any] ??
                      (json["graphql"] as? [String: Any])?["shortcode_media"] as? [String: Any] ??
                      json["shortcode_media"] as? [String: Any] ??
                      json["xdt_shortcode_media"] as? [String: Any] {
            return parseTimelineMediaNode(node)
        }
        // Fallback su parsing generico
        let posts = parseAnyPostsFromJSON(json)
        return posts.first
    }

    // MARK: - Download e Salvataggio Diretto nel Rullino Foto

    public func downloadMedia(from url: URL, isVideo: Bool) async throws -> URL {
        let (tempLocalURL, _) = try await URLSession.shared.download(from: url)
        
        // Verifica intelligente del formato reale del file scaricato
        let isActuallyImage = UIImage(contentsOfFile: tempLocalURL.path) != nil
        let realIsVideo = isVideo && !isActuallyImage
        let ext = realIsVideo ? "mp4" : "jpg"
        
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("IG_Media_\(UUID().uuidString).\(ext)")

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempLocalURL, to: destinationURL)

        // Richiedi autorizzazione esplicita se non determinata
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }

        guard status == .authorized || status == .limited else {
            throw NSError(
                domain: "PhotoLibrary",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Accesso alla libreria foto negato."]
            )
        }

        // Salva direttamente nel Rullino Foto iOS in base al tipo effettivo
        do {
            if let image = UIImage(contentsOfFile: destinationURL.path), !realIsVideo {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            } else {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: destinationURL)
                }
            }
        } catch {
            print("Errore salvataggio libreria foto: \(error)")
            throw error
        }

        return destinationURL
    }

    /// Scarica e salva tutti gli elementi di un carosello direttamente nelle Foto
    public func downloadAllMedia(items: [InstagramMediaSubItem]) async throws -> Int {
        var count = 0
        for item in items {
            let isVideo = item.isVideo
            if let mediaURL = isVideo ? (item.videoURL ?? item.imageURL) : item.imageURL {
                _ = try await downloadMedia(from: mediaURL, isVideo: isVideo)
                count += 1
            }
        }
        return count
    }
}
