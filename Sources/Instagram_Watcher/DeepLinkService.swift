import UIKit

/// Gestisce l'apertura diretta e sicura dell'app ufficiale di Instagram.
/// Questo metodo azzera il rischio di ban poiché l'azione di follow/unfollow viene eseguita
/// direttamente dall'utente nell'app ufficiale Instagram autenticata da Meta.
@MainActor
public final class DeepLinkService {
    public static let shared = DeepLinkService()

    private init() {}

    /// Apre il profilo dell'utente direttamente nell'app ufficiale Instagram
    /// Se l'app non è installata, effettua il fallback su Safari web.
    /// - Parameter username: Nome utente Instagram (senza '@')
    public func openProfile(username: String) {
        let cleanUsername = username.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        
        guard let appURL = URL(string: "instagram://user?username=\(cleanUsername)"),
              let webURL = URL(string: "https://www.instagram.com/\(cleanUsername)/") else {
            return
        }

        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL, options: [:], completionHandler: nil)
        } else {
            UIApplication.shared.open(webURL, options: [:], completionHandler: nil)
        }
    }
}
