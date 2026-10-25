//
//  MaintenanceModel.swift
//  RecoverySignal2
//
//  "How much should I eat to hold my weight?" — answered from what your body
//  actually burns, and turned into daily calorie and macro targets.
//
//  Maintenance = resting energy + average activity + digestion
//
//    resting    Apple Watch "Resting Energy", averaged over recent full-wear
//               days. Without a Watch, Mifflin–St Jeor from height/age/weight.
//    activity   Apple Watch "Active Energy", averaged over the same days.
//    digestion  The thermic effect of food: roughly 10% of what you eat. At
//               maintenance intake equals expenditure, so
//               total = (resting + activity) / (1 − 0.10).
//
//  Pure Foundation — no SwiftData or UIKit — so the maths can be checked on
//  its own. EnergyModel adapts DailyMetrics into the input here.
//

import Foundation

/// The slow-changing facts about the user that a formula needs.
/// Read from Health on refresh and cached, since none of it varies day to day.
nonisolated struct BodyProfile: Equatable, Sendable {
    var heightCm: Double?
    var ageYears: Int?
    /// nil when Health has no answer — the formula then uses the midpoint.
    var isFemale: Bool?

    private static let heightKey = "profile.heightCm"
    private static let ageKey = "profile.ageYears"
    private static let sexKey = "profile.sex"

    static func load(from defaults: UserDefaults = .standard) -> BodyProfile {
        BodyProfile(
            heightCm: defaults.object(forKey: heightKey) as? Double,
            ageYears: defaults.object(forKey: ageKey) as? Int,
            isFemale: (defaults.string(forKey: sexKey)).map { $0 == "female" }
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        if let heightCm { defaults.set(heightCm, forKey: Self.heightKey) } else { defaults.removeObject(forKey: Self.heightKey) }
        if let ageYears { defaults.set(ageYears, forKey: Self.ageKey) } else { defaults.removeObject(forKey: Self.ageKey) }
        if let isFemale { defaults.set(isFemale ? "female" : "male", forKey: Self.sexKey) } else { defaults.removeObject(forKey: Self.sexKey) }
    }
}

/// One day's energy facts — the only inputs the maintenance maths needs.
nonisolated struct DayEnergy: Sendable {
    let date: Date
    let restingKcal: Double?
    let activeKcal: Double?
    let bodyMassKg: Double?
}

nonisolated struct MaintenanceEstimate: Equatable, Sendable {
    enum RestingSource: Equatable, Sendable { case watch, formula }

    let total: Double        // kcal/day to hold weight
    let resting: Double
    let activity: Double
    let digestion: Double
    let restingSource: RestingSource
    /// How many days the averages rest on.
    let daysUsed: Int
}

nonisolated struct NutritionTargets: Equatable, Sendable {
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    /// True when the goal adjustment was capped at resting energy.
    let flooredAtResting: Bool

    /// Maintenance-level protein; goal phases override via GoalSettings.
    static let proteinGramsPerKg = 1.6
    /// Share of calories from fat: middle of the usual 25–35% range.
    static let fatShareOfCalories = 0.30
    /// Minimum fat on a cut, to protect hormone production.
    static let minimumFatGramsPerKg = 0.6

    /// Calories from maintenance plus the goal adjustment (never below resting
    /// energy); protein by bodyweight for the phase; fat as a share of
    /// calories with a floor; carbs fill the rest.
    init(maintenance: MaintenanceEstimate, bodyMassKg: Double?, goal: GoalSettings = GoalSettings.load()) {
        let adjusted = maintenance.total + goal.signedDailyAdjustment
        let kcal = max(adjusted, maintenance.resting)
        let protein = bodyMassKg.map { $0 * goal.phase.proteinGramsPerKg } ?? kcal * 0.25 / 4
        let fatFloor = bodyMassKg.map { $0 * Self.minimumFatGramsPerKg } ?? 0
        let fat = max(kcal * Self.fatShareOfCalories / 9, fatFloor)
        calories = kcal
        proteinGrams = protein
        fatGrams = fat
        carbsGrams = max(0, kcal - protein * 4 - fat * 9) / 4
        flooredAtResting = adjusted < maintenance.resting
    }
}

nonisolated enum MaintenanceModel {

    static let thermicEffectShare = 0.10
    /// A day counts as "worn" if its resting energy reaches this share of the
    /// typical day. Resting energy accrues only while the Watch is on, so a
    /// half-day of wear shows up as roughly half the usual resting total.
    static let fullWearThreshold = 0.8
    static let minimumDays = 5

    static func estimate(days: [DayEnergy], profile: BodyProfile,
                         window: Int = 14, now: Date = Date(),
                         calendar: Calendar = .current) -> MaintenanceEstimate? {
        // Completed days only: today's totals are still accumulating and would
        // drag both averages down.
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -window, to: today) else { return nil }
        let completed = days.filter { $0.date >= windowStart && $0.date < today }

        if let fromWatch = watchEstimate(completed) { return fromWatch }
        return formulaEstimate(completed, allDays: days, profile: profile)
    }

    private static func watchEstimate(_ days: [DayEnergy]) -> MaintenanceEstimate? {
        let restingValues = days.compactMap(\.restingKcal).filter { $0 > 0 }
        guard restingValues.count >= minimumDays, let typical = median(restingValues) else { return nil }

        let worn = days.filter { ($0.restingKcal ?? 0) >= typical * fullWearThreshold }
        guard worn.count >= minimumDays else { return nil }

        let resting = worn.compactMap(\.restingKcal).reduce(0, +) / Double(worn.count)
        let activity = worn.map { $0.activeKcal ?? 0 }.reduce(0, +) / Double(worn.count)
        return assemble(resting: resting, activity: activity, source: .watch, days: worn.count)
    }

    private static func formulaEstimate(_ days: [DayEnergy], allDays: [DayEnergy], profile: BodyProfile) -> MaintenanceEstimate? {
        guard let resting = mifflinStJeor(profile: profile, bodyMassKg: latestBodyMass(allDays)) else { return nil }

        // "Given your average activity" needs some activity data to average.
        let active = days.compactMap(\.activeKcal).filter { $0 > 0 }
        guard active.count >= minimumDays else { return nil }
        let activity = active.reduce(0, +) / Double(active.count)
        return assemble(resting: resting, activity: activity, source: .formula, days: active.count)
    }

    /// Mifflin–St Jeor (1990): 10·kg + 6.25·cm − 5·age + s, s = +5 male, −161 female.
    /// Unknown sex uses the midpoint, −78, rather than guessing either way.
    static func mifflinStJeor(profile: BodyProfile, bodyMassKg: Double?) -> Double? {
        guard let kg = bodyMassKg, let cm = profile.heightCm, let age = profile.ageYears,
              kg > 0, cm > 0, age > 0 else { return nil }
        let sexTerm: Double = profile.isFemale.map { $0 ? -161 : 5 } ?? -78
        return 10 * kg + 6.25 * cm - 5 * Double(age) + sexTerm
    }

    private static func assemble(resting: Double, activity: Double,
                                 source: MaintenanceEstimate.RestingSource, days: Int) -> MaintenanceEstimate {
        let total = (resting + activity) / (1 - thermicEffectShare)
        return MaintenanceEstimate(total: total, resting: resting, activity: activity,
                                   digestion: total - resting - activity,
                                   restingSource: source, daysUsed: days)
    }

    static func latestBodyMass(_ days: [DayEnergy]) -> Double? {
        days.sorted { $0.date < $1.date }.compactMap(\.bodyMassKg).last
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
}
