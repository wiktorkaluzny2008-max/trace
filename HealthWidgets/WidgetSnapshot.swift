//
//  WidgetSnapshot.swift
//  RecoverySignal2
//
//  The handful of numbers the home-screen widget shows, written by the app
//  after each refresh. Lives in a shared App Group so the widget extension can
//  read it — this file should be a member of both the app and widget targets.
//

import Foundation

nonisolated struct WidgetSnapshot: Codable, Sendable {
    static let appGroup = "group.com.wkaluzny.RecoverySignal2"
    private static let key = "widget.snapshot"

    var updatedAt: Date
    var score: Int?
    var bandLabel: String?
    var caloriesEaten: Double?
    var caloriesTarget: Double?
    var proteinEaten: Double?
    var proteinTarget: Double?
    var carbsEaten: Double? = nil
    var carbsTarget: Double? = nil
    var fatEaten: Double? = nil
    var fatTarget: Double? = nil
    /// Hours asleep last night.
    var sleepHours: Double? = nil
    /// Tonight's "be in bed by" time and the wake-up it plans for.
    var bedtime: Date? = nil
    var wakeTime: Date? = nil
    /// Tonight's sleep need, hours.
    var sleepNeedHours: Double? = nil
    /// Calories eaten on each of the last 7 days, oldest first (today last).
    var recentCalories: [Double]? = nil

    /// Falls back to standard defaults when the App Group isn't provisioned, so
    /// the app keeps working even on a signing setup that can't use groups.
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults.set(data, forKey: Self.key)
    }

    /// Same numbers on the same day — ignores when it was written.
    func sameContent(as other: WidgetSnapshot) -> Bool {
        guard Calendar.current.isDate(updatedAt, inSameDayAs: other.updatedAt) else { return false }
        var a = self, b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(a)) == (try? encoder.encode(b))
    }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
