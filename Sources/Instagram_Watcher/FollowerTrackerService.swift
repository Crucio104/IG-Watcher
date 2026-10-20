import Foundation

/// Modello di esportazione backup per salvataggio e ripristino dati
public struct AppDatabaseBackup: Codable, Sendable {
    public let version: Int
    public let appName: String
    public let createdAt: Date
    public let snapshot: FollowerSnapshot?
    public let lostFollowersHistory: [LostFollowerRecord]
    public let gainedFollowersHistory: [GainedFollowerRecord]?
}

/// Motore di calcolo per il confronto delle relazioni tra follower e seguiti
/// e persistenza sicura dello storico e dei profili nel database locale protetto del dispositivo.
@MainActor
public final class FollowerTrackerService: ObservableObject {
    public static let shared = FollowerTrackerService()

    @Published public private(set) var latestResult: ComparisonResult = .empty
    @Published public private(set) var isAnalyzing: Bool = false
    @Published public private(set) var statusMessage: String = "Ready for analysis"
    @Published public private(set) var lastErrorMessage: String? = nil
    @Published public private(set) var progressCount: Int = 0
    @Published public private(set) var activeStoriesMap: [String: Int] = [:]
    @Published public private(set) var isFetchingActiveStories: Bool = false

    private let snapshotFileURL: URL
    private let lostHistoryFileURL: URL
    private let gainedHistoryFileURL: URL

    private init() {
        // La directory Documents è garantita da iOS per sopravvivere agli aggiornamenti dell'applicazione
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.snapshotFileURL = docs.appendingPathComponent("instagram_last_snapshot.json")
        self.lostHistoryFileURL = docs.appendingPathComponent("instagram_lost_followers_history.json")
        self.gainedHistoryFileURL = docs.appendingPathComponent("instagram_gained_followers_history.json")
        loadCachedData()
    }

    /// Avvia l'analisi completa di Follower e Seguiti con protezione anti-ban
    public func runAnalysis(session: InstagramSession) async {
        guard !isAnalyzing else { return }

        isAnalyzing = true
        lastErrorMessage = nil
        statusMessage = loc("status.secure_connection")
        progressCount = 0

        do {
            // 0. Scarica info anagrafiche del profilo collegato (username, avatar, nome)
            if let profile = try? await InstagramAPIService.shared.fetchCurrentUserProfile(session: session) {
                InstagramSessionManager.shared.updateUserProfile(profile)
            }

            // 1. Scaricamento Follower
            statusMessage = loc("status.fetching_followers")
            let followers = try await InstagramAPIService.shared.fetchFollowers(session: session) { [weak self] count, status in
                Task { @MainActor [weak self] in
                    self?.progressCount = count
                    self?.statusMessage = status
                }
            }

            // 2. Pausa naturale di sicurezza tra le due liste
            statusMessage = loc("status.pause_between")
            try await AntiBanRateLimiter.shared.waitHumanDelay(pageIndex: 2) { [weak self] status in
                Task { @MainActor [weak self] in self?.statusMessage = status }
            }

            // 3. Scaricamento Seguiti (Following)
            statusMessage = loc("status.fetching_following")
            let following = try await InstagramAPIService.shared.fetchFollowing(session: session) { [weak self] count, status in
                Task { @MainActor [weak self] in
                    self?.progressCount = count
                    self?.statusMessage = status
                }
            }

            // 4. Elaborazione comparativa e rilevamento variazioni
            statusMessage = loc("status.processing")
            processLists(currentFollowers: followers, currentFollowing: following)

            statusMessage = loc("status.completed")
            lastErrorMessage = nil

            // 5. Aggiorna in background la mappa delle storie attive
            Task { [weak self] in
                await self?.refreshActiveStories(session: session)
            }
        } catch {
            let errorText = error.localizedDescription
            lastErrorMessage = errorText
            statusMessage = errorText
        }

        isAnalyzing = false
    }

