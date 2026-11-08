//
//  MacroLiveActivity.swift
//  RecoverySignal2
//
//  A Live Activity showing calories and macros eaten today, and tonight's bedtime, on the Lock Screen
//  and in the Dynamic Island, updated whenever new Yazio data syncs.
//
//  The on-screen design lives in the widget extension; this file starts,
//  updates and ends the activity. `MacroActivityAttributes` must match the copy
//  in the widget extension exactly.
//
//  iOS keeps a Live Activity for up to 8 hours (then it lingers on the Lock
//  Screen a little longer), so it's restarted on the next refresh after that.
//

import Foundation
import ActivityKit

nonisolated struct MacroActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var caloriesEaten: Int
        var caloriesTarget: Int
        var proteinEaten: Int
        var proteinTarget: Int
        var carbsEaten: Int = 0
        var carbsTarget: Int = 0
        var fatEaten: Int = 0
        var fatTarget: Int = 0
        var bedtime: Date? = nil
        var updatedAt: Date
    }

    var goalLabel: String
}

enum MacroLiveActivity {

    private static let enabledKey = "liveActivity.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var systemAllowsActivities: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Starts, updates or ends the activity to match today's numbers.
    @MainActor
    static func sync(days: [DailyMetrics], now: Date = Date()) async {
        guard isEnabled, systemAllowsActivities else {
            await endAll()
            return
        }

        let calendar = Calendar.current
        guard let targets = EnergyModel.cachedTargets(from: days) else { return }
        let today = days.first { calendar.isDate($0.date, inSameDayAs: now) }

        let state = MacroActivityAttributes.ContentState(
            caloriesEaten: Int((today?.dietaryEnergyKcal ?? 0).rounded()),
            caloriesTarget: Int(targets.calories.rounded()),
            proteinEaten: Int((today?.proteinGrams ?? 0).rounded()),
            proteinTarget: Int(targets.proteinGrams.rounded()),
            carbsEaten: Int((today?.carbsGrams ?? 0).rounded()),
            carbsTarget: Int(targets.carbsGrams.rounded()),
            fatEaten: Int((today?.fatGrams ?? 0).rounded()),
            fatTarget: Int(targets.fatGrams.rounded()),
            bedtime: SleepPlanner.plan(days: days, now: now)?.windowStart,
            updatedAt: now
        )
        // Yesterday's numbers mean nothing after midnight.
        let staleDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        let content = ActivityContent(state: state, staleDate: staleDate)

        let running = Activity<MacroActivityAttributes>.activities.filter { $0.activityState == .active }
        if let activity = running.first {
            var old = activity.content.state, new = state
            old.updatedAt = .distantPast
            new.updatedAt = .distantPast
            // Nothing new to show — don't spend an update.
            guard old != new else { return }
            await activity.update(content)
        } else {
            let attributes = MacroActivityAttributes(goalLabel: GoalSettings.load().phase.label)
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                // Most often: the widget extension that draws the activity isn't installed yet.
                print("Live Activity request failed: \(error)")
            }
        }
    }

    @MainActor
    static func endAll() async {
        for activity in Activity<MacroActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
