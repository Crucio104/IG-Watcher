import Foundation

/// Categorie di analisi richieste dall'utente
public enum FollowerCategory: String, CaseIterable, Identifiable, Sendable {
    case notFollowingBack = "Non ti seguono"       // Segui ma non ti seguono
    case fans = "Fan (Non seguiti)"                // Ti seguono ma non li segui
    case mutuals = "Follower Reciproci"            // Vi seguite a vicenda
    case lost = "Follower Persi"                   // Chi ha smesso di seguirti
    case ghosts = "Follower Fantasma"              // Profili inattivi o senza foto

    public var id: String { rawValue }

    public var systemIcon: String {
        switch self {
        case .notFollowingBack: return "person.crop.circle.badge.minus"
        case .fans: return "heart.circle"
        case .mutuals: return "arrow.triangle.2.circlepath.circle"
        case .lost: return "clock.arrow.circlepath"
        case .ghosts: return "eye.slash.circle"
        }
    }

    public var description: String {
        switch self {
        case .notFollowingBack:
            return "Profili che segui, ma che non ricambiano il follow."
        case .fans:
            return "Profili che ti seguono, ma che tu non segui."
        case .mutuals:
            return "Profili con follow reciproco."
        case .lost:
            return "Profili che hanno smesso di seguirti nel tempo."
        case .ghosts:
            return "Follower sospetti inattivi o senza immagine del profilo."
        }
    }
}

/// Risultato complessivo dell'analisi comparativa
public struct ComparisonResult: Codable, Sendable {
    public let timestamp: Date
    public let totalFollowersCount: Int
    public let totalFollowingCount: Int
    public let notFollowingBack: [InstagramUser]
    public let fans: [InstagramUser]
    public let mutuals: [InstagramUser]
    public let lostFollowers: [LostFollowerRecord]
    public let gainedFollowers: [GainedFollowerRecord]
    public let ghostFollowers: [InstagramUser]

    public init(
        timestamp: Date = Date(),
        totalFollowersCount: Int,
        totalFollowingCount: Int,
        notFollowingBack: [InstagramUser],
        fans: [InstagramUser],
        mutuals: [InstagramUser],
        lostFollowers: [LostFollowerRecord],
        gainedFollowers: [GainedFollowerRecord] = [],
        ghostFollowers: [InstagramUser] = []
    ) {
        self.timestamp = timestamp
        self.totalFollowersCount = totalFollowersCount
        self.totalFollowingCount = totalFollowingCount
        self.notFollowingBack = notFollowingBack
        self.fans = fans
        self.mutuals = mutuals
        self.lostFollowers = lostFollowers
        self.gainedFollowers = gainedFollowers
        self.ghostFollowers = ghostFollowers
    }

    /// Tasso di reciprocità: percentuale di chi segui che ti ricambia (0 - 100%)
    public var reciprocityRate: Double {
        guard totalFollowingCount > 0 else { return 100.0 }
        let rate = (Double(mutuals.count) / Double(totalFollowingCount)) * 100.0
        return min(max(rate, 0.0), 100.0)
    }

    /// Rapporto Follower / Seguiti
    public var ratio: Double {
        guard totalFollowingCount > 0 else { return Double(totalFollowersCount) }
        return Double(totalFollowersCount) / Double(totalFollowingCount)
    }

    /// Punteggio salute account (da 0 a 100)
    public var healthScore: Int {
        if totalFollowersCount == 0 && totalFollowingCount == 0 { return 100 }
        let recWeight = reciprocityRate * 0.7
        let ratioScore = min(ratio * 30.0, 30.0)
        return min(max(Int(round(recWeight + ratioScore)), 10), 100)
    }

    public static var empty: ComparisonResult {
        ComparisonResult(
            totalFollowersCount: 0,
            totalFollowingCount: 0,
            notFollowingBack: [],
            fans: [],
            mutuals: [],
            lostFollowers: [],
            gainedFollowers: [],
            ghostFollowers: []
        )
    }
}

/// Snapshot salvato su disco per il tracciamento storico
public struct FollowerSnapshot: Codable, Sendable {
    public let date: Date
    public let followers: [InstagramUser]
    public let following: [InstagramUser]

    public init(date: Date = Date(), followers: [InstagramUser], following: [InstagramUser]) {
        self.date = date
        self.followers = followers
        self.following = following
    }
}
