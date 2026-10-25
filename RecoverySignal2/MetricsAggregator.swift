//
//  MetricsAggregator.swift
//  RecoverySignal
//
//  Pulls raw HealthKit data for a date range and turns it into DailyMetrics
//  rows in SwiftData. Safe to call repeatedly (e.g. on every background wake
//  or app foreground) — it upserts by date rather than duplicating.
//

import Foundation
import HealthKit
import SwiftData

@MainActor
final class MetricsAggregator {
    let context: ModelContext
    let health = HealthKitManager.shared

    init(context: ModelContext) {
        self.context = context
    }

    /// How far back the first refresh reaches, so Trends can show a year and
    /// comparisons like "vs your 6-month average" have history behind them.
    static let historyDays = 365
    private static let backfillKey = "historyBackfilledDays"
    /// Heart-rate streams are heavy to query; strain and intensity minutes are
    /// only recomputed for this recent stretch, older days keep their values.
    private static let heartRateWindowDays = 45

    /// Refreshes the last `days` days (inclusive of today) of DailyMetrics. The
    /// very first run reaches back a full year instead.
    func refresh(days requestedDays: Int = 30) async throws {
        #if DEBUG && targetEnvironment(simulator)
        // Development only: `-seedLocal` fills the store without Health; don't wipe it.
        if ProcessInfo.processInfo.arguments.contains("-seedLocal") { return }
        #endif
        // One refresh at a time: otherwise an older read of Health can finish
        // last and overwrite newer numbers (like food you just logged).
        let previous = Self.inFlight
        let run = Task { @MainActor in
            _ = await previous?.result
            try await refreshSerial(days: requestedDays)
        }
        Self.inFlight = run
        try await run.value
    }

    @MainActor private static var inFlight: Task<Void, Error>?

    private func refreshSerial(days requestedDays: Int) async throws {
        let defaults = UserDefaults.standard
        let needsBackfill = defaults.integer(forKey: Self.backfillKey) < Self.historyDays
        let days = needsBackfill ? max(requestedDays, Self.historyDays) : requestedDays
        try await refreshWindow(days: days)
        if needsBackfill { defaults.set(Self.historyDays, forKey: Self.backfillKey) }
    }

    private func refreshWindow(days: Int) async throws {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return }

