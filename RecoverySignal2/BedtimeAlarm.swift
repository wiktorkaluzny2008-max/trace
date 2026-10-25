//
//  BedtimeAlarm.swift
//  RecoverySignal2
//
//  Tonight's wind-down and bedtime times, from the sleep plan (SleepNeed.swift):
//
//    wind down = start of the recommended bedtime window − 30 min
//    bedtime   = start of the recommended bedtime window
//
//  Nothing is ever scheduled here: no wind-down alarm, no bedtime
//  notification. `reschedule` only removes whatever older versions set, then
//  hands off to WakeAlarmSync — a separate, explicitly opted-in feature that
//  keeps a real wake alarm in step with the plan's wake time. That's the only
//  alarm this app ever sets, and only once you turn it on yourself.
//

import Foundation
import SwiftUI
import AlarmKit
import UserNotifications

enum BedtimeAlarm {

    static let baseSleepHours = 8.0
    static let windDownMinutes = 30.0

    private static let enabledKey = "bedtime.enabled"
    private static let wakeHourKey = "bedtime.wakeHour"
    private static let wakeMinuteKey = "bedtime.wakeMinute"
    private static let alarmIDKey = "bedtime.alarmID"
    private static let scheduledDateKey = "bedtime.scheduledDate"
    private static let windDownID = "bedtime.windDown"
    private static let bedtimeID = "bedtime.bed"

    // MARK: Settings

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var wakeTime: DateComponents {
        get {
            let d = UserDefaults.standard
            return DateComponents(hour: d.object(forKey: wakeHourKey) as? Int ?? 7,
                                  minute: d.object(forKey: wakeMinuteKey) as? Int ?? 0)
        }
        set {
            UserDefaults.standard.set(newValue.hour, forKey: wakeHourKey)
            UserDefaults.standard.set(newValue.minute, forKey: wakeMinuteKey)
        }
    }

    // MARK: Planning

    struct Plan {
        let alarm: Date
        let bedtime: Date
        let wake: Date
        let extraMinutes: Int
        let debtHours: Double
    }

    @MainActor
    static func plan(days: [DailyMetrics], now: Date = Date()) -> Plan? {
        guard let sleep = SleepPlanner.plan(days: days, now: now) else { return nil }
        let alarm = sleep.windowStart.addingTimeInterval(-windDownMinutes * 60)
        guard alarm > now.addingTimeInterval(60) else { return nil }
        let extra = sleep.need.strainExtra + sleep.need.debtExtra - sleep.need.napCredit
        return Plan(alarm: alarm, bedtime: sleep.windowStart, wake: sleep.wake,
                    extraMinutes: max(Int((extra * 60).rounded()), 0), debtHours: sleep.need.debtExtra)
    }

    // MARK: Scheduling

    /// Bedtime reminders are switched off for good: the app never sets an
    /// alarm or a wind-down notification. Every call clears anything an
    /// earlier version left behind. Tonight's bedtime still shows in the app
    /// and on the Lock Screen widgets.
    @MainActor
    static func reschedule(days: [DailyMetrics]) async {
        isEnabled = false
        cancel()
        await WakeAlarmSync.sync(days: days)
    }

    @MainActor
    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [windDownID, bedtimeID])
        center.removeDeliveredNotifications(withIdentifiers: [windDownID, bedtimeID])
        UserDefaults.standard.removeObject(forKey: scheduledDateKey)

        // Real alarms from older versions — cancel every one this app owns,
        // not just the last one it remembered.
        let alarms = AlarmManager.shared
        if alarms.authorizationState == .authorized {
            for alarm in (try? alarms.alarms) ?? [] {
                try? alarms.cancel(id: alarm.id)
            }
        }
        UserDefaults.standard.removeObject(forKey: alarmIDKey)
    }
}
