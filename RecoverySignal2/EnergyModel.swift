//
//  EnergyModel.swift
//  RecoverySignal2
//
//  Metabolic modelling that adapts to you rather than assuming a formula:
//   • Adaptive TDEE from the relationship between logged intake and actual
//     weight trend (the MacroFactor approach), which catches the metabolic
//     adaptation a fixed Mifflin-St Jeor number misses entirely.
//   • Energy Availability, the RED-S screening metric (Loucks).
//   • P-ratio, how a surplus or deficit is being partitioned.
//
//  EA and P-ratio need fat-free mass, so they stay dormant until a smart scale
//  (or manual entry) puts body fat % or lean mass into Health.
//

import Foundation
import SwiftUI

enum EnergyModel {

    /// Energy density of body mass change. 7700 kcal/kg is the conventional
    /// figure; it's an approximation that ignores glycogen and water swings,
    /// which is exactly why the weight series is smoothed first.
    static let kcalPerKg = 7700.0

    // MARK: - Adaptive TDEE

    struct TDEEEstimate {
        let value: Double              // kcal/day
        let averageIntake: Double
        let weightChangePerWeek: Double  // kg
        let windowDays: Int
        /// Rough ± band, widened when the weight series is noisy.
        let uncertainty: Double
    }

    /// Regresses EWMA-smoothed weight against logged intake over a trailing
    /// window. Requires both weight and intake on enough days to be meaningful.
    static func adaptiveTDEE(from days: [DailyMetrics], window: Int = 21) -> TDEEEstimate? {
        let sorted = days.sorted { $0.date < $1.date }.suffix(window)

        let paired = sorted.compactMap { day -> (weight: Double, intake: Double)? in
            guard let w = day.bodyMassKg, let i = day.dietaryEnergyKcal, i > 0 else { return nil }
            return (w, i)
        }
        guard paired.count >= 14 else { return nil }

        let smoothedWeights = Stats.ewmaSeries(paired.map(\.weight), span: 7)
        guard let slopePerDay = Stats.slope(smoothedWeights),
              let averageIntake = Stats.mean(paired.map(\.intake)) else { return nil }

        let tdee = averageIntake - slopePerDay * kcalPerKg

        // Uncertainty scales with how much the raw weight scatters around the
        // smoothed line — water-weight noise makes the estimate less certain.
        let residuals = zip(paired.map(\.weight), smoothedWeights).map { $0 - $1 }
        let scatter = Stats.standardDeviation(residuals) ?? 0
        let uncertainty = max(60, scatter * kcalPerKg / Double(paired.count).squareRoot())

        return TDEEEstimate(
            value: tdee,
            averageIntake: averageIntake,
            weightChangePerWeek: slopePerDay * 7,
            windowDays: paired.count,
            uncertainty: uncertainty
        )
    }

    // MARK: - Maintenance calories & daily targets

    /// Maintenance used for targets: the adaptive figure once it has learned
    /// enough from your intake and weight, otherwise the Watch estimate.
    static func maintenance(from days: [DailyMetrics], profile: BodyProfile = .load(), excluded: Set<Date> = []) -> MaintenanceEstimate? {
        guard let watch = watchMaintenance(from: days, profile: profile) else { return nil }
        if let adaptive = AdaptiveMaintenance.compute(from: days, starting: watch.total, excluded: excluded), adaptive.isActive {
            return watch.adapted(to: adaptive.value)
        }
        return watch
    }

    /// Resting + activity + digestion, from recent completed days. See MaintenanceModel.
    static func watchMaintenance(from days: [DailyMetrics], profile: BodyProfile = .load()) -> MaintenanceEstimate? {
        MaintenanceModel.estimate(days: days.map { dayEnergy($0) }, profile: profile)
    }

    static func adaptiveMaintenance(from days: [DailyMetrics], profile: BodyProfile = .load(), excluded: Set<Date> = []) -> AdaptiveMaintenance.Estimate? {
        guard let watch = watchMaintenance(from: days, profile: profile) else { return nil }
        return AdaptiveMaintenance.compute(from: days, starting: watch.total, excluded: excluded)
    }

    /// Calorie and macro targets for holding weight at that maintenance level.
    /// Maintenance-based targets, remembered until the data or settings change
    /// (see DerivedCache). For callers that run often, like the minute refresh.
    static func cachedTargets(from days: [DailyMetrics]) -> NutritionTargets? {
        DerivedCache.value("energy.targets", inputs: DaysSignature(days)) {
            maintenance(from: days).map { targets(from: days, maintenance: $0) }
        }
    }

    static func targets(from days: [DailyMetrics], maintenance: MaintenanceEstimate) -> NutritionTargets {
        NutritionTargets(maintenance: maintenance,
                         bodyMassKg: MaintenanceModel.latestBodyMass(days.map { dayEnergy($0) }))
    }

    private static func dayEnergy(_ day: DailyMetrics) -> DayEnergy {
        DayEnergy(date: day.date, restingKcal: day.basalEnergyKcal,
                  activeKcal: day.activeEnergyBurned, bodyMassKg: day.bodyMassKg)
    }

