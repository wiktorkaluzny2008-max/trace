//
//  AdvancedModels.swift
//  RecoverySignal2
//
//  The longer-horizon models at the bottom of Analysis. Each one is a pure
//  function over DailyMetrics, returns nil until it has enough data to say
//  something honest, and is described line by line in AnalysisExplainers.
//
//   1. Intake-balance method      what you must have eaten, from expenditure + weight change
//   2. Weight forecast            Hall-style energy-balance projection with adaptation
//   3. Expenditure phenotype      resting / exercise / NEAT / digestion, and NEAT drift
//   4. Heart-rate recovery        1-minute drop after workouts, a fitness & mortality marker
//   5. VO₂ max & fitness age      against age/sex norms
//   6. Sleep coupling             how sleep moves HRV, heart rate, activity and appetite
//   7. Activity spectrum          light / moderate / vigorous minutes vs guidelines
//   8. Mobility                   gait speed, step length, asymmetry, double support
//   9. Allostatic load            wear-and-tear composite against your long-term normal
//

import Foundation
import SwiftUI

// MARK: - Shared helpers

private extension Array where Element == DailyMetrics {
    var chronological: [DailyMetrics] { sorted { $0.date < $1.date } }

    func lastDays(_ n: Int, calendar: Calendar = .current) -> [DailyMetrics] {
        let start = calendar.date(byAdding: .day, value: -(n - 1), to: calendar.startOfDay(for: Date())) ?? Date()
        return filter { $0.date >= start }
    }
}

enum Regression {
    /// Least-squares slope and intercept of y on x.
    static func fit(_ x: [Double], _ y: [Double]) -> (slope: Double, intercept: Double)? {
        guard x.count == y.count, x.count >= 3, let mx = Stats.mean(x), let my = Stats.mean(y) else { return nil }
        let sxx = x.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(x, y).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let slope = sxy / sxx
        return (slope, my - slope * mx)
    }

    /// kg/day slope of weight over the given days, using real day spacing.
    static func weightSlope(_ days: [DailyMetrics]) -> Double? {
        let weighed = days.compactMap { d in d.bodyMassKg.map { (d.date, $0) } }
        guard weighed.count >= 6, let first = weighed.first?.0,
              let last = weighed.last?.0, last.timeIntervalSince(first) >= 10 * 86_400 else { return nil }
        return fit(weighed.map { $0.0.timeIntervalSince(first) / 86_400 }, weighed.map(\.1))?.slope
    }
}

/// Days the Watch was worn enough for energy totals to mean something.
private func totalExpenditure(_ day: DailyMetrics) -> Double? {
    guard let basal = day.basalEnergyKcal, basal > 900, let active = day.activeEnergyBurned else { return nil }
    return basal + active
}

// MARK: - 1 & 2. Energy balance

enum EnergyBalanceModel {

    /// Energy stored or released per kg of body-mass change. With body fat
    /// known, Forbes' rule splits the change into lean and fat tissue (Hall's
    /// densities: lean 1,816 kcal/kg, fat 9,440 kcal/kg). Otherwise 7,700.
    static func energyDensity(for days: [DailyMetrics]) -> (kcalPerKg: Double, leanShare: Double?) {
        guard let day = days.last(where: { $0.bodyFatPercent != nil && $0.bodyMassKg != nil }),
              let bf = day.bodyFatPercent, let weight = day.bodyMassKg else { return (EnergyModel.kcalPerKg, nil) }
        let fatMass = weight * bf / 100
        let leanShare = 10.4 / (10.4 + fatMass)
        return (leanShare * 1816 + (1 - leanShare) * 9440, leanShare)
    }

    struct IntakeBalance {
        struct Week: Identifiable {
            let id = UUID()
            let start: Date
            let logged: Double?
            let implied: Double
        }

        let windowDays: Int
        let expenditure: Double
        let storagePerDay: Double
        let impliedIntake: Double
        let loggedIntake: Double?
        let weightChangePerWeek: Double
        let kcalPerKg: Double
        let leanShare: Double?
        let weeks: [Week]

