//
//  WakeAlarmSync.swift
//  RecoverySignal2
//
//  Optional, explicitly opted-in: keeps a real system alarm in step with
//  whichever wake time is currently active in the sleep plan — the "usual"
//  wake time learned from your last 4 weeks, the fixed every-day time, or a
//  one-off wake set for tomorrow. Change it once, in one place, and this
//  updates the actual alarm that fires; you never have to also open the
//  Clock app.
//
//  This is entirely separate from BedtimeAlarm.swift, which stays permanently
//  disabled — the app still never sets a wind-down or bedtime reminder.
//  Nothing here fires unless you turn "Sync with a real alarm" on yourself.
//
//  There's no API for the reverse (reading an alarm you set in Clock and
//  pulling its time into the app) — iOS doesn't expose other apps' alarms,
//  or even the Health app's own sleep schedule, to any third-party app. This
//  is the only direction that's actually possible: the app's wake time drives
//  a real alarm, via AlarmKit (iOS 26+).
//
//  One honest limitation: AlarmKit alarms repeat by weekday, not "just once".
//  A one-off wake time for tomorrow retimes the recurring alarm to that hour
//  for every day until the plan is next recomputed (on next app open or
//  refresh) — at which point, once the one-off has passed, it reverts to the
//  usual time on its own. It is not a true single-occurrence override.
//

import Foundation
import AlarmKit
import ActivityKit
import SwiftUI

enum WakeAlarmSync {

    private static let enabledKey = "wakeAlarmSync.enabled"
    private static let idKey = "wakeAlarmSync.alarmID"
    private static let scheduledClockKey = "wakeAlarmSync.scheduledClock"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var authorizationState: AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    /// Asks for permission and, if granted, turns sync on and schedules
    /// tonight's wake time right away. Leaves sync off if permission is refused.
    @MainActor
    static func enable(days: [DailyMetrics]) async -> Bool {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            guard state == .authorized else {
                isEnabled = false
                return false
            }
        } catch {
            isEnabled = false
            return false
        }
        isEnabled = true
        await sync(days: days)
        return true
    }

    static func disable() {
        isEnabled = false
        cancelScheduled()
    }

    /// Call whenever the wake time might have changed — the plan is
    /// recomputed and the real alarm is pushed to match, only if the clock
    /// time it resolves to has actually changed since the last sync.
    @MainActor
    static func sync(days: [DailyMetrics]) async {
        guard isEnabled else { return }
        guard AlarmManager.shared.authorizationState == .authorized else {
            // Permission was revoked in Settings since we last checked.
            isEnabled = false
            return
        }
        guard let plan = SleepPlanner.plan(days: days) else { return }
        let clock = Calendar.current.dateComponents([.hour, .minute], from: plan.wake)
        guard let hour = clock.hour, let minute = clock.minute else { return }

        let key = "\(hour):\(minute)"
        guard UserDefaults.standard.string(forKey: scheduledClockKey) != key else { return }

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource("Wake up"),
            secondaryButton: AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .countdown
        )
        struct WakeAlarmMetadata: AlarmMetadata {}
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeAlarmMetadata(),
            tintColor: Theme.accent
        )
        let snooze = Alarm.CountdownDuration(preAlert: nil, postAlert: 9 * 60)
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: snooze,
            schedule: .relative(.init(
                time: .init(hour: hour, minute: minute),
                repeats: .weekly([.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
            )),
            attributes: attributes,
            sound: .default
        )

        // Cancelling first avoids relying on unclear replace-in-place
        // semantics for re-scheduling an id that's already live.
        cancelScheduled()
        let id = UUID()
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            UserDefaults.standard.set(id.uuidString, forKey: idKey)
            UserDefaults.standard.set(key, forKey: scheduledClockKey)
        } catch {
            // Leave it be — the next sync (next app open) tries again.
        }
    }

    private static func cancelScheduled() {
        if let saved = UserDefaults.standard.string(forKey: idKey), let uuid = UUID(uuidString: saved) {
            try? AlarmManager.shared.cancel(id: uuid)
        }
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: scheduledClockKey)
    }
}
