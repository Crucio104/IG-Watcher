import Foundation
import SwiftUI

/// Traccia le azioni giornaliere di unfollow per proteggere l'account dai blocchi temporanei di Instagram
@MainActor
public final class DailySafetyTracker: ObservableObject {
    public static let shared = DailySafetyTracker()

    public let recommendedDailyLimit = 30
    private let countKey = "com.instagramwatcher.daily_actions_count"
    private let dateKey = "com.instagramwatcher.daily_actions_date"

    @Published public private(set) var actionsToday: Int = 0

    public var remainingActions: Int {
        max(recommendedDailyLimit - actionsToday, 0)
    }

    public var safetyProgress: Double {
        min(Double(actionsToday) / Double(recommendedDailyLimit), 1.0)
    }

    public var statusColor: Color {
        if actionsToday < 20 {
            return Color.green
        } else if actionsToday < recommendedDailyLimit {
            return Color.orange
        } else {
            return Color.red
        }
    }

    private init() {
        checkAndResetDaily()
    }

    public func recordAction() {
        checkAndResetDaily()
        actionsToday += 1
        UserDefaults.standard.set(actionsToday, forKey: countKey)
        UserDefaults.standard.set(Date(), forKey: dateKey)
    }

    private func checkAndResetDaily() {
        if let lastDate = UserDefaults.standard.object(forKey: dateKey) as? Date {
            if !Calendar.current.isDateInToday(lastDate) {
                actionsToday = 0
                UserDefaults.standard.set(0, forKey: countKey)
                UserDefaults.standard.set(Date(), forKey: dateKey)
                return
            }
        }
        actionsToday = UserDefaults.standard.integer(forKey: countKey)
    }
}