        /// Logged ÷ implied: 1.0 means the log matches what the body did.
        var loggingRatio: Double? {
            guard let loggedIntake, impliedIntake > 0 else { return nil }
            return loggedIntake / impliedIntake
        }
    }

    /// Intake-balance method: intake ≈ expenditure + change in stored energy.
    static func intakeBalance(from all: [DailyMetrics], window: Int = 28) -> IntakeBalance? {
        let days = all.chronological.lastDays(window)
        let tee = days.compactMap(totalExpenditure)
        guard tee.count >= 10, let expenditure = Stats.mean(tee),
              let slope = Regression.weightSlope(days) else { return nil }

        let density = energyDensity(for: days)
        let storage = slope * density.kcalPerKg
        let logged = days.compactMap(\.dietaryEnergyKcal).filter { $0 > 0 }

        // Weekly view: each week's expenditure plus the weight slope over the
        // 14 days ending that week (a single week's scale data is too noisy).
        let calendar = Calendar.current
        let history = all.chronological
        var weeks: [IntakeBalance.Week] = []
        for back in stride(from: 7, through: 0, by: -1) {
            guard let end = calendar.date(byAdding: .day, value: -7 * back, to: calendar.startOfDay(for: Date())),
                  let start = calendar.date(byAdding: .day, value: -6, to: end),
                  let slopeStart = calendar.date(byAdding: .day, value: -13, to: end) else { continue }
            let week = history.filter { $0.date >= start && $0.date <= end }
            let slopeDays = history.filter { $0.date >= slopeStart && $0.date <= end }
            guard let weekTEE = Stats.mean(week.compactMap(totalExpenditure)),
                  week.compactMap(totalExpenditure).count >= 4,
                  let weekSlope = Regression.weightSlope(slopeDays) else { continue }
            weeks.append(.init(start: start,
                               logged: Stats.mean(week.compactMap(\.dietaryEnergyKcal).filter { $0 > 0 }),
                               implied: weekTEE + weekSlope * density.kcalPerKg))
        }

        return IntakeBalance(windowDays: days.count, expenditure: expenditure, storagePerDay: storage,
                             impliedIntake: expenditure + storage,
                             loggedIntake: logged.count >= 10 ? Stats.mean(logged) : nil,
                             weightChangePerWeek: slope * 7, kcalPerKg: density.kcalPerKg,
                             leanShare: density.leanShare, weeks: weeks)
    }

    struct Forecast {
        struct Point: Identifiable {
            let id = UUID()
            let date: Date
            let weight: Double
            let low: Double
            let high: Double
            let scenario: String
        }

        let startWeight: Double
        let intake: Double
        let expenditure: Double
        let imbalance: Double
        /// Where weight settles if nothing changes.
        let plateauWeight: Double
        /// Days to cover half the distance to the plateau.
        let halfLifeDays: Double
        let points: [Point]
        let history: [TrendPoint]
        let goalIntake: Double?

        func weight(afterWeeks weeks: Int) -> Double? {
            points.filter { $0.scenario == Forecast.current }.min {
                abs($0.date.timeIntervalSinceNow - Double(weeks * 7 * 86_400)) < abs($1.date.timeIntervalSinceNow - Double(weeks * 7 * 86_400))
            }?.weight
        }

        static let current = "Current intake"
        static let goal = "Goal intake"
    }

    /// Each kg of body mass gained or lost shifts daily expenditure by about
    /// 22 kcal once adaptation settles (Hall et al., Lancet 2011).
    static let expenditurePerKg = 22.0

