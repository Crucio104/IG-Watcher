import Foundation
import SwiftUI

/// Servizio per la gestione degli account "Protetti / Preferiti" (Whitelist)
/// Permette all'utente di contrassegnare profili (amici, celebrità, brand) per evitare
/// di smettere di seguirli per sbaglio o per filtrarli dalla vista "Non ti seguono".
@MainActor
public final class WhitelistService: ObservableObject {
    public static let shared = WhitelistService()

    @Published public private(set) var protectedUsers: [String: InstagramUser] = [:]

    private let storageURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = docs.appendingPathComponent("instagram_whitelist.json")
        loadFromDisk()
    }

    public func isProtected(userID: String) -> Bool {
        protectedUsers[userID] != nil
    }

    public func toggleProtection(user: InstagramUser) {
        if isProtected(userID: user.id) {
            protectedUsers.removeValue(forKey: user.id)
        } else {
            protectedUsers[user.id] = user
        }
        saveToDisk()
    }

    private func saveToDisk() {
        let list = Array(protectedUsers.values)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL),
              let list = try? JSONDecoder().decode([InstagramUser].self, from: data) else {
            return
        }
        var dict: [String: InstagramUser] = [:]
        for user in list {
            dict[user.id] = user
        }
        self.protectedUsers = dict
    }
}
