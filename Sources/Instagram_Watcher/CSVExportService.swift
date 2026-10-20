import Foundation
import UIKit

/// Servizio per generare file CSV ed esportare liste di utenti e variazioni storiche
public struct CSVExportService {
    public static func exportUsersToCSV(users: [InstagramUser], categoryName: String) -> URL? {
        var csv = "Username,Full Name,Is Verified,Is Private,Profile Link\n"
        for user in users {
            let cleanFullName = user.fullName.replacingOccurrences(of: ",", with: " ")
            let link = "https://instagram.com/\(user.username)"
            csv.append("\(user.username),\(cleanFullName),\(user.isVerified ? "Yes" : "No"),\(user.isPrivate ? "Yes" : "No"),\(link)\n")
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("IG_\(categoryName.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970).csv")
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("CSV export error: \(error)")
            return nil
        }
    }

    public static func exportLostFollowersToCSV(records: [LostFollowerRecord]) -> URL? {
        let formatter = ISO8601DateFormatter()
        var csv = "Username,Full Name,Detected Date,Profile Link\n"
        for rec in records {
            let cleanFullName = rec.user.fullName.replacingOccurrences(of: ",", with: " ")
            let dateStr = formatter.string(from: rec.detectedAt)
            let link = "https://instagram.com/\(rec.user.username)"
            csv.append("\(rec.user.username),\(cleanFullName),\(dateStr),\(link)\n")
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("IG_Lost_Followers_\(Date().timeIntervalSince1970).csv")
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("CSV export error: \(error)")
            return nil
        }
    }

    public static func exportGainedFollowersToCSV(records: [GainedFollowerRecord]) -> URL? {
        let formatter = ISO8601DateFormatter()
        var csv = "Username,Full Name,Detected Date,Profile Link\n"
        for rec in records {
            let cleanFullName = rec.user.fullName.replacingOccurrences(of: ",", with: " ")
            let dateStr = formatter.string(from: rec.detectedAt)
            let link = "https://instagram.com/\(rec.user.username)"
            csv.append("\(rec.user.username),\(cleanFullName),\(dateStr),\(link)\n")
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("IG_New_Followers_\(Date().timeIntervalSince1970).csv")
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("CSV export error: \(error)")
            return nil
        }
    }
}