    /// W(t) = W₀ + ΔE ÷ k × (1 − e^(−t ÷ τ)),  τ = ρ ÷ k
    static func forecast(from all: [DailyMetrics], goalIntake: Double?, weeks: Int = 16) -> Forecast? {
        let days = all.chronological
        let weights = days.compactMap { d in d.bodyMassKg.map { TrendPoint(date: d.date, value: $0) } }
        guard weights.count >= 7, let startWeight = Stats.ewma(weights.map(\.value), span: 10) else { return nil }

        let recent = days.lastDays(14)
        let intakeDays = recent.compactMap(\.dietaryEnergyKcal).filter { $0 > 0 }
        guard intakeDays.count >= 7, let intake = Stats.mean(intakeDays) else { return nil }

        let adaptive = EnergyModel.adaptiveTDEE(from: days)
        let watchTEE = Stats.mean(recent.compactMap(totalExpenditure))
        guard let expenditure = adaptive?.value ?? watchTEE else { return nil }
        let uncertainty = adaptive?.uncertainty ?? 200

        let density = energyDensity(for: days).kcalPerKg
        let k = expenditurePerKg
        let tau = density / k

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var points: [Forecast.Point] = []
        func project(_ dailyIntake: Double, scenario: String, band: Bool) {
            for day in stride(from: 0, through: weeks * 7, by: 3) {
                guard let date = calendar.date(byAdding: .day, value: day, to: today) else { continue }
                let shape = 1 - exp(-Double(day) / tau)
                let mid = startWeight + (dailyIntake - expenditure) / k * shape
                let spread = band ? uncertainty / k * shape : 0
                points.append(.init(date: date, weight: mid, low: mid - spread, high: mid + spread, scenario: scenario))
            }
        }
        project(intake, scenario: Forecast.current, band: true)
        if let goalIntake, abs(goalIntake - intake) > 50 {
            project(goalIntake, scenario: Forecast.goal, band: false)
        }

        let historyStart = calendar.date(byAdding: .day, value: -60, to: today) ?? today
        return Forecast(startWeight: startWeight, intake: intake, expenditure: expenditure,
                        imbalance: intake - expenditure,
                        plateauWeight: startWeight + (intake - expenditure) / k,
                        halfLifeDays: tau * log(2),
                        points: points,
                        history: weights.filter { $0.date >= historyStart },
                        goalIntake: goalIntake)
    }
}

// MARK: - 3. Expenditure phenotype

enum ExpenditureModel {
    struct Week: Identifiable {
        let id = UUID()
        let start: Date
        let resting: Double
        let exercise: Double
        let neat: Double
        let digestion: Double
        var total: Double { resting + exercise + neat + digestion }
    }

    struct Breakdown {
        let weeks: [Week]
        let recent: Week
        let neatRecent: Double
        let neatBaseline: Double?
        var neatChange: Double? {
            guard let neatBaseline, neatBaseline > 0 else { return nil }
            return (neatRecent - neatBaseline) / neatBaseline * 100
        }
    }

    private static func components(_ day: DailyMetrics) -> (resting: Double, exercise: Double, neat: Double, digestion: Double)? {
        guard let resting = day.basalEnergyKcal, resting > 900, let active = day.activeEnergyBurned else { return nil }
        let exercise = min(day.workoutEnergyKcal ?? 0, active)
        return (resting, exercise, max(active - exercise, 0), (day.dietaryEnergyKcal ?? 0) * 0.10)
    }

    private static func average(_ days: [DailyMetrics], start: Date) -> Week? {
        let parts = days.compactMap { components($0) }
        guard parts.count >= 3 else { return nil }
        let n = Double(parts.count)
        return Week(start: start,
                    resting: parts.reduce(0) { $0 + $1.resting } / n,
                    exercise: parts.reduce(0) { $0 + $1.exercise } / n,
                    neat: parts.reduce(0) { $0 + $1.neat } / n,
                    digestion: parts.reduce(0) { $0 + $1.digestion } / n)
    }

    static func breakdown(from all: [DailyMetrics]) -> Breakdown? {
        let days = all.chronological
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var weeks: [Week] = []
        for back in stride(from: 7, through: 0, by: -1) {
            guard let end = calendar.date(byAdding: .day, value: -7 * back, to: today),
                  let start = calendar.date(byAdding: .day, value: -6, to: end) else { continue }
            if let week = average(days.filter { $0.date >= start && $0.date <= end }, start: start) {
                weeks.append(week)
            }
        }

        let recentDays = days.lastDays(14)
        guard let recent = average(recentDays, start: recentDays.first?.date ?? today) else { return nil }
        let baselineDays = days.filter { d in
            guard let from = calendar.date(byAdding: .day, value: -56, to: today),
                  let to = calendar.date(byAdding: .day, value: -14, to: today) else { return false }
            return d.date >= from && d.date < to
        }
        let baseline = average(baselineDays, start: today)
        return Breakdown(weeks: weeks, recent: recent, neatRecent: recent.neat,
                         neatBaseline: baselineDays.compactMap { components($0) }.count >= 10 ? baseline?.neat : nil)
    }
}

