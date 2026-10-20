import Foundation

/// Modello che rappresenta un utente di Instagram
public struct InstagramUser: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let username: String
    public let fullName: String
    public let profilePicURL: URL?
    public let isVerified: Bool
    public let isPrivate: Bool
    public let mediaCount: Int?

    public init(
        id: String,
        username: String,
        fullName: String = "",
        profilePicURL: URL? = nil,
        isVerified: Bool = false,
        isPrivate: Bool = false,
        mediaCount: Int? = nil
    ) {
        self.id = id
        self.username = username
        self.fullName = fullName
        self.profilePicURL = profilePicURL
        self.isVerified = isVerified
        self.isPrivate = isPrivate
        self.mediaCount = mediaCount
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: InstagramUser, rhs: InstagramUser) -> Bool {
        lhs.id == rhs.id
    }
}

/// Rappresenta un follower perso con la data e ora esatta della rilevazione
public struct LostFollowerRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let user: InstagramUser
    public let detectedAt: Date

    public init(id: UUID = UUID(), user: InstagramUser, detectedAt: Date = Date()) {
        self.id = id
        self.user = user
        self.detectedAt = detectedAt
    }
}

/// Rappresenta un nuovo follower acquisito con la data e ora esatta della rilevazione
public struct GainedFollowerRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let user: InstagramUser
    public let detectedAt: Date

    public init(id: UUID = UUID(), user: InstagramUser, detectedAt: Date = Date()) {
        self.id = id
        self.user = user
        self.detectedAt = detectedAt
    }
}