    // MARK: - Energy availability

    struct EnergyAvailability {
        let kcalPerKgFFM: Double
        let fatFreeMass: Double
        let status: Status
        let days: Int

        enum Status {
            case low, reduced, optimal

            var label: String {
                switch self {
                case .low:      String(localized: "Low")
                case .reduced:  String(localized: "Reduced")
                case .optimal:  String(localized: "Adequate")
                }
            }

            var color: Color {
                switch self {
                case .low:      Theme.bad
                case .reduced:  Theme.warn
                case .optimal:  Theme.good
                }
            }

            var explanation: String {
                switch self {
                case .low:
                    String(localized: "Below ~30 kcal/kg FFM/day is the threshold associated with RED-S — hormonal, bone-density and recovery consequences, not just slower progress.")
                case .reduced:
                    String(localized: "Between 30 and 45 kcal/kg FFM/day. Sustainable short-term for a deliberate cut, but not a place to live.")
                case .optimal:
                    String(localized: "At or above ~45 kcal/kg FFM/day, the range generally considered adequate to support training and hormonal function.")
                }
            }
        }
    }

    /// EA = (intake − exercise energy) / fat-free mass, averaged over a week.
    static func energyAvailability(from days: [DailyMetrics], window: Int = 7) -> EnergyAvailability? {
        let sorted = days.sorted { $0.date < $1.date }.suffix(window)
        guard let ffm = latestFatFreeMass(in: days), ffm > 0 else { return nil }

        let values = sorted.compactMap { day -> Double? in
            guard let intake = day.dietaryEnergyKcal, intake > 0 else { return nil }
            let exercise = day.workoutEnergyKcal ?? 0
            return (intake - exercise) / ffm
        }
        guard values.count >= 4, let mean = Stats.mean(values) else { return nil }

        let status: EnergyAvailability.Status = mean < 30 ? .low : (mean < 45 ? .reduced : .optimal)
        return EnergyAvailability(kcalPerKgFFM: mean, fatFreeMass: ffm, status: status, days: values.count)
    }

    /// Prefers a directly measured lean mass; otherwise derives it from body fat %.
    static func latestFatFreeMass(in days: [DailyMetrics]) -> Double? {
        let sorted = days.sorted { $0.date < $1.date }
        if let lean = sorted.compactMap(\.leanBodyMassKg).last { return lean }
        guard let weight = sorted.compactMap(\.bodyMassKg).last,
              let fatPercent = sorted.compactMap(\.bodyFatPercent).last else { return nil }
        return weight * (1 - fatPercent / 100)
    }

    // MARK: - P-ratio

    struct PRatio {
        let value: Double          // share of the change that was lean mass
        let deltaFFM: Double       // kg
        let deltaFatMass: Double   // kg
        let windowDays: Int

        var interpretation: String {
            if deltaFFM + deltaFatMass > 0 {
                return value >= 0.5
                    ? String(localized: "Most of what you've added is lean mass — the surplus looks well dosed.")
                    : String(localized: "More than half of the gain is fat mass, which usually means the surplus is larger than it needs to be.")
            } else {
                return value <= 0.2
                    ? String(localized: "Most of what you've lost is fat, with lean mass largely preserved.")
                    : String(localized: "A meaningful share of the loss is lean mass — worth raising protein or easing the deficit.")
            }
        }
    }

    /// Partitioning over a multi-week window. Bioimpedance is noisy day to day,
    /// so this deliberately needs a long window and a non-trivial total change.
    static func pRatio(from days: [DailyMetrics], window: Int = 42) -> PRatio? {
        let sorted = days.sorted { $0.date < $1.date }.suffix(window)

        let points = sorted.compactMap { day -> (ffm: Double, fat: Double)? in
            guard let weight = day.bodyMassKg else { return nil }
            let ffm: Double
            if let lean = day.leanBodyMassKg {
                ffm = lean
            } else if let bf = day.bodyFatPercent {
                ffm = weight * (1 - bf / 100)
            } else {
                return nil
            }
            return (ffm, weight - ffm)
        }
        guard points.count >= 14 else { return nil }

        // Smooth both ends to take the edge off scale noise.
        let smoothedFFM = Stats.ewmaSeries(points.map(\.ffm), span: 7)
        let smoothedFat = Stats.ewmaSeries(points.map(\.fat), span: 7)
        guard let ffmStart = smoothedFFM.first, let ffmEnd = smoothedFFM.last,
              let fatStart = smoothedFat.first, let fatEnd = smoothedFat.last else { return nil }

        let deltaFFM = ffmEnd - ffmStart
        let deltaFat = fatEnd - fatStart
        let total = deltaFFM + deltaFat
        guard abs(total) >= 0.5 else { return nil }   // too small to read through the noise

        return PRatio(value: deltaFFM / total, deltaFFM: deltaFFM, deltaFatMass: deltaFat, windowDays: points.count)
    }
}
