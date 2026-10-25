//
//  HealthKitManager.swift
//  RecoverySignal
//
//  Single point of contact with HealthKit. Read-only — this app never writes
//  anything back to Health. Nutrition data arrives here the same way Watch
//  data does, because Yazio writes it into HealthKit itself once its own
//  "Apple Health" sync is enabled.
//

import Foundation
import HealthKit

final class HealthKitManager {
    static let shared = HealthKitManager()
    let store = HKHealthStore()

    private init() {}

    // MARK: - Types we read

    private var quantityTypes: [HKQuantityTypeIdentifier] {
        [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .vo2Max,
            .oxygenSaturation,
            .stepCount,
            .activeEnergyBurned,
            .bodyMass,
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryFiber,
            .dietarySugar,
            .dietaryWater,
            .dietaryCaffeine,
            .bodyFatPercentage,
            .leanBodyMass
        ]
    }

    /// Read-only extras that we don't want background observers for.
    /// Heart rate and resting energy fire constantly, so they're queried on
    /// refresh rather than being allowed to wake the app all day. Height
    /// barely changes and only feeds the maintenance formula fallback.
    private var additionalReadTypes: [HKQuantityTypeIdentifier] {
        [.heartRate, .basalEnergyBurned, .height, .respiratoryRate,
         .heartRateRecoveryOneMinute, .appleExerciseTime,
         .walkingSpeed, .walkingStepLength, .walkingAsymmetryPercentage,
         .walkingDoubleSupportPercentage, .appleWalkingSteadiness,
         .appleSleepingWristTemperature]
    }