        async let hrv = health.dailyValues(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), style: .average, from: startDate, to: endDate)
        async let rhr = health.dailyValues(for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), style: .average, from: startDate, to: endDate)
        async let vo2 = health.dailyValues(for: .vo2Max, unit: HKUnit(from: "ml/kg*min"), style: .average, from: startDate, to: endDate)
        async let spo2 = health.dailyValues(for: .oxygenSaturation, unit: .percent(), style: .average, from: startDate, to: endDate)
        async let steps = health.dailyValues(for: .stepCount, unit: .count(), style: .sum, from: startDate, to: endDate)
        async let activeEnergy = health.dailyValues(for: .activeEnergyBurned, unit: .kilocalorie(), style: .sum, from: startDate, to: endDate)
        async let bodyMass = health.dailyValues(for: .bodyMass, unit: .gramUnit(with: .kilo), style: .average, from: startDate, to: endDate)
        // Food can be logged ahead of time. Read the whole local nutrition day;
        // physiological signals still stop at now. Health remains the single
        // aggregation source, so saved app entries are not counted twice.
        let nutritionEnd = FoodLogDate.nutritionQueryEnd(on: endDate, calendar: calendar)
        async let dietaryEnergy = health.dailyValues(for: .dietaryEnergyConsumed, unit: .kilocalorie(), style: .sum, from: calendar.startOfDay(for: startDate), to: nutritionEnd)
        async let protein = health.dailyValues(for: .dietaryProtein, unit: .gram(), style: .sum, from: calendar.startOfDay(for: startDate), to: nutritionEnd)
        async let carbs = health.dailyValues(for: .dietaryCarbohydrates, unit: .gram(), style: .sum, from: calendar.startOfDay(for: startDate), to: nutritionEnd)
        async let fat = health.dailyValues(for: .dietaryFatTotal, unit: .gram(), style: .sum, from: calendar.startOfDay(for: startDate), to: nutritionEnd)
        async let fiber = health.dailyValues(for: .dietaryFiber, unit: .gram(), style: .sum, from: calendar.startOfDay(for: startDate), to: nutritionEnd)
        async let sugar = health.dailyValues(for: .dietarySugar, unit: .gram(), style: .sum, from: calendar.startOfDay(for: startDate), to: nutritionEnd)
        async let water = health.dailyValues(for: .dietaryWater, unit: .literUnit(with: .milli), style: .sum, from: startDate, to: endDate)
        async let caffeine = health.dailyValues(for: .dietaryCaffeine, unit: .gramUnit(with: .milli), style: .sum, from: startDate, to: endDate)
        async let sleep = health.sleepByNight(from: startDate, to: endDate)
        async let workouts = health.workouts(from: startDate, to: endDate)

        let (hrvV, rhrV, vo2V, spo2V, stepsV, activeEnergyV, bodyMassV, dietaryEnergyV, proteinV, carbsV, fatV, fiberV, sugarV, waterV, caffeineV, sleepV, workoutsV) =
            try await (hrv, rhr, vo2, spo2, steps, activeEnergy, bodyMass, dietaryEnergy, protein, carbs, fat, fiber, sugar, water, caffeine, sleep, workouts)

        async let bodyFat = health.dailyValues(for: .bodyFatPercentage, unit: .percent(), style: .average, from: startDate, to: endDate)
        async let leanMass = health.dailyValues(for: .leanBodyMass, unit: .gramUnit(with: .kilo), style: .average, from: startDate, to: endDate)
        async let basalEnergy = health.dailyValues(for: .basalEnergyBurned, unit: .kilocalorie(), style: .sum, from: startDate, to: endDate)
        let (bodyFatV, leanMassV, basalEnergyV) = try await (bodyFat, leanMass, basalEnergy)

        // Height, age and sex change rarely; cache them for the maintenance formula.
        // Health's answer wins; anything Health doesn't know keeps what you entered in setup.
        var profile = await health.bodyProfile()
        let entered = BodyProfile.load()
        profile.heightCm = profile.heightCm ?? entered.heightCm
        profile.ageYears = profile.ageYears ?? entered.ageYears
        profile.isFemale = profile.isFemale ?? entered.isFemale
        profile.save()

        // HR max: measured beats assumed, but fall back to the age formula and
        // finally to a generic 190 so training load still has a scale.
        let restingBaseline = Stats.mean(Array(rhrV.values)) ?? 60
        let maxHR = (try? await health.observedMaxHeartRate())
            ?? health.ageBasedMaxHeartRate()
            ?? 190
        let coefficients = health.trimpCoefficients()

        // Breathing rate (the Watch measures it during sleep) and day strain
        // from heart rate across the whole day.
        let respiratoryV = (try? await health.dailyValues(for: .respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()),
                                                          style: .average, from: startDate, to: endDate)) ?? [:]
        // Watch Series 8+/Ultra only; empty on older Watches, which the model treats like any other missing input.
        let wristTempV = (try? await health.dailyValues(for: .appleSleepingWristTemperature, unit: .degreeCelsius(),
                                                         style: .average, from: startDate, to: endDate)) ?? [:]

        // How much of each day's caffeine came at or after 2pm — a fixed
        // sleep-hygiene cutoff (caffeine's ~5-6h half-life), not personalised.
        let caffeineSamples = (try? await health.caffeineSamples(from: startDate, to: endDate)) ?? []
        var lateCaffeineByDay: [Date: Double] = [:]
        for sample in caffeineSamples where calendar.component(.hour, from: sample.date) >= 14 {
            lateCaffeineByDay[calendar.startOfDay(for: sample.date), default: 0] += sample.mg
        }
        let heartRateStart = max(calendar.startOfDay(for: startDate),
                                 calendar.date(byAdding: .day, value: -Self.heartRateWindowDays, to: calendar.startOfDay(for: endDate)) ?? startDate)
        let heartRates = (try? await health.heartRateBuckets(from: heartRateStart, to: endDate)) ?? []
        let heartRatesByDay = Dictionary(grouping: heartRates) { calendar.startOfDay(for: $0.date) }

        // Fitness and mobility extras. Each is optional: plenty of people never
        // log a Workout-app session or carry their phone while walking.
        let bpm = HKUnit.count().unitDivided(by: .minute())
        func extra(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ style: HealthKitManager.AggregationStyle = .average) async -> [Date: Double] {
            (try? await health.dailyValues(for: id, unit: unit, style: style, from: startDate, to: endDate)) ?? [:]
        }
        let hrRecoveryV = await extra(.heartRateRecoveryOneMinute, bpm)
        let exerciseV = await extra(.appleExerciseTime, .minute(), .sum)
        let walkSpeedV = await extra(.walkingSpeed, HKUnit.meter().unitDivided(by: .second()))
        let stepLengthV = await extra(.walkingStepLength, .meterUnit(with: .centi))
        let asymmetryV = await extra(.walkingAsymmetryPercentage, .percent())
        let doubleSupportV = await extra(.walkingDoubleSupportPercentage, .percent())
        let steadinessV = await extra(.appleWalkingSteadiness, .percent())

        let workoutsByDay = try await summarizeWorkouts(
            workoutsV,
            calendar: calendar,
            restingByDay: rhrV,
            restingFallback: restingBaseline,
            maxHeartRate: maxHR,
            coefficients: coefficients
        )

        var day = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: endDate)
        while day <= today {
            let metrics = fetchOrCreate(for: day)
            assign(metrics, \.hrvSDNN, hrvV[day])
            assign(metrics, \.restingHeartRate, rhrV[day])
            assign(metrics, \.vo2Max, vo2V[day])
            assign(metrics, \.oxygenSaturation, spo2V[day])
            assign(metrics, \.steps, stepsV[day])
            assign(metrics, \.activeEnergyBurned, activeEnergyV[day])
            assign(metrics, \.basalEnergyKcal, basalEnergyV[day])
            assign(metrics, \.bodyMassKg, bodyMassV[day])
            assign(metrics, \.bodyFatPercent, bodyFatV[day].map { $0 * 100 })
            assign(metrics, \.leanBodyMassKg, leanMassV[day])
            assign(metrics, \.dietaryEnergyKcal, dietaryEnergyV[day])
            assign(metrics, \.respiratoryRate, respiratoryV[day])
            assign(metrics, \.wristTemperature, wristTempV[day])
            if day >= calendar.startOfDay(for: heartRateStart) {
                if let rates = heartRatesByDay[day], rates.count >= 2 {
                    let resting = rhrV[day] ?? restingBaseline
                    let load = StrainModel.load(heartRates: rates, restingHR: resting, maxHR: maxHR)
                    assign(metrics, \.strain, StrainModel.strain(fromLoad: load))
                    let bands = StrainModel.intensityMinutes(heartRates: rates, restingHR: resting, maxHR: maxHR)
                    assign(metrics, \.lightMinutes, bands.light)
                    assign(metrics, \.moderateMinutes, bands.moderate)
                    assign(metrics, \.vigorousMinutes, bands.vigorous)
                } else {
                    assign(metrics, \.strain, nil)
                    assign(metrics, \.lightMinutes, nil)
                    assign(metrics, \.moderateMinutes, nil)
                    assign(metrics, \.vigorousMinutes, nil)
                }
            }
            assign(metrics, \.heartRateRecovery, hrRecoveryV[day])
            assign(metrics, \.exerciseMinutes, exerciseV[day])
            assign(metrics, \.walkingSpeed, walkSpeedV[day])
            assign(metrics, \.walkingStepLength, stepLengthV[day])
            assign(metrics, \.walkingAsymmetry, asymmetryV[day].map { $0 * 100 })
            assign(metrics, \.walkingDoubleSupport, doubleSupportV[day].map { $0 * 100 })
            assign(metrics, \.walkingSteadiness, steadinessV[day].map { $0 * 100 })
            assign(metrics, \.proteinGrams, proteinV[day])
            assign(metrics, \.carbsGrams, carbsV[day])
            assign(metrics, \.fatGrams, fatV[day])
            assign(metrics, \.fiberGrams, fiberV[day])
            assign(metrics, \.sugarGrams, sugarV[day])
            assign(metrics, \.waterMl, waterV[day])
            assign(metrics, \.caffeineMg, caffeineV[day])
            assign(metrics, \.lateCaffeineMg, lateCaffeineByDay[day])
            assign(metrics, \.napHours, sleepV[day].map { $0.napHours > 0 ? $0.napHours : nil } ?? nil)
            if let night = sleepV[day], night.asleepHours > 0 {
                assign(metrics, \.sleepDurationHours, night.totalInBedHours)
                assign(metrics, \.sleepAsleepHours, night.asleepHours)
                assign(metrics, \.sleepDeepHours, night.deepHours)
                assign(metrics, \.sleepREMHours, night.remHours)
                assign(metrics, \.sleepAwakeHours, night.awakeHours)
                assign(metrics, \.sleepStart, night.sleepStart)
                assign(metrics, \.sleepEnd, night.sleepEnd)
                assign(metrics, \.sleepLatencyMinutes, night.latencyMinutes)
                assign(metrics, \.sleepWakeAfterOnsetHours, night.awakeAfterOnsetHours)
            }
            if let w = workoutsByDay[day] {
                assign(metrics, \.hadWorkout, true)
                assign(metrics, \.workoutIsResistance, w.strengthMinutes > 0)
                assign(metrics, \.workoutCount, w.count)
                assign(metrics, \.workoutMinutes, w.totalMinutes)
                assign(metrics, \.workoutEnergyKcal, w.energyKcal)
                assign(metrics, \.workoutAvgHeartRate, w.averageHeartRate)
                assign(metrics, \.strengthMinutes, w.strengthMinutes)
                assign(metrics, \.cardioMinutes, w.cardioMinutes)
                assign(metrics, \.primaryWorkoutName, w.primaryName)
                assign(metrics, \.trainingLoad, w.trimp)
            } else {
                assign(metrics, \.hadWorkout, false)
                assign(metrics, \.workoutIsResistance, false)
                assign(metrics, \.workoutCount, 0)
                assign(metrics, \.workoutMinutes, nil)
                assign(metrics, \.workoutEnergyKcal, nil)
                assign(metrics, \.workoutAvgHeartRate, nil)
                assign(metrics, \.strengthMinutes, nil)
                assign(metrics, \.cardioMinutes, nil)
                assign(metrics, \.primaryWorkoutName, nil)
                // Rest days are genuine zero-load days, not missing data —
                // ACWR depends on that distinction.
                assign(metrics, \.trainingLoad, 0)
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        try context.save()

        // Relearn the personal sleep baseline from the full history.
        let everyDay = (try? context.fetch(FetchDescriptor<DailyMetrics>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let tags = (try? context.fetch(FetchDescriptor<DayTag>())) ?? []
        SleepNeedModel.learnBaseline(from: everyDay, excluded: DayTagStore.excludedDates(tags))

        // Latest weight, for workout calorie estimates.
        if let latest = bodyMassV.sorted(by: { $0.key < $1.key }).last?.value {
            UserDefaults.standard.set(latest, forKey: "workout.lastBodyMass")
        }
    }

    // MARK: - Workouts

    struct WorkoutDay {
        var count = 0
        var totalMinutes: Double = 0
        var energyKcal: Double?
        var averageHeartRate: Double?
        var strengthMinutes: Double = 0
        var cardioMinutes: Double = 0
        /// Name of the longest session that day — what to show as the headline.
        var primaryName: String?
        var longestDuration: Double = 0
        var trimp: Double = 0
    }

    /// Banister TRIMP for one session.
    /// `duration × ΔHR × multiplier × e^(exponent × ΔHR)`,
    /// with ΔHR = (HR_exercise − HR_rest) / (HR_max − HR_rest).
    private func trimp(minutes: Double, averageHR: Double, restingHR: Double,
                       maxHR: Double, coefficients: HealthKitManager.TrimpCoefficients) -> Double {
        guard maxHR > restingHR, minutes > 0 else { return 0 }
        let ratio = min(max((averageHR - restingHR) / (maxHR - restingHR), 0), 1)
        return minutes * ratio * coefficients.multiplier * exp(coefficients.exponent * ratio)
    }

    private func summarizeWorkouts(
        _ workouts: [HKWorkout],
        calendar: Calendar,
        restingByDay: [Date: Double],
        restingFallback: Double,
        maxHeartRate: Double,
        coefficients: HealthKitManager.TrimpCoefficients
    ) async throws -> [Date: WorkoutDay] {
        var byDay: [Date: WorkoutDay] = [:]
        // Heart-rate averages are weighted by session length so a long easy
        // session doesn't get outvoted by a short hard one.
        var hrWeighted: [Date: (sum: Double, weight: Double)] = [:]

        for workout in workouts {
            let day = calendar.startOfDay(for: workout.endDate)
            let minutes = workout.duration / 60
            let isResistance = HealthKitManager.resistanceWorkoutTypes.contains(workout.workoutActivityType)

            var entry = byDay[day] ?? WorkoutDay()
            entry.count += 1
            entry.totalMinutes += minutes
            if isResistance {
                entry.strengthMinutes += minutes
            } else {
                entry.cardioMinutes += minutes
            }
            if let energy = HealthKitManager.energyBurned(for: workout) {
                entry.energyKcal = (entry.energyKcal ?? 0) + energy
            }
            if minutes > entry.longestDuration {
                entry.longestDuration = minutes
                entry.primaryName = HealthKitManager.displayName(for: workout.workoutActivityType)
            }
            byDay[day] = entry

            let measuredHR = try? await health.averageHeartRate(during: workout)
            if let hr = measuredHR, hr > 0, minutes > 0 {
                let existing = hrWeighted[day] ?? (sum: 0, weight: 0)
                hrWeighted[day] = (sum: existing.sum + hr * minutes, weight: existing.weight + minutes)
            }

            // Lifting apps often log sessions without a heart-rate stream, so
            // fall back to a nominal intensity rather than dropping the session
            // from training load entirely (which would distort ACWR).
            let restingHR = restingByDay[day] ?? restingFallback
            let effectiveHR: Double = {
                if let hr = measuredHR, hr > 0 { return hr }
                let assumedRatio = isResistance ? 0.55 : 0.70
                return restingHR + assumedRatio * (maxHeartRate - restingHR)
            }()

            byDay[day]?.trimp += trimp(minutes: minutes, averageHR: effectiveHR, restingHR: restingHR,
                                       maxHR: maxHeartRate, coefficients: coefficients)
        }

        for (day, hr) in hrWeighted where hr.weight > 0 {
            byDay[day]?.averageHeartRate = hr.sum / hr.weight
        }

        return byDay
    }

    /// Writes a value only when it changed. SwiftData marks an object dirty on
    /// every assignment, even to an equal value, and every observing screen
    /// re-renders — so the minute-by-minute refresh used to redraw the whole
    /// app even when nothing in Health had moved.
    private func assign<T: Equatable>(_ metrics: DailyMetrics, _ keyPath: ReferenceWritableKeyPath<DailyMetrics, T>, _ value: T) {
        if metrics[keyPath: keyPath] != value { metrics[keyPath: keyPath] = value }
    }

    private func fetchOrCreate(for day: Date) -> DailyMetrics {
        let descriptor = FetchDescriptor<DailyMetrics>(predicate: #Predicate { $0.date == day })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = DailyMetrics(date: day)
        context.insert(created)
        return created
    }
}