// MARK: - 4. Heart-rate recovery

enum HeartRateRecoveryModel {
    enum Band {
        case low, normal, good, excellent

        init(_ bpm: Double) {
            switch bpm {
            case ...12:   self = .low
            case ..<21:   self = .normal
            case ..<30:   self = .good
            default:      self = .excellent
            }
        }

        var label: String {
            switch self {
            case .low:       String(localized: "Below 12 bpm")
            case .normal:    String(localized: "Normal")
            case .good:      String(localized: "Good")
            case .excellent: String(localized: "Excellent")
            }
        }

        var color: Color {
            switch self {
            case .low:       Theme.bad
            case .normal:    Theme.warn
            case .good:      Theme.good
            case .excellent: Theme.good
            }
        }
    }

    struct Summary {
        let latest: TrendPoint
        let recentAverage: Double
        let previousAverage: Double?
        let points: [TrendPoint]
        var band: Band { Band(recentAverage) }
    }

    static func summary(from all: [DailyMetrics]) -> Summary? {
        let points = all.chronological.compactMap { d in d.heartRateRecovery.map { TrendPoint(date: d.date, value: $0) } }
        guard let latest = points.last else { return nil }
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let previousCutoff = calendar.date(byAdding: .day, value: -180, to: Date()) ?? Date()
        let recent = points.filter { $0.date >= cutoff }.map(\.value)
        let previous = points.filter { $0.date >= previousCutoff && $0.date < cutoff }.map(\.value)
        return Summary(latest: latest, recentAverage: Stats.mean(recent) ?? latest.value,
                       previousAverage: previous.count >= 3 ? Stats.mean(previous) : nil,
                       points: points.filter { $0.date >= previousCutoff })
    }
}

// MARK: - 5. VO₂ max & fitness age

enum FitnessModel {
    enum Category: Int, CaseIterable {
        case poor, fair, good, excellent, superior

        var label: String {
            switch self {
            case .poor:      String(localized: "Poor")
            case .fair:      String(localized: "Fair")
            case .good:      String(localized: "Good")
            case .excellent: String(localized: "Excellent")
            case .superior:  String(localized: "Superior")
            }
        }

        var color: Color {
            switch self {
            case .poor:      Theme.bad
            case .fair:      Theme.warn
            case .good:      Theme.accent
            case .excellent: Theme.good
            case .superior:  Theme.good
            }
        }
    }

    /// Lower bounds of fair / good / excellent / superior, ml/kg/min, by age
    /// decade. Approximated from Cooper Institute / ACSM norm tables.
    static func thresholds(age: Int, female: Bool) -> [Double] {
        let male: [[Double]] = [[38, 43, 49, 56], [35, 41, 46, 53], [33, 38, 43, 50], [30, 35, 40, 47], [26, 31, 36, 43]]
        let band = min(max((age - 20) / 10, 0), 4)
        return male[band].map { female ? $0 - 6 : $0 }
    }

    struct Summary {
        let latest: TrendPoint
        let category: Category
        let thresholds: [Double]
        let fitnessAge: Int?
        let age: Int?
        let female: Bool
        let points: [TrendPoint]
        let changePerYear: Double?
    }