    /// Aggiorna la mappa globale delle storie attive per prioritarizzare gli account nelle liste
    public func refreshActiveStories(session: InstagramSession? = nil) async {
        guard let sess = session ?? InstagramSessionManager.shared.currentSession else { return }
        guard !isFetchingActiveStories else { return }
        isFetchingActiveStories = true
        let map = await AnonymousMediaService.shared.fetchActiveStoriesMap(session: sess)
        if !map.isEmpty {
            self.activeStoriesMap = map
        }
        self.isFetchingActiveStories = false
    }

    /// Esegue il confronto logico tra le due liste e memorizza nel database locale
    private func processLists(currentFollowers: [InstagramUser], currentFollowing: [InstagramUser]) {
        let followerIDs = Set(currentFollowers.map { $0.id })
        let followingIDs = Set(currentFollowing.map { $0.id })

        // Categoria 1: Chi segui ma non ti segue (Non ricambiano)
        let notFollowingBack = currentFollowing.filter { !followerIDs.contains($0.id) }

        // Categoria 2: Chi ti segue ma tu non segui (Fan)
        let fans = currentFollowers.filter { !followingIDs.contains($0.id) }

        // Categoria 3: Follower reciproci (Amici)
        let mutuals = currentFollowers.filter { followingIDs.contains($0.id) }

        // Calcolo accurato dei follower persi e nuovi follower tra uno scan e l'altro
        var allLostRecords = loadLostHistory()
        var allGainedRecords = loadGainedHistory()
        let previousSnapshot = loadPreviousSnapshot()

        if let previous = previousSnapshot, !previous.followers.isEmpty {
            // Salvaguardia: se l'elenco corrente è vuoto a causa di anomalie API, non azzerare o considerali tutti persi
            if currentFollowers.isEmpty && previous.followers.count > 5 {
                print("Salvaguardia anti-anomalia: lista corrente vuota ma snapshot precedente consistente.")
                return
            }

            let currentIDs = Set(currentFollowers.map { $0.id })
            let previousIDs = Set(previous.followers.map { $0.id })

            // 1. Follower Persi: presenti nello scan precedente che ORA non sono più presenti
            let newlyLost = previous.followers.filter { !currentIDs.contains($0.id) }
            if !newlyLost.isEmpty {
                let now = Date()
                let existingLostIDs = Set(allLostRecords.map { $0.user.id })
                let newRecords = newlyLost
                    .filter { !existingLostIDs.contains($0.id) }
                    .map { LostFollowerRecord(user: $0, detectedAt: now) }

                if !newRecords.isEmpty {
                    allLostRecords.insert(contentsOf: newRecords, at: 0)
                    saveLostHistory(allLostRecords)

                    // Invia notifica locale con il nome del profilo perso
                    NotificationService.shared.notifyLostFollowers(newlyLost, detectedAt: now)
                }
            }

            // 2. Nuovi Follower Acquisiti: presenti ORA che non erano presenti nel precedente
            let newlyGained = currentFollowers.filter { !previousIDs.contains($0.id) }
            if !newlyGained.isEmpty {
                let now = Date()
                let existingGainedIDs = Set(allGainedRecords.map { $0.user.id })
                let newGainedRecords = newlyGained
                    .filter { !existingGainedIDs.contains($0.id) }
                    .map { GainedFollowerRecord(user: $0, detectedAt: now) }

                if !newGainedRecords.isEmpty {
                    allGainedRecords.insert(contentsOf: newGainedRecords, at: 0)
                    saveGainedHistory(allGainedRecords)
                }
            }
        }

        // Categoria 4: Follower Fantasma (senza foto o avatar default)
        let ghostFollowers = currentFollowers.filter { user in
            guard let url = user.profilePicURL?.absoluteString else { return true }
            return url.isEmpty || url.contains("44884218_345707102884561") || url.contains("anonymous_user")
        }

        // Salva atomicamente il nuovo snapshot nel database locale
        let newSnapshot = FollowerSnapshot(followers: currentFollowers, following: currentFollowing)
        saveSnapshot(newSnapshot)

        // Aggiorna il risultato pubblicato per l'interfaccia SwiftUI
        self.latestResult = ComparisonResult(
            timestamp: Date(),
            totalFollowersCount: currentFollowers.count,
            totalFollowingCount: currentFollowing.count,
            notFollowingBack: notFollowingBack,
            fans: fans,
            mutuals: mutuals,
            lostFollowers: allLostRecords,
            gainedFollowers: allGainedRecords,
            ghostFollowers: ghostFollowers
        )
    }