    var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for id in quantityTypes + additionalReadTypes {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        types.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        types.insert(HKObjectType.workoutType())
        // Needed to pick the right TRIMP coefficients and estimate HR max.
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { types.insert(sex) }
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(dob) }
        return types
    }

    // MARK: - Physiological constants

    /// Banister TRIMP uses sex-specific coefficients; defaults to the male
    /// pair when Health has no answer, which is documented in the UI.
    struct TrimpCoefficients {
        let multiplier: Double
        let exponent: Double

        static let male = TrimpCoefficients(multiplier: 0.64, exponent: 1.92)
        static let female = TrimpCoefficients(multiplier: 0.86, exponent: 1.67)
    }

    func trimpCoefficients() -> TrimpCoefficients {
        guard let sex = try? store.biologicalSex().biologicalSex else { return .male }
        return sex == .female ? .female : .male
    }

    /// Highest heart rate actually observed recently. Preferred over an
    /// age formula because it's measured rather than assumed.
    func observedMaxHeartRate(days: Int = 90) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteMax) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: stats?.maximumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Tanaka estimate (208 − 0.7 × age) from Health's date of birth.
    func ageBasedMaxHeartRate() -> Double? {
        guard let components = try? store.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: components) else { return nil }
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        guard years > 5, years < 120 else { return nil }
        return 208 - 0.7 * Double(years)
    }

    // MARK: - Body profile

    /// Height, age and sex for the maintenance-calorie formula fallback.
    /// Every field is optional: Health may simply not have it.
    func bodyProfile() async -> BodyProfile {
        var profile = BodyProfile()

        if let components = try? store.dateOfBirthComponents(),
           let birthDate = Calendar.current.date(from: components) {
            let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
            if years > 5, years < 120 { profile.ageYears = years }
        }

        switch (try? store.biologicalSex())?.biologicalSex {
        case .female: profile.isFemale = true
        case .male:   profile.isFemale = false
        default:      profile.isFemale = nil
        }

        profile.heightCm = try? await latestValue(for: .height, unit: .meterUnit(with: .centi))
        return profile
    }

    /// The most recent sample ever recorded for a type, however old.
    func latestValue(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let newestFirst = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: newestFirst) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "RecoverySignal", code: 1,
                           userInfo: [NSLocalizedDescriptionKey: "Health data isn't available on this device."])
        }
        // Reads and writes in one sheet, shown only when something is new.
        await HealthAccess.requestAllIfNeeded()
    }

    // MARK: - Background updates

    /// Registers an observer so we get woken up when new samples land, and asks
    /// iOS to keep delivering in the background. Call once at launch.
    func enableBackgroundDelivery(onUpdate: @escaping () -> Void) {
        for id in quantityTypes {
            guard let type = HKObjectType.quantityType(forIdentifier: id) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, _ in
                onUpdate()
                completionHandler()
            }
            store.execute(query)
            // Food logged anywhere should show up right away; the rest can wait.
            let nutrition = [HKQuantityTypeIdentifier.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal]
            store.enableBackgroundDelivery(for: type, frequency: nutrition.contains(id) ? .immediate : .hourly) { _, _ in }
        }
    }

    // MARK: - Daily quantity aggregation

    nonisolated enum AggregationStyle: Sendable {
        case sum
        case average
    }

    /// Returns one value per calendar day for the given identifier over the date range.
    func dailyValues(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        style: AggregationStyle,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }

        var interval = DateComponents()
        interval.day = 1
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: startDate)

        let options: HKStatisticsOptions = style == .sum ? .cumulativeSum : .discreteAverage
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: startDate, to: endDate) { stats, _ in
                    let day = calendar.startOfDay(for: stats.startDate)
                    let quantity = style == .sum ? stats.sumQuantity() : stats.averageQuantity()
                    if let quantity {
                        out[day] = quantity.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep

    struct SleepNight {
        var totalInBedHours: Double = 0
        var asleepHours: Double = 0
        var deepHours: Double = 0
        var remHours: Double = 0
        var awakeHours: Double = 0
        /// Daytime naps on this calendar day (not part of any night).
        var napHours: Double = 0
        /// When sleep actually started and ended (first/last asleep sample).
        var sleepStart: Date?
        var sleepEnd: Date?
        /// Minutes from getting into bed (or the Watch starting to track) to
        /// the first moment asleep. Nil when nothing marks the start.
        var latencyMinutes: Double?
        /// Time awake between falling asleep and the final wake-up.
        var awakeAfterOnsetHours: Double?
    }

    enum SleepStage: String, CaseIterable, Sendable {
        case awake, rem, core, deep
    }

    struct SleepSegment: Sendable {
        let start: Date
        let end: Date
        let stage: SleepStage
    }

    /// Which morning a sleep sample belongs to. Anything ending after 18:00
    /// counts toward the next morning, so a night that starts at 23:00 and ends
    /// at 07:30 is one night — not split at midnight.
    nonisolated static func sleepDay(for end: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: end.addingTimeInterval(6 * 3600))
    }

    /// Nights keyed by the morning you woke up. Overlapping samples (e.g. from
    /// both Watch and iPhone, or several sleep apps) are merged, not added twice.
    func sleepByNight(from startDate: Date, to endDate: Date) async throws -> [Date: SleepNight] {
        let calendar = Calendar.current
        // Reach back to the evening before the first day so its night is complete.
        let queryStart = calendar.date(byAdding: .hour, value: -12, to: startDate) ?? startDate
        let samples = try await sleepSamples(from: queryStart, to: endDate)

        let asleepValues = [HKCategoryValueSleepAnalysis.asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified].map(\.rawValue)

        var intervals: [Date: [Int: [(Date, Date)]]] = [:]
        var naps: [Date: [(Date, Date)]] = [:]
        for sample in samples {
            if Self.isNap(start: sample.startDate, end: sample.endDate, calendar: calendar) {
                if asleepValues.contains(sample.value) {
                    naps[calendar.startOfDay(for: sample.startDate), default: []].append((sample.startDate, sample.endDate))
                }
                continue
            }
            let day = Self.sleepDay(for: sample.endDate, calendar: calendar)
            intervals[day, default: [:]][sample.value, default: []].append((sample.startDate, sample.endDate))
        }

        var nights: [Date: SleepNight] = [:]
        for (day, byValue) in intervals {
            let asleep = asleepValues.flatMap { byValue[$0] ?? [] }
            var night = SleepNight()
            night.asleepHours = Self.unionHours(asleep)
            night.deepHours = Self.unionHours(byValue[HKCategoryValueSleepAnalysis.asleepDeep.rawValue] ?? [])
            night.remHours = Self.unionHours(byValue[HKCategoryValueSleepAnalysis.asleepREM.rawValue] ?? [])
            night.awakeHours = Self.unionHours(byValue[HKCategoryValueSleepAnalysis.awake.rawValue] ?? [])
            let inBed = byValue[HKCategoryValueSleepAnalysis.inBed.rawValue] ?? []
            // Watches don't always write an "in bed" sample; fall back to the whole sleep span.
            night.totalInBedHours = inBed.isEmpty
                ? Self.unionHours(asleep + (byValue[HKCategoryValueSleepAnalysis.awake.rawValue] ?? []))
                : Self.unionHours(inBed)
            night.sleepStart = asleep.map(\.0).min()
            night.sleepEnd = asleep.map(\.1).max()
            if let onset = night.sleepStart, let end = night.sleepEnd {
                let awake = byValue[HKCategoryValueSleepAnalysis.awake.rawValue] ?? []
                // Whatever began before sleep did — an "in bed" sample or the
                // Watch's awake stretch at the start of tracking.
                let starts = (inBed + awake).map(\.0).filter { $0 < onset && onset.timeIntervalSince($0) <= 2 * 3600 }
                if let first = starts.min() {
                    night.latencyMinutes = onset.timeIntervalSince(first) / 60
                }
                let midNight = awake.compactMap { s, e -> (Date, Date)? in
                    let a = max(s, onset), b = min(e, end)
                    return a < b ? (a, b) : nil
                }
                night.awakeAfterOnsetHours = Self.unionHours(midNight)
            }
            nights[day] = night
        }
        for (day, spans) in naps {
            nights[day, default: SleepNight()].napHours = Self.unionHours(spans)
        }
        return nights
    }

    /// Sleep that starts after 11:00 and ends by 19:00 on the same day is a
    /// nap, not part of a night.
    nonisolated static func isNap(start: Date, end: Date, calendar: Calendar) -> Bool {
        guard calendar.isDate(start, inSameDayAs: end) else { return false }
        let startHour = calendar.component(.hour, from: start)
        let endMinutes = calendar.component(.hour, from: end) * 60 + calendar.component(.minute, from: end)
        return startHour >= 11 && endMinutes <= 19 * 60 && end.timeIntervalSince(start) <= 3 * 3600
    }

    /// Stage-by-stage timeline for the night ending on `day`, for the hypnogram.
    /// Uses the single source that recorded the most staged sleep, so two
    /// devices' overlapping stages don't draw on top of each other.
    func sleepSegments(forNightEnding day: Date) async throws -> [SleepSegment] {
        let calendar = Calendar.current
        guard let from = calendar.date(byAdding: .hour, value: -18, to: day),
              let to = calendar.date(byAdding: .hour, value: 18, to: day) else { return [] }
        let samples = try await sleepSamples(from: from, to: to)
            .filter { Self.sleepDay(for: $0.endDate, calendar: calendar) == calendar.startOfDay(for: day) }

        func stage(_ value: Int) -> SleepStage? {
            switch value {
            case HKCategoryValueSleepAnalysis.awake.rawValue:      .awake
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:  .rem
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: .deep
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: .core
            default: nil
            }
        }

        let staged = samples.filter { stage($0.value) != nil }
        let bySource = Dictionary(grouping: staged) { $0.sourceRevision.source.bundleIdentifier }
        let best = bySource.max { a, b in
            a.value.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                < b.value.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        }?.value ?? []

        return best
            .compactMap { sample in stage(sample.value).map { SleepSegment(start: sample.startDate, end: sample.endDate, stage: $0) } }
            .sorted { $0.start < $1.start }
    }

    private func sleepSamples(from start: Date, to end: Date) async throws -> [HKCategorySample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }
    }

    /// Total hours covered by a set of possibly overlapping intervals.
    nonisolated static func unionHours(_ intervals: [(Date, Date)]) -> Double {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for interval in sorted {
            if let c = current, interval.0 <= c.1 {
                current = (c.0, max(c.1, interval.1))
            } else {
                if let c = current { total += c.1.timeIntervalSince(c.0) }
                current = interval
            }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return total / 3600
    }

    // MARK: - Heart rate streams

    /// Heart rate averaged into fixed buckets (default 2 min), keyed by bucket
    /// start. Smooths the Watch's irregular sampling into an even timeline the
    /// strain calculation can integrate over.
    func heartRateBuckets(from start: Date, to end: Date, minutes: Int = 2) async throws -> [(date: Date, bpm: Double)] {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        var interval = DateComponents()
        interval.minute = minutes
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let unit = HKUnit.count().unitDivided(by: .minute())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: .discreteAverage,
                                                    anchorDate: Calendar.current.startOfDay(for: start),
                                                    intervalComponents: interval)
            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var out: [(Date, Double)] = []
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let avg = stats.averageQuantity() {
                        out.append((stats.startDate, avg.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Raw caffeine samples in a window, oldest first — so the sleep plan can
    /// tell *when* caffeine was taken, not just how much.
    func caffeineSamples(from start: Date, to end: Date) async throws -> [(date: Date, mg: Double)] {
        guard let type = HKObjectType.quantityType(forIdentifier: .dietaryCaffeine) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let unit = HKUnit.gramUnit(with: .milli)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let values = (samples as? [HKQuantitySample] ?? []).map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

        /// Raw heart-rate samples in a window, oldest first — for the overnight chart.
    func heartRateSamples(from start: Date, to end: Date) async throws -> [(date: Date, bpm: Double)] {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let unit = HKUnit.count().unitDivided(by: .minute())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let values = (samples as? [HKQuantitySample] ?? []).map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    // MARK: - Workouts

    func workouts(from startDate: Date, to endDate: Date) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
    }

    static let resistanceWorkoutTypes: Set<HKWorkoutActivityType> = [
        .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining, .coreTraining
    ]

    /// Energy burned during a workout. Prefers the modern per-workout
    /// statistics; falls back to nil rather than the deprecated total.
    nonisolated static func energyBurned(for workout: HKWorkout) -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let sum = workout.statistics(for: type)?.sumQuantity() else { return nil }
        return sum.doubleValue(for: .kilocalorie())
    }

    /// Average heart rate across a workout's window, queried separately since
    /// HR samples aren't necessarily attached to the workout object itself.
    func averageHeartRate(during workout: HKWorkout) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Human-readable name for the activity types most likely to show up here.
    nonisolated static func displayName(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: "Strength training"
        case .functionalStrengthTraining:  "Functional strength"
        case .coreTraining:                "Core training"
        case .crossTraining:               "Cross training"
        case .highIntensityIntervalTraining: "HIIT"
        case .running:                     "Running"
        case .walking:                     "Walking"
        case .cycling:                     "Cycling"
        case .swimming:                    "Swimming"
        case .rowing:                      "Rowing"
        case .elliptical:                  "Elliptical"
        case .yoga:                        "Yoga"
        case .pilates:                     "Pilates"
        case .hiking:                      "Hiking"
        case .dance:                       "Dance"
        case .boxing:                      "Boxing"
        case .climbing:                    "Climbing"
        case .stairClimbing:               "Stair climbing"
        default:                           "Workout"
        }
    }
}
