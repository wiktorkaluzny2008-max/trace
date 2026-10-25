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

    /// Refreshes the last `days` days (inclusive of today) of DailyMetrics.
    func refresh(days: Int = 30) async throws {
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
        async let dietaryEnergy = health.dailyValues(for: .dietaryEnergyConsumed, unit: .kilocalorie(), style: .sum, from: startDate, to: endDate)
        async let protein = health.dailyValues(for: .dietaryProtein, unit: .gram(), style: .sum, from: startDate, to: endDate)
        async let carbs = health.dailyValues(for: .dietaryCarbohydrates, unit: .gram(), style: .sum, from: startDate, to: endDate)
        async let fat = health.dailyValues(for: .dietaryFatTotal, unit: .gram(), style: .sum, from: startDate, to: endDate)
        async let fiber = health.dailyValues(for: .dietaryFiber, unit: .gram(), style: .sum, from: startDate, to: endDate)
        async let sugar = health.dailyValues(for: .dietarySugar, unit: .gram(), style: .sum, from: startDate, to: endDate)
        async let sleep = health.sleepByNight(from: startDate, to: endDate)
        async let workouts = health.workouts(from: startDate, to: endDate)

        let (hrvV, rhrV, vo2V, spo2V, stepsV, activeEnergyV, bodyMassV, dietaryEnergyV, proteinV, carbsV, fatV, fiberV, sugarV, sleepV, workoutsV) =
            try await (hrv, rhr, vo2, spo2, steps, activeEnergy, bodyMass, dietaryEnergy, protein, carbs, fat, fiber, sugar, sleep, workouts)

        var workoutsByDay: [Date: (any: Bool, resistance: Bool)] = [:]
        for workout in workoutsV {
            let day = calendar.startOfDay(for: workout.endDate)
            let isResistance = HealthKitManager.resistanceWorkoutTypes.contains(workout.workoutActivityType)
            let existing = workoutsByDay[day] ?? (any: false, resistance: false)
            workoutsByDay[day] = (any: true, resistance: existing.resistance || isResistance)
        }

        var day = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: endDate)
        while day <= today {
            let metrics = fetchOrCreate(for: day)
            metrics.hrvSDNN = hrvV[day]
            metrics.restingHeartRate = rhrV[day]
            metrics.vo2Max = vo2V[day]
            metrics.oxygenSaturation = spo2V[day]
            metrics.steps = stepsV[day]
            metrics.activeEnergyBurned = activeEnergyV[day]
            metrics.bodyMassKg = bodyMassV[day]
            metrics.dietaryEnergyKcal = dietaryEnergyV[day]
            metrics.proteinGrams = proteinV[day]
            metrics.carbsGrams = carbsV[day]
            metrics.fatGrams = fatV[day]
            metrics.fiberGrams = fiberV[day]
            metrics.sugarGrams = sugarV[day]
            if let night = sleepV[day] {
                metrics.sleepDurationHours = night.totalInBedHours
                metrics.sleepAsleepHours = night.asleepHours
                metrics.sleepDeepHours = night.deepHours
                metrics.sleepREMHours = night.remHours
            }
            if let w = workoutsByDay[day] {
                metrics.hadWorkout = w.any
                metrics.workoutIsResistance = w.resistance
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        try context.save()
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
