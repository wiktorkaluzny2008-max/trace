//
//  AdaptiveMaintenance.swift
//  RecoverySignal2
//
//  Maintenance calories that learn from you. It starts from what the Watch
//  says you burn, then every day you log food it checks what your body did
//  with it: if you ate 2,500 kcal and your trend weight held still, 2,500 was
//  maintenance; if trend weight dropped, maintenance must be higher.
//
//    trend weight  W̃   = EWMA (span 10) of daily weight, gaps interpolated
//    implied burn  eₜ  = intakeₜ − (W̃ₜ − W̃ₜ₋₁) × 7,700
//    maintenance   Mₜ  = Mₜ₋₁ + α (eₜ − Mₜ₋₁),  α = 2 ÷ (21 + 1)
//    M₀ = Watch maintenance estimate
//
//  A 21-day span lets it respond within two to three weeks while a single
//  big day or water swing barely moves it. Each day's implied burn is capped
//  at ±1,000 kcal from the current estimate so one mis-logged day can't
//  lurch the number. Once there are 10+ logged days in the last four weeks,
//  calorie and macro targets switch from the Watch estimate to this one.
//

import Foundation

enum AdaptiveMaintenance {

    static let span = 21.0
    static let dailyCap = 1000.0

    enum Confidence: Int, Comparable {
        case learning, medium, high

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .learning: String(localized: "Learning")
            case .medium:   String(localized: "Medium confidence")
            case .high:     String(localized: "High confidence")
            }
        }
    }

    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let maintenance: Double
        let trendWeight: Double
        let intake: Double?
    }

    struct Estimate {
        let value: Double
        /// Where it started: the Watch (or formula) maintenance.
        let starting: Double
        let series: [Point]
        let loggedDays: Int
        let confidence: Confidence
        /// Change over the last 14 days.
        let changeTwoWeeks: Double?
        let averageIntake: Double?
        let trendChangePerWeek: Double?

        var isActive: Bool { confidence >= .medium }

        /// A plain-English account of the latest adjustment.
        var explanation: String {
            guard let intake = averageIntake, let rate = trendChangePerWeek else {
                return String(localized: "Log your food and weigh in regularly — each day refines this number.")
            }
            let intakeText = Int(intake.rounded()).formatted()
            if abs(rate) < 0.1 {
                return String(localized: "You've averaged \(intakeText) kcal and your trend weight has held steady, so maintenance sits close to what you eat.")
            }
            return rate < 0
                ? String(localized: "You've averaged \(intakeText) kcal while your trend weight fell \(abs(rate).formatted(.number.precision(.fractionLength(2)))) kg/week — so you burn more than you eat.")
                : String(localized: "You've averaged \(intakeText) kcal while your trend weight rose \(rate.formatted(.number.precision(.fractionLength(2)))) kg/week — so you burn less than you eat.")
        }
    }

    /// `excluded` (sick or travel days) are treated as not logged: illness and
    /// travel both disrupt digestion, activity and appetite enough that the
    /// day's intake-vs-weight relationship isn't a reliable read on maintenance.
    static func compute(from all: [DailyMetrics], starting: Double, lookbackDays: Int = 120, excluded: Set<Date> = []) -> Estimate? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return nil }
        // Completed days only — today's intake is still being logged.
        let days = all.filter { $0.date >= start && $0.date < today }.sorted { $0.date < $1.date }

        let weighIns = days.compactMap { d in d.bodyMassKg.map { (d.date, $0) } }
        guard weighIns.count >= 3, let firstWeighIn = weighIns.first?.0 else { return nil }

        // One weight per calendar day from the first weigh-in, linearly
        // interpolated between readings and held flat after the last.
        var dailyWeights: [(Date, Double)] = []
        var day = firstWeighIn
        var cursor = 0
        while day < today {
            while cursor + 1 < weighIns.count, weighIns[cursor + 1].0 <= day { cursor += 1 }
            let (d0, w0) = weighIns[cursor]
            if cursor + 1 < weighIns.count {
                let (d1, w1) = weighIns[cursor + 1]
                let t = day.timeIntervalSince(d0) / d1.timeIntervalSince(d0)
                dailyWeights.append((day, w0 + (w1 - w0) * t))
            } else {
                dailyWeights.append((day, w0))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let trend = Stats.ewmaSeries(dailyWeights.map(\.1), span: 10)
        let intakeByDay = Dictionary(days.compactMap { d -> (Date, Double)? in
            guard !excluded.contains(Calendar.current.startOfDay(for: d.date)) else { return nil }
            return d.dietaryEnergyKcal.flatMap { $0 > 500 ? (d.date, $0) : nil }
        }, uniquingKeysWith: { a, _ in a })
        let alpha = 2 / (span + 1)

        var maintenance = starting
        var series: [Point] = []
        for i in dailyWeights.indices {
            let date = dailyWeights[i].0
            let intake = intakeByDay[date]
            if i > 0, let intake {
                let implied = intake - (trend[i] - trend[i - 1]) * EnergyModel.kcalPerKg
                let capped = min(max(implied, maintenance - dailyCap), maintenance + dailyCap)
                maintenance += alpha * (capped - maintenance)
            }
            series.append(Point(date: date, maintenance: maintenance, trendWeight: trend[i], intake: intake))
        }
        guard let last = series.last else { return nil }

        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today) ?? today
        let logged = series.filter { $0.date >= fourWeeksAgo && $0.intake != nil }.count
        let confidence: Confidence = logged >= 21 && weighIns.count >= 10 ? .high : (logged >= 10 ? .medium : .learning)

        let recent = series.filter { $0.date >= twoWeeksAgo }
        let before = series.last { $0.date < twoWeeksAgo }
        var trendRate: Double?
        if let first = recent.first, recent.count >= 7 {
            trendRate = (last.trendWeight - first.trendWeight) / Double(recent.count - 1) * 7
        }

        return Estimate(value: last.maintenance, starting: starting, series: series, loggedDays: logged,
                        confidence: confidence,
                        changeTwoWeeks: before.map { last.maintenance - $0.maintenance },
                        averageIntake: Stats.mean(recent.compactMap(\.intake)),
                        trendChangePerWeek: trendRate)
    }
}

extension MaintenanceEstimate {
    /// The same breakdown with the total replaced by the adaptive figure.
    func adapted(to total: Double) -> MaintenanceEstimate {
        MaintenanceEstimate(total: total, resting: resting, activity: activity, digestion: digestion,
                            restingSource: restingSource, daysUsed: daysUsed)
    }
}
