//
//  InsightRules.swift
//  RecoverySignal
//
//  Deterministic, explainable checks over a window of DailyMetrics. These are
//  intentionally simple thresholds, not a black box — every flag should be
//  traceable to a specific number you can go look at yourself. Tune the
//  constants at the top as you learn what's normal for you.
//
//  IMPORTANT HONESTY NOTE: a Watch + smart scale cannot directly measure body
//  composition (muscle vs. fat). The "body composition" rule below is a
//  directional inference from weight trend + calorie balance + resistance
//  training frequency, not a measurement. It's phrased that way on purpose —
//  don't let this read as more certain than it is.
//

import Foundation

enum InsightRules {

    // Tune these to your own baseline once you have a few weeks of data.
    static let proteinGramsPerKgTarget = 1.6
    static let sleepDebtHoursPerWeekThreshold = 5.0
    static let hrvDropFractionThreshold = 0.12 // 12% below rolling baseline

    static func evaluate(recentDays: [DailyMetrics]) -> [Insight] {
        let sorted = recentDays.sorted { $0.date < $1.date }
        guard let latestDay = sorted.last?.date else { return [] }

        return recoveryDeficit(sorted, referenceDate: latestDay)
            + sleepDebt(sorted, referenceDate: latestDay)
            + proteinShortfall(sorted, referenceDate: latestDay)
            + bodyTrend(sorted, referenceDate: latestDay)
    }

    // MARK: - Recovery

    private static func recoveryDeficit(_ days: [DailyMetrics], referenceDate: Date) -> [Insight] {
        let hrvValues = days.compactMap(\.hrvSDNN)
        guard hrvValues.count >= 7 else { return [] }

        let baseline = average(hrvValues.dropLast(3))
        let recent = average(hrvValues.suffix(3))
        guard baseline > 0 else { return [] }

        let drop = (baseline - recent) / baseline
        guard drop >= hrvDropFractionThreshold else { return [] }

        let recentSleep = average(days.suffix(3).compactMap(\.sleepAsleepHours))
        let sleepNote = recentSleep > 0 && recentSleep < 6.5
            ? " Combined with averaging \(String(format: "%.1f", recentSleep))h of sleep the last 3 nights, this reads like a genuine recovery deficit rather than noise."
            : " Sleep looks normal over the same window, so this is worth watching rather than acting on immediately."

        return [Insight(
            date: referenceDate,
            title: "Recovery is trending down",
            detail: "Your HRV over the last 3 days is \(String(format: "%.0f", drop * 100))% below your recent baseline.\(sleepNote)",
            severity: .warning,
            category: "recovery"
        )]
    }

    // MARK: - Sleep

    private static func sleepDebt(_ days: [DailyMetrics], referenceDate: Date) -> [Insight] {
        let asleepValues = days.suffix(7).compactMap(\.sleepAsleepHours)
        guard asleepValues.count >= 4 else { return [] } // need a reasonable sample of nights

        let debt = asleepValues.reduce(0.0) { $0 + max(0, 8.0 - $1) }
        guard debt >= sleepDebtHoursPerWeekThreshold else { return [] }

        return [Insight(
            date: referenceDate,
            title: "Sleep debt is building",
            detail: "Over the last \(asleepValues.count) tracked nights you're running about \(String(format: "%.1f", debt))h short of 8h/night. This tends to show up in recovery metrics within a few days.",
            severity: .notice,
            category: "sleep"
        )]
    }

    // MARK: - Nutrition

    private static func proteinShortfall(_ days: [DailyMetrics], referenceDate: Date) -> [Insight] {
        let pairs = days.suffix(7).compactMap { day -> (protein: Double, bodyMass: Double)? in
            guard let p = day.proteinGrams, let bw = day.bodyMassKg else { return nil }
            return (p, bw)
        }
        guard pairs.count >= 3 else { return [] }

        let avgProtein = average(pairs.map(\.protein))
        let avgBodyMass = average(pairs.map(\.bodyMass))
        let target = avgBodyMass * proteinGramsPerKgTarget
        guard avgProtein < target * 0.85 else { return [] }

        return [Insight(
            date: referenceDate,
            title: "Protein is under target",
            detail: "You're averaging \(String(format: "%.0f", avgProtein))g/day of protein against a target of roughly \(String(format: "%.0f", target))g for your bodyweight — worth closing that gap if muscle retention/growth matters to you.",
            severity: .info,
            category: "nutrition"
        )]
    }

    // MARK: - Body composition (directional inference only)

    private static func bodyTrend(_ days: [DailyMetrics], referenceDate: Date) -> [Insight] {
        let weights = days.compactMap { d -> (date: Date, kg: Double)? in
            guard let m = d.bodyMassKg else { return nil }
            return (d.date, m)
        }
        guard weights.count >= 5, let first = weights.first, let last = weights.last else { return [] }

        let daySpan = last.date.timeIntervalSince(first.date) / 86400.0
        guard daySpan >= 5 else { return [] }
        let weeklyRate = (last.kg - first.kg) / daySpan * 7.0

        let avgIntake = average(days.compactMap(\.dietaryEnergyKcal))
        guard avgIntake > 0 else { return [] }
        let resistanceDays = days.filter(\.workoutIsResistance).count

        let narrative: String
        if weeklyRate > 0.15 {
            narrative = resistanceDays >= 2
                ? "Weight is rising about \(String(format: "%.2f", weeklyRate))kg/week alongside \(resistanceDays) resistance sessions — consistent with muscle gain, though only a smart scale or DEXA can confirm composition directly."
                : "Weight is rising about \(String(format: "%.2f", weeklyRate))kg/week with little resistance training logged — this is more likely to be fat gain than muscle. Worth checking if intake has crept up."
        } else if weeklyRate < -0.15 {
            narrative = "Weight is dropping about \(String(format: "%.2f", abs(weeklyRate)))kg/week. If protein and resistance training are both in place, this is likely mostly fat loss; if not, some of it may be muscle."
        } else {
            return []
        }

        return [Insight(date: referenceDate, title: "Body weight trend", detail: narrative, severity: .info, category: "body")]
    }

    private static func average(_ values: some Sequence<Double>) -> Double {
        let arr = Array(values)
        guard !arr.isEmpty else { return 0 }
        return arr.reduce(0, +) / Double(arr.count)
    }
}
