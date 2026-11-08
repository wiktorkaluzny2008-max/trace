//
//  BriefingService.swift
//  RecoverySignal2
//
//  The morning briefing: one notification a day with your recovery score and
//  a one-line read.
//
//  Local notifications carry fixed text, so there are two layers:
//   1. Whenever the app refreshes after your chosen time and last night's
//      HRV/sleep have synced, it posts the real briefing immediately (once a day).
//   2. A generic "your read is ready" reminder is scheduled for the chosen time
//      as a fallback, and cancelled once the real one has gone out.
//
//  Also publishes a small snapshot for the home-screen widget.
//

import Foundation
import UserNotifications
import WidgetKit

enum BriefingService {

    static let fallbackIdentifier = "briefing.fallback"
    private static let enabledKey = "briefing.enabled"
    private static let hourKey = "briefing.hour"
    private static let minuteKey = "briefing.minute"
    private static let lastSentKey = "briefing.lastSent"

    // MARK: Settings

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var time: DateComponents {
        get {
            let defaults = UserDefaults.standard
            let hour = defaults.object(forKey: hourKey) as? Int ?? 7
            let minute = defaults.object(forKey: minuteKey) as? Int ?? 30
            return DateComponents(hour: hour, minute: minute)
        }
        set {
            UserDefaults.standard.set(newValue.hour, forKey: hourKey)
            UserDefaults.standard.set(newValue.minute, forKey: minuteKey)
        }
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Re-creates (or removes) the daily fallback reminder.
    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [fallbackIdentifier])
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your recovery read is ready")
        content.body = String(localized: "Open Trace for today's score and what it means.")
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        center.add(UNNotificationRequest(identifier: fallbackIdentifier, content: content, trigger: trigger))
    }

    // MARK: Delivery

    /// Call after every refresh. Sends the real briefing at most once a day,
    /// and only once it's past the chosen time and today's data exists.
    @MainActor
    static func update(with days: [DailyMetrics], now: Date = Date()) {
        publishWidgetSnapshot(days: days, now: now)
        Task { await MacroLiveActivity.sync(days: days, now: now) }

        guard isEnabled else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        if let lastSent = UserDefaults.standard.object(forKey: lastSentKey) as? Date,
           calendar.isDate(lastSent, inSameDayAs: now) { return }

        guard let scheduled = calendar.date(bySettingHour: time.hour ?? 7, minute: time.minute ?? 30, second: 0, of: now),
              now >= scheduled,
              let todayMetrics = days.first(where: { calendar.isDate($0.date, inSameDayAs: today) }),
              todayMetrics.hrvSDNN != nil || todayMetrics.sleepAsleepHours != nil,
              let score = RecoveryScore.compute(from: Array(days.sorted { $0.date > $1.date }.prefix(RecoveryScore.baselineDays + 1)))
        else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Recovery \(score.value) · \(score.band.label)")
        content.body = score.headline
        content.sound = .default

        let center = UNUserNotificationCenter.current()
        center.add(UNNotificationRequest(identifier: "briefing.\(today.timeIntervalSince1970)", content: content, trigger: nil))
        // The real briefing replaces today's generic fallback.
        center.removeDeliveredNotifications(withIdentifiers: [fallbackIdentifier])
        UserDefaults.standard.set(now, forKey: lastSentKey)
    }

    // MARK: Widget

    @MainActor
    private static func publishWidgetSnapshot(days: [DailyMetrics], now: Date) {
        let sorted = days.sorted { $0.date > $1.date }
        let score = RecoveryScore.compute(from: Array(sorted.prefix(RecoveryScore.baselineDays + 1)))
        let today = sorted.first { Calendar.current.isDate($0.date, inSameDayAs: now) }
        let targets = EnergyModel.cachedTargets(from: days)
        let sleepPlan = SleepPlanner.plan(days: days, now: now)

        let snapshot = WidgetSnapshot(
            updatedAt: now,
            score: score?.value,
            bandLabel: score?.band.label,
            caloriesEaten: today?.dietaryEnergyKcal,
            caloriesTarget: targets?.calories,
            proteinEaten: today?.proteinGrams,
            proteinTarget: targets?.proteinGrams,
            carbsEaten: today?.carbsGrams,
            carbsTarget: targets?.carbsGrams,
            fatEaten: today?.fatGrams,
            fatTarget: targets?.fatGrams,
            sleepHours: today?.sleepAsleepHours,
            bedtime: sleepPlan?.windowStart,
            wakeTime: sleepPlan?.wake,
            sleepNeedHours: sleepPlan?.need.total,
            recentCalories: (0..<7).reversed().map { offset in
                let day = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: now)) ?? now
                return sorted.first { Calendar.current.isDate($0.date, inSameDayAs: day) }?.dietaryEnergyKcal ?? 0
            }
        )
        let previous = WidgetSnapshot.load()
        snapshot.save()
        // Widgets have a daily reload budget: only spend it when something
        // visible changed (or a new day started).
        if previous.map({ !$0.sameContent(as: snapshot) }) ?? true {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
