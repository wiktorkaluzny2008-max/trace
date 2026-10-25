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
            .dietarySugar
        ]
    }

    var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for id in quantityTypes {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        types.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "RecoverySignal", code: 1,
                           userInfo: [NSLocalizedDescriptionKey: "Health data isn't available on this device."])
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
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
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    // MARK: - Daily quantity aggregation

    enum AggregationStyle {
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
    }

    /// Buckets sleep samples by the calendar day they *end* on (the morning you woke up),
    /// which matches how people mentally attribute a night's sleep.
    func sleepByNight(from startDate: Date, to endDate: Date) async throws -> [Date: SleepNight] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let calendar = Calendar.current

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var nights: [Date: SleepNight] = [:]
                for sample in (samples as? [HKCategorySample] ?? []) {
                    let day = calendar.startOfDay(for: sample.endDate)
                    let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
                    var night = nights[day] ?? SleepNight()

                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        night.totalInBedHours += hours
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                         HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        night.asleepHours += hours
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        night.asleepHours += hours
                        night.deepHours += hours
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        night.asleepHours += hours
                        night.remHours += hours
                    default:
                        break
                    }
                    nights[day] = night
                }
                continuation.resume(returning: nights)
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
}
