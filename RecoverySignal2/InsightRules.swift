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
    /// Follows the goal phase: higher in a cut, where lean mass is most at risk.
    static var proteinGramsPerKgTarget: Double { GoalSettings.load().phase.proteinGramsPerKg }
    static let sleepDebtHoursPerWeekThreshold = 5.0
    static let hrvDropFractionThreshold = 0.12 // 12% below rolling baseline

    static func evaluate(recentDays: [DailyMetrics]) -> [Insight] {
        let sorted = recentDays.sorted { $0.date < $1.date }
        guard let latestDay = sorted.last?.date else { return [] }

        return sicknessRisk(sorted, referenceDate: latestDay)
            + recoveryDeficit(sorted, referenceDate: latestDay)
            + acwrWarning(sorted, referenceDate: latestDay)
            + compositeFatigue(sorted, referenceDate: latestDay)
            + sleepDebt(sorted, referenceDate: latestDay)
            + trainingLoadSpike(sorted, referenceDate: latestDay)
            + proteinShortfall(sorted, referenceDate: latestDay)
            + bodyTrend(sorted, referenceDate: latestDay)
    }

    // MARK: - Early illness signal

    private static func sicknessRisk(_ days: [DailyMetrics], referenceDate: Date) -> [Insight] {
        guard let signal = SicknessRiskModel.evaluate(from: days) else { return [] }

        // A hard couple of days can raise the same signals — don't cry wolf
        // if training load is also spiking right now.
        let recentLoad = Stats.mean(days.suffix(2).map { $0.trainingLoad ?? 0 }) ?? 0
        let chronicLoad = Stats.mean(days.dropLast(2).suffix(28).map { $0.trainingLoad ?? 0 }) ?? 0
        guard chronicLoad == 0 || recentLoad < chronicLoad * 1.4 else { return [] }

        let list = signal.components.map { "\($0.label.lowercased())" }.joined(separator: ", ")
        return [Insight(
            date: referenceDate,
            title: String(localized: "A few signs worth watching"),
            detail: String(localized: "Over the last 2 days, \(list) \(signal.components.count == 1 ? "has" : "have") crept up together against your normal. This combination often shows up a day or two before you feel unwell — it's also what a hard training block can look like, so treat it as a nudge to rest if it develops, not a diagnosis."),
            severity: .notice,
            category: "recovery"
        )]
    }

    // MARK: - Model-driven flags

    private static func acwrWarning(_ days: [DailyMetrics], referenceDate: Date) -> [Insight] {
        guard let acwr = TrainingLoadModel.compute(from: days), acwr.ratio >= 1.5 else { return [] }
        return [Insight(
            date: referenceDate,
            title: String(localized: "Workload ratio in the spike zone"),
            detail: String(localized: "Your acute:chronic workload ratio is \(acwr.ratio.formatted(.number.precision(.fractionLength(2)))). Above 1.5 is where the training-load literature sees injury risk climb sharply. Holding volume flat for a week brings this back without losing fitness."),
            severity: .warning,
            category: "training"
        )]
    }

    private static func compositeFatigue(_ days: [DailyMetrics], referenceDate: Date) -> [Insight] {
        guard let fatigue = ReadinessModel.fatigue(from: days),
              fatigue.consecutiveStrainedDays >= 2 else { return [] }

        let worst = fatigue.components.min { $0.z < $1.z }
        let driver = worst.map { " \($0.label) is the biggest contributor." } ?? ""

        return [Insight(
            date: referenceDate,
            title: String(localized: "Fatigue elevated \(fatigue.consecutiveStrainedDays) days running"),
            detail: String(localized: "Your composite fatigue score has been below −1.5 SD of your own baseline for \(fatigue.consecutiveStrainedDays) consecutive days.\(driver) One bad day is noise; a run of them is a signal."),
            severity: .warning,
            category: "recovery"
        )]
    }

    // MARK: - Training load

    /// A sharp jump in training minutes is only worth flagging loudly when
    /// recovery is also heading the wrong way — load on its own is just training.
    private static func trainingLoadSpike(_ days: [DailyMetrics], referenceDate: Date) -> [Insight] {
        let thisWeek = days.suffix(7)
        let priorWeeks = days.dropLast(7).suffix(14)
        guard priorWeeks.count >= 7 else { return [] }

        let currentMinutes = thisWeek.compactMap(\.workoutMinutes).reduce(0, +)
        let priorWeekly = priorWeeks.compactMap(\.workoutMinutes).reduce(0, +) / (Double(priorWeeks.count) / 7.0)
        guard priorWeekly >= 30, currentMinutes > priorWeekly * 1.5 else { return [] }

        let increase = Int(((currentMinutes / priorWeekly) - 1) * 100)
        let hrvValues = days.compactMap(\.hrvSDNN)
        let recoveryFalling = hrvValues.count >= 7
            && average(hrvValues.suffix(3)) < average(hrvValues.dropLast(3)) * 0.95

        let detail = recoveryFalling
            ? String(localized: "Training volume is up about \(increase)% on your recent average (\(Int(currentMinutes)) min this week) while HRV drifts down. That combination is the classic setup for digging a hole — consider a lighter week.")
            : String(localized: "Training volume is up about \(increase)% on your recent average (\(Int(currentMinutes)) min this week). Recovery markers are holding so far, so this is worth watching rather than acting on.")

        return [Insight(
            date: referenceDate,
            title: String(localized: "Training load jumped"),
            detail: detail,
            severity: recoveryFalling ? .warning : .info,
            category: "training"
        )]
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
            ? String(localized: " Combined with averaging \(recentSleep.formatted(.number.precision(.fractionLength(1))))h of sleep the last 3 nights, this reads like a genuine recovery deficit rather than noise.")
            : String(localized: " Sleep looks normal over the same window, so this is worth watching rather than acting on immediately.")

        return [Insight(
            date: referenceDate,
            title: String(localized: "Recovery is trending down"),
            detail: String(localized: "Your HRV over the last 3 days is \(Int((drop * 100).rounded()))% below your recent baseline.\(sleepNote)"),
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
            title: String(localized: "Sleep debt is building"),
            detail: String(localized: "Over the last \(asleepValues.count) tracked nights you're running about \(debt.formatted(.number.precision(.fractionLength(1))))h short of 8h/night. This tends to show up in recovery metrics within a few days."),
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
            title: String(localized: "Protein is under target"),
            detail: String(localized: "You're averaging \(Int(avgProtein.rounded()))g/day of protein against a target of roughly \(Int(target.rounded()))g for your bodyweight — worth closing that gap if muscle retention/growth matters to you."),
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
                ? String(localized: "Weight is rising about \(weeklyRate.formatted(.number.precision(.fractionLength(2))))kg/week alongside \(resistanceDays) resistance sessions — consistent with muscle gain, though only a smart scale or DEXA can confirm composition directly.")
                : String(localized: "Weight is rising about \(weeklyRate.formatted(.number.precision(.fractionLength(2))))kg/week with little resistance training logged — this is more likely to be fat gain than muscle. Worth checking if intake has crept up.")
        } else if weeklyRate < -0.15 {
            narrative = String(localized: "Weight is dropping about \(abs(weeklyRate).formatted(.number.precision(.fractionLength(2))))kg/week. If protein and resistance training are both in place, this is likely mostly fat loss; if not, some of it may be muscle.")
        } else {
            return []
        }

        return [Insight(date: referenceDate, title: String(localized: "Body weight trend"), detail: narrative, severity: .info, category: "body")]
    }

    private static func average(_ values: some Sequence<Double>) -> Double {
        let arr = Array(values)
        guard !arr.isEmpty else { return 0 }
        return arr.reduce(0, +) / Double(arr.count)
    }
}