    static func summary(from all: [DailyMetrics], profile: BodyProfile) -> Summary? {
        let points = all.chronological.compactMap { d in d.vo2Max.map { TrendPoint(date: d.date, value: $0) } }
        guard let latest = points.last else { return nil }
        let female = profile.isFemale ?? false
        let age = profile.ageYears
        let limits = thresholds(age: age ?? 30, female: female)
        let category = Category(rawValue: limits.filter { latest.value >= $0 }.count) ?? .poor

        // Fitness age: the age at which your VO₂ max would be the typical
        // (median) value. Median ≈ 47 − 0.4 × (age − 25) for men, 6 lower for women.
        let adjusted = latest.value + (female ? 6 : 0)
        let fitnessAge = Int((25 + (47 - adjusted) / 0.4).rounded())

        var changePerYear: Double?
        if points.count >= 4, let first = points.first,
           latest.date.timeIntervalSince(first.date) > 60 * 86_400,
           let fit = Regression.fit(points.map { $0.date.timeIntervalSince(first.date) / 86_400 }, points.map(\.value)) {
            changePerYear = fit.slope * 365
        }

        return Summary(latest: latest, category: category, thresholds: limits,
                       fitnessAge: min(max(fitnessAge, 18), 90), age: age, female: female,
                       points: points, changePerYear: changePerYear)
    }
}

// MARK: - 6. Sleep coupling

enum SleepCouplingModel {
    struct Coupling: Identifiable {
        let id = UUID()
        let cause: String
        let effect: String
        let r: Double
        let n: Int
        let pValue: Double?
        /// What a positive r would mean in words, e.g. "higher HRV".
        let positiveMeaning: String
        let negativeMeaning: String

        var strength: String {
            switch abs(r) {
            case ..<0.1: String(localized: "no link")
            case ..<0.3: "weak"
            case ..<0.5: "moderate"
            default:     "strong"
            }
        }

        var isSignificant: Bool { (pValue ?? 1) < 0.05 }

        var sentence: String {
            guard abs(r) >= 0.1 else { return String(localized: "\(cause) shows no clear link with \(effect.lowercased()) so far.") }
            return String(localized: "More \(cause.lowercased()) goes with \(r > 0 ? positiveMeaning : negativeMeaning).")
        }
    }

    struct Result {
        let scatter: [(x: Double, y: Double)]
        let deepHRV: Coupling?
        let couplings: [Coupling]
        let deepShare: Double?
        let remShare: Double?
        let efficiency: Double?
    }

    private static func couple(_ pairs: [(Double, Double)], cause: String, effect: String,
                               positive: String, negative: String) -> Coupling? {
        guard pairs.count >= 14, let r = Stats.pearson(pairs.map(\.0), pairs.map(\.1)) else { return nil }
        return Coupling(cause: cause, effect: effect, r: r, n: pairs.count,
                        pValue: Stats.correlationPValue(r: r, n: pairs.count),
                        positiveMeaning: positive, negativeMeaning: negative)
    }