    // MARK: - Persistenza Dati Locale (Database su Disco)

    private func saveSnapshot(_ snapshot: FollowerSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: snapshotFileURL, options: .atomic)
        }
    }

    private func loadPreviousSnapshot() -> FollowerSnapshot? {
        guard let data = try? Data(contentsOf: snapshotFileURL),
              let snapshot = try? JSONDecoder().decode(FollowerSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    private func saveLostHistory(_ records: [LostFollowerRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: lostHistoryFileURL, options: .atomic)
        }
    }

    private func loadLostHistory() -> [LostFollowerRecord] {
        guard let data = try? Data(contentsOf: lostHistoryFileURL),
              let records = try? JSONDecoder().decode([LostFollowerRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func saveGainedHistory(_ records: [GainedFollowerRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: gainedHistoryFileURL, options: .atomic)
        }
    }

    private func loadGainedHistory() -> [GainedFollowerRecord] {
        guard let data = try? Data(contentsOf: gainedHistoryFileURL),
              let records = try? JSONDecoder().decode([GainedFollowerRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func loadCachedData() {
        if let snapshot = loadPreviousSnapshot() {
            let lost = loadLostHistory()
            let gained = loadGainedHistory()
            let followerIDs = Set(snapshot.followers.map { $0.id })
            let followingIDs = Set(snapshot.following.map { $0.id })

            let ghosts = snapshot.followers.filter { user in
                guard let url = user.profilePicURL?.absoluteString else { return true }
                return url.isEmpty || url.contains("44884218_345707102884561") || url.contains("anonymous_user")
            }

            self.latestResult = ComparisonResult(
                timestamp: snapshot.date,
                totalFollowersCount: snapshot.followers.count,
                totalFollowingCount: snapshot.following.count,
                notFollowingBack: snapshot.following.filter { !followerIDs.contains($0.id) },
                fans: snapshot.followers.filter { !followingIDs.contains($0.id) },
                mutuals: snapshot.followers.filter { followingIDs.contains($0.id) },
                lostFollowers: lost,
                gainedFollowers: gained,
                ghostFollowers: ghosts
            )
        }
    }

    // MARK: - Backup & Ripristino Dati

    /// Esporta l'intero database in un file JSON per backup permanente
    public func exportBackupFile() -> URL? {
        let backup = AppDatabaseBackup(
            version: 2,
            appName: "IG Watcher",
            createdAt: Date(),
            snapshot: loadPreviousSnapshot(),
            lostFollowersHistory: loadLostHistory(),
            gainedFollowersHistory: loadGainedHistory()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(backup) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateStr = formatter.string(from: Date())
        let fileURL = tempDir.appendingPathComponent("IG_Watcher_Backup_\(dateStr).json")

        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("Errore esportazione backup: \(error)")
            return nil
        }
    }

    /// Ripristina l'intero database da un file JSON di backup
    public func restoreBackup(from fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(AppDatabaseBackup.self, from: data)

        if let snapshot = backup.snapshot {
            saveSnapshot(snapshot)
        }
        saveLostHistory(backup.lostFollowersHistory)
        if let gained = backup.gainedFollowersHistory {
            saveGainedHistory(gained)
        }
        loadCachedData()
    }

    /// Cancella tutti i dati memorizzati nel database locale
    public func clearAllData() {
        try? FileManager.default.removeItem(at: snapshotFileURL)
        try? FileManager.default.removeItem(at: lostHistoryFileURL)
        try? FileManager.default.removeItem(at: gainedHistoryFileURL)
        self.latestResult = .empty
        self.statusMessage = loc("status.ready")
        self.lastErrorMessage = nil
    }
}