    static func analyse(from all: [DailyMetrics]) -> Result? {
        let days = all.chronological.lastDays(120)
        guard days.filter({ ($0.sleepAsleepHours ?? 0) > 0 }).count >= 14 else { return nil }

        let deepHRV = days.compactMap { d -> (Double, Double)? in
            guard let deep = d.sleepDeepHours, deep > 0, let hrv = d.hrvSDNN else { return nil }
            return (deep * 60, hrv)
        }

        var couplings: [Coupling] = []
        if let c = couple(deepHRV, cause: String(localized: "Deep sleep"), effect: String(localized: "HRV next morning"),
                          positive: String(localized: "higher HRV the next morning"), negative: String(localized: "lower HRV the next morning")) { couplings.append(c) }
        if let c = couple(days.compactMap { d in d.sleepAsleepHours.flatMap { s in d.restingHeartRate.map { (s, $0) } } },
                          cause: String(localized: "Sleep"), effect: String(localized: "Resting heart rate"),
                          positive: String(localized: "a higher resting heart rate"), negative: String(localized: "a lower resting heart rate")) { couplings.append(c) }
        if let c = couple(days.compactMap { d in d.respiratoryRate.flatMap { b in d.hrvSDNN.map { (b, $0) } } },
                          cause: String(localized: "Breathing rate"), effect: String(localized: "HRV"),
                          positive: String(localized: "higher HRV"), negative: String(localized: "lower HRV — a sign of autonomic load")) { couplings.append(c) }
        if let c = couple(days.compactMap { d in d.sleepAsleepHours.flatMap { s in d.steps.map { (s, $0) } } },
                          cause: String(localized: "Sleep"), effect: String(localized: "Steps that day"),
                          positive: String(localized: "more movement that day"), negative: String(localized: "less movement that day")) { couplings.append(c) }
        if let c = couple(days.compactMap { d in d.sleepAsleepHours.flatMap { s in d.dietaryEnergyKcal.map { (s, $0) } } },
                          cause: String(localized: "Sleep"), effect: String(localized: "Calories eaten that day"),
                          positive: String(localized: "eating more that day"), negative: String(localized: "eating less that day — short nights tend to raise appetite")) { couplings.append(c) }

        // Strain today against deep sleep the following night.
        var strainDeep: [(Double, Double)] = []
        for (today, next) in zip(days, days.dropFirst()) {
            if let strain = today.strain, let deep = next.sleepDeepHours, deep > 0 { strainDeep.append((strain, deep * 60)) }
        }
        if let c = couple(strainDeep, cause: String(localized: "Day strain"), effect: String(localized: "Deep sleep that night"),
                          positive: String(localized: "more deep sleep that night"), negative: String(localized: "less deep sleep that night")) { couplings.append(c) }

        let nights = days.filter { ($0.sleepAsleepHours ?? 0) > 0 }
        func share(_ keyPath: KeyPath<DailyMetrics, Double?>) -> Double? {
            Stats.mean(nights.compactMap { n in n[keyPath: keyPath].map { $0 / (n.sleepAsleepHours ?? 1) * 100 } })
        }
        let efficiency = Stats.mean(nights.compactMap { n -> Double? in
            guard let asleep = n.sleepAsleepHours, let inBed = n.sleepDurationHours, inBed > 0 else { return nil }
            return min(asleep / inBed * 100, 100)
        })

        return Result(scatter: deepHRV.map { (x: $0.0, y: $0.1) },
                      deepHRV: couplings.first { $0.cause == "Deep sleep" },
                      couplings: couplings.sorted { abs($0.r) > abs($1.r) },
                      deepShare: share(\.sleepDeepHours), remShare: share(\.sleepREMHours), efficiency: efficiency)
    }
}

// MARK: - 7. Activity spectrum

enum ActivitySpectrumModel {
    struct Week: Identifiable {
        let id = UUID()
        let start: Date
        let light: Double
        let moderate: Double
        let vigorous: Double
        /// WHO counts a vigorous minute as two moderate ones.
        var moderateEquivalent: Double { moderate + 2 * vigorous }
    }

    enum Source { case heartRate, exerciseRing }

    struct Summary {
        let weeks: [Week]
        let last7: Week
        let source: Source

        var guidelineMet: Bool { last7.moderateEquivalent >= 150 }
    }

    static func summary(from all: [DailyMetrics]) -> Summary? {
        let days = all.chronological
        let hasHeartRate = days.lastDays(28).contains { $0.moderateMinutes != nil }
        let hasRing = days.lastDays(28).contains { $0.exerciseMinutes != nil }
        guard hasHeartRate || hasRing else { return nil }
        let source: Source = hasHeartRate ? .heartRate : .exerciseRing

        func total(_ slice: [DailyMetrics], start: Date) -> Week {
            switch source {
            case .heartRate:
                Week(start: start,
                     light: slice.compactMap(\.lightMinutes).reduce(0, +),
                     moderate: slice.compactMap(\.moderateMinutes).reduce(0, +),
                     vigorous: slice.compactMap(\.vigorousMinutes).reduce(0, +))
            case .exerciseRing:
                Week(start: start, light: 0, moderate: slice.compactMap(\.exerciseMinutes).reduce(0, +), vigorous: 0)
            }
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var weeks: [Week] = []
        for back in stride(from: 7, through: 0, by: -1) {
            guard let end = calendar.date(byAdding: .day, value: -7 * back, to: today),
                  let start = calendar.date(byAdding: .day, value: -6, to: end) else { continue }
            let slice = days.filter { $0.date >= start && $0.date <= end }
            guard slice.contains(where: { source == .heartRate ? $0.moderateMinutes != nil : $0.exerciseMinutes != nil }) else { continue }
            weeks.append(total(slice, start: start))
        }
        guard let last = weeks.last else { return nil }
        return Summary(weeks: weeks, last7: last, source: source)
    }
}

// MARK: - 8. Mobility

enum MobilityModel {
    struct Metric: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let unit: String
        let decimals: Int
        let previous: Double?
        let verdict: String
        let color: Color
        let higherIsBetter: Bool?
    }

    struct Summary {
        let metrics: [Metric]
        let speedWeeks: [TrendPoint]
        let speed: Double?
    }

    static func summary(from all: [DailyMetrics]) -> Summary? {
        let days = all.chronological
        let calendar = Calendar.current
        let recentStart = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let previousStart = calendar.date(byAdding: .day, value: -120, to: Date()) ?? Date()

        func means(_ keyPath: KeyPath<DailyMetrics, Double?>) -> (Double, Double?)? {
            let recent = days.filter { $0.date >= recentStart }.compactMap { $0[keyPath: keyPath] }
            guard recent.count >= 3, let mean = Stats.mean(recent) else { return nil }
            let previous = days.filter { $0.date >= previousStart && $0.date < recentStart }.compactMap { $0[keyPath: keyPath] }
            return (mean, previous.count >= 5 ? Stats.mean(previous) : nil)
        }

        var metrics: [Metric] = []
        var speedValue: Double?
        if let (speed, before) = means(\.walkingSpeed) {
            speedValue = speed
            let (verdict, color): (String, Color) = switch speed {
            case 1.3...:     ("Brisk", Theme.good)
            case 1.0..<1.3:  ("Healthy range", Theme.good)
            case 0.8..<1.0:  ("Slower than typical", Theme.warn)
            default:         ("Frailty-risk range", Theme.bad)
            }
            metrics.append(.init(label: String(localized: "Walking speed"), value: speed * 3.6, unit: String(localized: "km/h"), decimals: 1,
                                 previous: before.map { $0 * 3.6 }, verdict: verdict, color: color, higherIsBetter: true))
        }
        if let (length, before) = means(\.walkingStepLength) {
            metrics.append(.init(label: String(localized: "Step length"), value: length, unit: "cm", decimals: 0, previous: before,
                                 verdict: String(localized: "Longer usually means more power"), color: Theme.textTertiary, higherIsBetter: true))
        }
        if let (asymmetry, before) = means(\.walkingAsymmetry) {
            metrics.append(.init(label: String(localized: "Asymmetry"), value: asymmetry, unit: "%", decimals: 1, previous: before,
                                 verdict: asymmetry < 5 ? String(localized: "Typical (under ~5%)") : String(localized: "Uneven — worth watching"),
                                 color: asymmetry < 5 ? Theme.good : Theme.warn, higherIsBetter: false))
        }
        if let (support, before) = means(\.walkingDoubleSupport) {
            let typical = (20...40).contains(support)
            metrics.append(.init(label: String(localized: "Double support"), value: support, unit: "%", decimals: 1, previous: before,
                                 verdict: typical ? String(localized: "Typical (20–40%)") : (support > 40 ? String(localized: "Cautious gait") : String(localized: "Below typical")),
                                 color: typical ? Theme.good : Theme.warn, higherIsBetter: false))
        }
        if let (steadiness, before) = means(\.walkingSteadiness) {
            metrics.append(.init(label: String(localized: "Steadiness"), value: steadiness, unit: "%", decimals: 0, previous: before,
                                 verdict: String(localized: "Apple's fall-risk score, higher is steadier"), color: Theme.textTertiary, higherIsBetter: true))
        }
        guard !metrics.isEmpty else { return nil }

        let speedPoints = days.compactMap { d in d.walkingSpeed.map { TrendPoint(date: d.date, value: $0 * 3.6) } }
        return Summary(metrics: metrics, speedWeeks: speedPoints.bucketed(.week), speed: speedValue)
    }
}

// MARK: - 9. Allostatic load

enum AllostaticLoadModel {
    struct Component: Identifiable {
        let id = UUID()
        let label: String
        /// Positive = more wear than your normal.
        let z: Double
        let inWorstQuartile: Bool
    }

    struct Summary {
        let index: Double
        let components: [Component]
        let weeks: [TrendPoint]
        let weeksOfHistory: Int

        var highRiskCount: Int { components.filter(\.inWorstQuartile).count }

        var label: String {
            switch index {
            case ..<(-0.5): String(localized: "Lower than your normal")
            case ..<0.5:    String(localized: "Typical for you")
            case ..<1.0:    String(localized: "Elevated")
            default:        String(localized: "High")
            }
        }

        var color: Color {
            switch index {
            case ..<0.5: Theme.good
            case ..<1.0: Theme.warn
            default:     Theme.bad
            }
        }
    }

    private struct Input {
        let label: String
        /// +1 when a higher value means more wear.
        let direction: Double
        let value: (DailyMetrics) -> Double?
    }

    private static let inputs: [Input] = [
        Input(label: String(localized: "Resting HR"), direction: 1) { $0.restingHeartRate },
        Input(label: String(localized: "HRV"), direction: -1) { $0.hrvSDNN },
        Input(label: String(localized: "HR recovery"), direction: -1) { $0.heartRateRecovery },
        Input(label: String(localized: "Sleep"), direction: -1) { $0.sleepAsleepHours },
        Input(label: String(localized: "Active minutes"), direction: -1) { d in
            if let m = d.moderateMinutes { return m + 2 * (d.vigorousMinutes ?? 0) }
            return d.exerciseMinutes
        },
        Input(label: String(localized: "Breathing rate"), direction: 1) { $0.respiratoryRate }
    ]

    static func summary(from all: [DailyMetrics]) -> Summary? {
        let days = all.chronological
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Rolling 7-day blocks going back up to a year.
        var blocks: [(start: Date, days: [DailyMetrics])] = []
        for back in stride(from: 51, through: 0, by: -1) {
            guard let end = calendar.date(byAdding: .day, value: -7 * back, to: today),
                  let start = calendar.date(byAdding: .day, value: -6, to: end) else { continue }
            let slice = days.filter { $0.date >= start && $0.date <= end }
            if !slice.isEmpty { blocks.append((start, slice)) }
        }

        // Weekly mean of each input, then each week's z against that input's own weekly history.
        var zByWeek: [Date: [Double]] = [:]
        var latestComponents: [Component] = []
        for input in inputs {
            let weekly = blocks.compactMap { block -> (Date, Double)? in
                let values = block.days.compactMap(input.value)
                return values.count >= 3 ? (block.start, Stats.mean(values)!) : nil
            }
            guard weekly.count >= 8, let mean = Stats.mean(weekly.map(\.1)),
                  let sd = Stats.standardDeviation(weekly.map(\.1)), sd > 0 else { continue }
            for (start, value) in weekly {
                zByWeek[start, default: []].append((value - mean) / sd * input.direction)
            }
            if let last = weekly.last, calendar.isDate(last.0, inSameDayAs: blocks.last?.start ?? .distantPast) {
                let z = (last.1 - mean) / sd * input.direction
                let adverse = weekly.map { ($0.1 - mean) / sd * input.direction }.sorted()
                let q3 = adverse[Int(Double(adverse.count - 1) * 0.75)]
                latestComponents.append(.init(label: input.label, z: z, inWorstQuartile: z >= q3))
            }
        }

        guard latestComponents.count >= 3 else { return nil }
        let weeks = zByWeek
            .filter { $0.value.count >= 3 }
            .map { TrendPoint(date: $0.key, value: $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
        let index = latestComponents.reduce(0) { $0 + $1.z } / Double(latestComponents.count)
        return Summary(index: index, components: latestComponents, weeks: weeks, weeksOfHistory: blocks.count)
    }
}
