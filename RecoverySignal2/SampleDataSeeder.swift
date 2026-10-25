//
//  SampleDataSeeder.swift
//  RecoverySignal2
//
//  Simulator-only helper that fills the app with four months of believable
//  data, so every screen has something real to show: Watch readings in Apple
//  Health (sleep in proper cycles, dense heart rate, HRV, steps, workouts with
//  heart rate attached, weight, nutrition by meal), plus the app's own records
//  (a food log, routines, logged strength sessions with sets, day tags).
//
//  The months tell a story the analysis can find: a cut then a lean gain,
//  steady strength progress, a hard block that tips into overreaching, a
//  deload, a few sick days, a trip, and drinks on some weekends that show up
//  in the next night's HRV. The last week is a good one.
//
//  Hard-gated to the Simulator, so it can never write fake data into someone's
//  real Health app. Running it again replaces the previous sample data.
//

import Foundation
import HealthKit
import SwiftData

#if targetEnvironment(simulator)
enum SampleDataSeeder {

    static let dayCount = 120

    private static var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        let quantityIds: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN, .restingHeartRate, .heartRate, .respiratoryRate, .oxygenSaturation, .vo2Max,
            .stepCount, .activeEnergyBurned, .basalEnergyBurned, .height, .bodyMass, .bodyFatPercentage,
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFiber,
            .dietarySugar, .dietaryWater, .dietaryCaffeine
        ]
        for id in quantityIds {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        types.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        types.insert(HKObjectType.workoutType())
        return types
    }

    // MARK: - The story

    /// What kind of day `offset` days ago was.
    private struct DayPlan {
        var offset: Int
        var sick = false
        var travel = false
        var alcohol = false
        var lateMeal = false
        /// 0 normal … 1 badly overreached.
        var fatigue = 0.0
        var deload = false
        var session: Session?
        var run = false
    }

    private enum Session: String, CaseIterable {
        case push = "Push", pull = "Pull", legs = "Legs", upper = "Upper"
    }

    private static func plans(calendar: Calendar, today: Date) -> [DayPlan] {
        (0..<dayCount).reversed().map { offset in
            var plan = DayPlan(offset: offset)
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let weekday = calendar.component(.weekday, from: date) // 1 = Sunday

            plan.sick = (60...62).contains(offset)
            plan.travel = (19...21).contains(offset)
            // A hard block that builds fatigue, then a deload week.
            if (35...45).contains(offset) { plan.fatigue = Double(46 - offset) / 11 }
            plan.deload = (28...34).contains(offset)
            // Drinks on some Friday and Saturday nights; late dinners now and then.
            plan.alcohol = (weekday == 6 || weekday == 7) && offset % 3 != 0 && !plan.sick && offset > 6
            plan.lateMeal = offset % 6 == 2 && !plan.sick

            if !plan.sick && !plan.travel {
                switch weekday {
                case 2: plan.session = .push
                case 3: plan.session = .pull
                case 5: plan.session = .legs
                case 7: plan.session = .upper
                case 4, 1: plan.run = true
                default: break
                }
            }
            return plan
        }
    }

    // MARK: - Seed

    /// Writes the sample Health data and, when a context is given, the app's own
    /// records. Call `MetricsAggregator.refresh(days:)` afterwards, then
    /// `attachReadiness(context:)`.
    static func seed(context: ModelContext? = nil) async throws {
        let store = HealthKitManager.shared.store
        try await store.requestAuthorization(toShare: writeTypes, read: HealthKitManager.shared.readTypes)

        // Replace whatever an earlier run wrote.
        for type in writeTypes {
            _ = try? await deleteOwnSamples(of: type, in: store)
        }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let days = plans(calendar: calendar, today: today)
        var samples: [HKObject] = []
        var workouts: [WorkoutPlan] = []
        var foodDays: [(date: Date, meals: [(MealSlot, Date, [(FoodItem, Double)])])] = []

        let bpm = HKUnit.count().unitDivided(by: .minute())

        samples.append(quantitySample(.height, unit: .meterUnit(with: .centi), value: 181,
                                      at: calendar.date(byAdding: .day, value: -dayCount, to: today)!))

        for (index, plan) in days.enumerated() {
            let offset = plan.offset
            let dayStart = calendar.date(byAdding: .day, value: -offset, to: today)!
            let progress = Double(dayCount - 1 - offset) / Double(dayCount - 1) // 0 oldest … 1 today
            let yesterday = index > 0 ? days[index - 1] : nil
            func at(_ hour: Double) -> Date { dayStart.addingTimeInterval(hour * 3600) }
            func clamp(_ date: Date) -> Date { min(date, now) }

            // How rough last night was: drinks, a late meal, illness, travel or fatigue.
            var strain = plan.fatigue * 0.8
            if yesterday?.alcohol == true { strain += 0.9 }
            if yesterday?.lateMeal == true { strain += 0.35 }
            if plan.sick { strain += 1.4 }
            if plan.travel { strain += 0.7 }
            if plan.deload { strain -= 0.2 }
            if offset < 6 { strain -= 0.35 } // a good last week
            let noise = Double.random(in: -0.35...0.35)

            // --- Sleep: the night that ended this morning.
            var bedtime = 23.1 + Double.random(in: -0.5...0.6)
            let weekday = calendar.component(.weekday, from: dayStart)
            if weekday == 1 || weekday == 7 { bedtime += 0.6 }          // later at weekends
            if yesterday?.alcohol == true { bedtime += 0.8 }
            if plan.travel { bedtime += 1.2 }
            var asleepHours = 7.35 + Double.random(in: -0.5...0.5) - max(strain, 0) * 0.45
            if plan.sick { asleepHours += 1.1 }
            if offset < 6 { asleepHours += 0.25 }
            let sleepStart = dayStart.addingTimeInterval((bedtime - 24) * 3600)
            let deepScale = yesterday?.lateMeal == true || yesterday?.alcohol == true ? 0.6 : 1.0
            let sleep = sleepSegments(start: sleepStart, asleepHours: asleepHours, deepScale: deepScale, now: now)
            samples.append(contentsOf: sleep.samples)
            let wake = sleep.end

            // --- Overnight vitals.
            let restingHR = 53 - progress * 2.5 + max(strain, 0) * 4.2 + noise * 2
            let hrv = max(22, 50 + progress * 7 - max(strain, 0) * 10.5 + noise * 8)
            if wake <= now {
                samples.append(quantitySample(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), value: hrv,
                                              at: wake.addingTimeInterval(-3600)))
                samples.append(quantitySample(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli),
                                              value: hrv * Double.random(in: 0.85...1.15), at: sleepStart.addingTimeInterval(2 * 3600)))
                samples.append(quantitySample(.restingHeartRate, unit: bpm, value: restingHR, at: wake.addingTimeInterval(1800)))
                samples.append(quantitySample(.oxygenSaturation, unit: .percent(),
                                              value: min(0.99, 0.975 - max(strain, 0) * 0.008 + Double.random(in: -0.01...0.01)),
                                              at: sleepStart.addingTimeInterval(3 * 3600)))
                samples.append(quantitySample(.respiratoryRate, unit: bpm,
                                              value: 14.4 + max(strain, 0) * 1.1 + Double.random(in: -0.3...0.3),
                                              at: sleepStart.addingTimeInterval(3.5 * 3600)))
            }
            var t = sleepStart
            while t < min(wake, now) {
                let f = t.timeIntervalSince(sleepStart) / max(wake.timeIntervalSince(sleepStart), 1)
                let value = restingHR + 5 - 7 * sin(f * .pi) + Double.random(in: -1.5...2.5)
                samples.append(quantitySample(.heartRate, unit: bpm, value: value, at: t))
                t = t.addingTimeInterval(300)
            }
            if offset % 6 == 0 && !plan.sick {
                samples.append(quantitySample(.vo2Max, unit: HKUnit(from: "ml/kg*min"),
                                              value: 44.2 + progress * 3.1 + Double.random(in: -0.4...0.4), at: clamp(at(18.5))))
            }

            // --- Training.
            var sessionWindow: ClosedRange<Date>?
            if let session = plan.session {
                let start = at(17.8 + Double.random(in: -0.3...0.4))
                let minutes = (plan.deload ? 48 : 64) + Double.random(in: -6...8)
                let end = start.addingTimeInterval(minutes * 60)
                if end <= now {
                    workouts.append(WorkoutPlan(activity: .traditionalStrengthTraining, start: start, end: end,
                                                kcal: minutes * (plan.deload ? 5.0 : 6.2), bpmRange: 98...148, session: session,
                                                readiness: -strain))
                    sessionWindow = start...end
                }
            } else if plan.run {
                let start = at(7.3 + Double.random(in: -0.2...0.3))
                let minutes = 32 + Double.random(in: -4...10)
                let end = start.addingTimeInterval(minutes * 60)
                if end <= now {
                    workouts.append(WorkoutPlan(activity: .running, start: start, end: end,
                                                kcal: minutes * 11, bpmRange: 138...171, session: nil, readiness: -strain))
                    sessionWindow = start...end
                }
            }

            // --- Daytime heart rate every 10 minutes, outside workouts.
            var d = wake.addingTimeInterval(600)
            let dayEnd = at(22.4)
            while d < min(dayEnd, now) {
                if sessionWindow?.contains(d) != true {
                    let hour = d.timeIntervalSince(dayStart) / 3600
                    let active = (hour > 8 && hour < 9) || (hour > 12.5 && hour < 13.2) || (hour > 17 && hour < 17.5)
                    samples.append(quantitySample(.heartRate, unit: bpm,
                                                  value: restingHR + (active ? Double.random(in: 30...48) : Double.random(in: 12...26)), at: d))
                }
                d = d.addingTimeInterval(600)
            }

            // --- Steps and energy, spread through the day.
            let stepTotal = (plan.sick ? 2600 : (plan.run ? 12500 : 8600)) + Double.random(in: -1500...1800)
            let activeTotal = (plan.sick ? 180 : 470) + Double.random(in: -60...90)
            for hour in 8...21 {
                let start = at(Double(hour))
                guard start < now else { break }
                let share = [9, 13, 18].contains(hour) ? 1.5 : 0.9
                samples.append(quantitySample(.stepCount, unit: .count(), value: stepTotal / 14 * share * Double.random(in: 0.7...1.3),
                                              start: start, end: min(start.addingTimeInterval(3600), now)))
                samples.append(quantitySample(.activeEnergyBurned, unit: .kilocalorie(), value: activeTotal / 14 * share,
                                              start: start, end: min(start.addingTimeInterval(3600), now)))
            }
            // Resting energy, with one part-wear day a week (Watch left on the charger).
            let resting = offset % 7 == 4 ? Double.random(in: 700...950) : 1790 + Double.random(in: -25...25)
            samples.append(quantitySample(.basalEnergyBurned, unit: .kilocalorie(), value: resting, at: clamp(at(12))))

            // --- Body: a cut for the first half, then a slow lean gain.
            let weight = progress < 0.5 ? 81.2 - progress * 3.8 : 79.3 + (progress - 0.5) * 1.6
            if offset % 5 != 3, at(7.1) <= now {
                samples.append(quantitySample(.bodyMass, unit: .gramUnit(with: .kilo),
                                              value: weight + Double.random(in: -0.25...0.25) + (plan.travel ? 0.5 : 0), at: at(7.1)))
            }
            if offset % 3 == 0, at(7.1) <= now {
                samples.append(quantitySample(.bodyFatPercentage, unit: .percent(),
                                              value: 0.176 - progress * 0.021 + Double.random(in: -0.002...0.002), at: at(7.12)))
            }

            // --- Food, meal by meal.
            let cutting = progress < 0.5
            let scale = (cutting ? 0.86 : 1.02) * (plan.sick ? 0.75 : 1) * Double.random(in: 0.93...1.07)
            var meals: [(MealSlot, Date, [(FoodItem, Double)])] = []
            let breakfast = offset % 2 == 0 ? Meals.breakfastA : Meals.breakfastB
            let lunch = offset % 3 == 0 ? Meals.lunchB : Meals.lunchA
            let dinner = offset % 2 == 0 ? Meals.dinnerA : Meals.dinnerB
            let snack = offset % 2 == 0 ? Meals.snackA : Meals.snackB
            meals.append((.breakfast, at(7.6), breakfast))
            meals.append((.lunch, at(12.8), lunch))
            if !plan.sick { meals.append((.snack, at(16.2), snack)) }
            meals.append((.dinner, at(plan.lateMeal ? 22.1 : 19.4), dinner))
            meals = meals.filter { $0.1 <= now }.map { meal in (meal.0, meal.1, meal.2.map { ($0.0, $0.1 * scale) }) }
            var fiber = 0.0
            for (_, time, items) in meals {
                var k = 0.0, p = 0.0, c = 0.0, f = 0.0
                for line in items {
                    let a = line.0.amount(line.1)
                    k += a.kcal; p += a.protein; c += a.carbs; f += a.fat
                }
                samples.append(quantitySample(.dietaryEnergyConsumed, unit: .kilocalorie(), value: k, at: time))
                samples.append(quantitySample(.dietaryProtein, unit: .gram(), value: p, at: time))
                samples.append(quantitySample(.dietaryCarbohydrates, unit: .gram(), value: c, at: time))
                samples.append(quantitySample(.dietaryFatTotal, unit: .gram(), value: f, at: time))
                fiber += c * 0.11
            }
            if let last = meals.last {
                samples.append(quantitySample(.dietaryFiber, unit: .gram(), value: fiber, at: last.1))
                samples.append(quantitySample(.dietarySugar, unit: .gram(), value: fiber * 1.9, at: last.1))
            }
            if offset < 21 { foodDays.append((dayStart, meals)) }

            // Water through the day; coffee in the morning, sometimes a late one.
            for hour in [8.0, 11.5, 14.5, 18.0, 20.5] where at(hour) <= now {
                samples.append(quantitySample(.dietaryWater, unit: .literUnit(with: .milli), value: Double.random(in: 350...550), at: at(hour)))
            }
            for hour in [7.8, offset % 4 == 1 ? 16.4 : 13.6] where at(hour) <= now {
                samples.append(quantitySample(.dietaryCaffeine, unit: .gramUnit(with: .milli), value: 95, at: at(hour)))
            }
        }

        for chunk in stride(from: 0, to: samples.count, by: 2000) {
            try await store.save(Array(samples[chunk..<min(chunk + 2000, samples.count)]))
        }
        // Workouts go through a builder so energy and heart rate are attached to
        // them, the same shape the app reads back from a real Watch workout.
        for plan in workouts {
            try await build(plan, in: store)
        }

        if let context {
            try seedAppRecords(days: days, workouts: workouts, foodDays: foodDays, today: today, calendar: calendar, context: context)
        }
    }

    /// Records how the body looked before each seeded session, as the recorder
    /// does for real ones, so the performance model has labels to learn from.
    /// Needs the daily metrics, so call it after the aggregator has refreshed.
    static func attachReadiness(context: ModelContext) {
        let days = (try? context.fetch(FetchDescriptor<DailyMetrics>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let tags = (try? context.fetch(FetchDescriptor<DayTag>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        for log in logs where log.readinessPayload.isEmpty {
            log.readiness = ReadinessSnapshot.capture(at: log.start, days: days, tags: tags)
        }
        try? context.save()
    }

    // MARK: - Local-only seed (no Health)

    /// Fills the app's own store with the same four-month story — daily
    /// rollups, routines, logged sessions, the food log and day tags — without
    /// writing anything to Apple Health, so every screen can be checked in the
    /// Simulator without granting Health access. Launch argument: `-seedLocal`.
    /// The aggregator skips its Health refresh while that argument is present,
    /// so the rows written here aren't overwritten by an empty Health store.
    static func seedLocal(context: ModelContext) throws {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let days = plans(calendar: calendar, today: today)
        var workouts: [WorkoutPlan] = []
        var foodDays: [(date: Date, meals: [(MealSlot, Date, [(FoodItem, Double)])])] = []
        var rows: [DailyMetrics] = []

        for (index, plan) in days.enumerated() {
            let offset = plan.offset
            let dayStart = calendar.date(byAdding: .day, value: -offset, to: today)!
            let progress = Double(dayCount - 1 - offset) / Double(dayCount - 1)
            let yesterday = index > 0 ? days[index - 1] : nil
            func at(_ hour: Double) -> Date { dayStart.addingTimeInterval(hour * 3600) }

            var strain = plan.fatigue * 0.8
            if yesterday?.alcohol == true { strain += 0.9 }
            if yesterday?.lateMeal == true { strain += 0.35 }
            if plan.sick { strain += 1.4 }
            if plan.travel { strain += 0.7 }
            if plan.deload { strain -= 0.2 }
            if offset < 6 { strain -= 0.35 }
            let noise = Double.random(in: -0.35...0.35)

            let m = DailyMetrics(date: dayStart)

            // Sleep
            var bedtime = 23.1 + Double.random(in: -0.5...0.6)
            let weekday = calendar.component(.weekday, from: dayStart)
            if weekday == 1 || weekday == 7 { bedtime += 0.6 }
            if yesterday?.alcohol == true { bedtime += 0.8 }
            if plan.travel { bedtime += 1.2 }
            var asleepHours = 7.35 + Double.random(in: -0.5...0.5) - max(strain, 0) * 0.45
            if plan.sick { asleepHours += 1.1 }
            if offset < 6 { asleepHours += 0.25 }
            let deepScale = yesterday?.lateMeal == true || yesterday?.alcohol == true ? 0.6 : 1.0
            let sleepStart = dayStart.addingTimeInterval((bedtime - 24) * 3600)
            let awake = 0.25 + Double.random(in: 0...0.2)
            m.sleepStart = sleepStart
            m.sleepEnd = sleepStart.addingTimeInterval((asleepHours + awake + 0.2) * 3600)
            m.sleepAsleepHours = asleepHours
            m.sleepDurationHours = asleepHours + awake + 0.2
            m.sleepDeepHours = asleepHours * 0.17 * deepScale
            m.sleepREMHours = asleepHours * 0.23
            m.sleepAwakeHours = awake
            m.sleepLatencyMinutes = Double.random(in: 8...18)
            m.sleepWakeAfterOnsetHours = awake * 0.6

            // Overnight vitals
            let restingHR = 53 - progress * 2.5 + max(strain, 0) * 4.2 + noise * 2
            let hrv = max(22, 50 + progress * 7 - max(strain, 0) * 10.5 + noise * 8)
            m.hrvSDNN = hrv
            m.restingHeartRate = restingHR
            m.oxygenSaturation = min(0.99, 0.975 - max(strain, 0) * 0.008 + Double.random(in: -0.01...0.01))
            m.respiratoryRate = 14.4 + max(strain, 0) * 1.1 + Double.random(in: -0.3...0.3)
            if offset % 6 == 0 && !plan.sick { m.vo2Max = 44.2 + progress * 3.1 + Double.random(in: -0.4...0.4) }

            // Training
            if let session = plan.session {
                let start = at(17.8 + Double.random(in: -0.3...0.4))
                let minutes = (plan.deload ? 48 : 64) + Double.random(in: -6...8)
                let end = start.addingTimeInterval(minutes * 60)
                if end <= now {
                    workouts.append(WorkoutPlan(activity: .traditionalStrengthTraining, start: start, end: end,
                                                kcal: minutes * (plan.deload ? 5.0 : 6.2), bpmRange: 98...148, session: session,
                                                readiness: -strain))
                    m.hadWorkout = true
                    m.workoutIsResistance = true
                    m.workoutCount = 1
                    m.workoutMinutes = minutes
                    m.strengthMinutes = minutes
                    m.workoutEnergyKcal = minutes * (plan.deload ? 5.0 : 6.2)
                    m.workoutAvgHeartRate = 115 + Double.random(in: -5...5)
                    m.primaryWorkoutName = "Traditional Strength Training"
                    m.trainingLoad = minutes * (plan.deload ? 0.9 : 1.25)
                }
            } else if plan.run {
                let start = at(7.3 + Double.random(in: -0.2...0.3))
                let minutes = 32 + Double.random(in: -4...10)
                let end = start.addingTimeInterval(minutes * 60)
                if end <= now {
                    workouts.append(WorkoutPlan(activity: .running, start: start, end: end,
                                                kcal: minutes * 11, bpmRange: 138...171, session: nil, readiness: -strain))
                    m.hadWorkout = true
                    m.workoutCount = 1
                    m.workoutMinutes = minutes
                    m.cardioMinutes = minutes
                    m.workoutEnergyKcal = minutes * 11
                    m.workoutAvgHeartRate = 152 + Double.random(in: -5...5)
                    m.primaryWorkoutName = "Running"
                    m.trainingLoad = minutes * 2.1
                }
            }
            m.strain = min(21, max(2, (m.hadWorkout ? 11.5 : 5.5) + max(strain, 0) * 2 + Double.random(in: -1.5...1.5)))

            // Activity and energy
            let stepTotal = (plan.sick ? 2600 : (plan.run ? 12500 : 8600)) + Double.random(in: -1500...1800)
            let activeTotal = (plan.sick ? 180 : 470) + Double.random(in: -60...90)
            m.steps = stepTotal
            m.activeEnergyBurned = activeTotal
            m.exerciseMinutes = (m.workoutMinutes ?? 0) + Double.random(in: 10...25)
            m.basalEnergyKcal = offset % 7 == 4 ? Double.random(in: 700...950) : 1790 + Double.random(in: -25...25)
            m.lightMinutes = Double.random(in: 40...90)
            m.moderateMinutes = m.hadWorkout ? Double.random(in: 25...50) : Double.random(in: 5...15)
            m.vigorousMinutes = plan.run ? Double.random(in: 15...30) : (m.hadWorkout ? Double.random(in: 3...10) : 0)

            // Body
            let weight = progress < 0.5 ? 81.2 - progress * 3.8 : 79.3 + (progress - 0.5) * 1.6
            if offset % 5 != 3 {
                m.bodyMassKg = weight + Double.random(in: -0.25...0.25) + (plan.travel ? 0.5 : 0)
            }
            if offset % 3 == 0 {
                let fat = 0.176 - progress * 0.021 + Double.random(in: -0.002...0.002)
                m.bodyFatPercent = fat * 100
                m.leanBodyMassKg = (m.bodyMassKg ?? weight) * (1 - fat)
            }

            // Food
            let cutting = progress < 0.5
            let scale = (cutting ? 0.86 : 1.02) * (plan.sick ? 0.75 : 1) * Double.random(in: 0.93...1.07)
            var meals: [(MealSlot, Date, [(FoodItem, Double)])] = []
            let breakfast = offset % 2 == 0 ? Meals.breakfastA : Meals.breakfastB
            let lunch = offset % 3 == 0 ? Meals.lunchB : Meals.lunchA
            let dinner = offset % 2 == 0 ? Meals.dinnerA : Meals.dinnerB
            let snack = offset % 2 == 0 ? Meals.snackA : Meals.snackB
            meals.append((.breakfast, at(7.6), breakfast))
            meals.append((.lunch, at(12.8), lunch))
            if !plan.sick { meals.append((.snack, at(16.2), snack)) }
            meals.append((.dinner, at(plan.lateMeal ? 22.1 : 19.4), dinner))
            meals = meals.filter { $0.1 <= now }.map { meal in (meal.0, meal.1, meal.2.map { ($0.0, $0.1 * scale) }) }
            var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
            for (_, _, items) in meals {
                for line in items {
                    let a = line.0.amount(line.1)
                    kcal += a.kcal; protein += a.protein; carbs += a.carbs; fat += a.fat
                }
            }
            if !meals.isEmpty {
                m.dietaryEnergyKcal = kcal
                m.proteinGrams = protein
                m.carbsGrams = carbs
                m.fatGrams = fat
                m.fiberGrams = carbs * 0.11
                m.sugarGrams = carbs * 0.21
            }
            m.waterMl = Double(meals.count) * Double.random(in: 420...560)
            m.caffeineMg = offset % 4 == 1 ? 190 : 95
            m.lateCaffeineMg = offset % 4 == 1 ? 95 : 0
            if offset < 21 { foodDays.append((dayStart, meals)) }

            rows.append(m)
        }

        // seedAppRecords clears DailyMetrics first, so the rows go in afterwards.
        try seedAppRecords(days: days, workouts: workouts, foodDays: foodDays, today: today, calendar: calendar, context: context)
        for row in rows { context.insert(row) }
        try context.save()
        attachReadiness(context: context)
    }

    // MARK: - Sleep

    /// A night in ~90-minute cycles: deep sleep front-loaded, REM growing toward
    /// morning, and a few short wakings — how a Watch night actually looks.
    private static func sleepSegments(start: Date, asleepHours: Double, deepScale: Double,
                                      now: Date) -> (samples: [HKObject], end: Date) {
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        var samples: [HKObject] = []
        var cursor = start.addingTimeInterval(Double.random(in: 8...18) * 60) // falling asleep
        var asleep = 0.0
        let target = asleepHours * 3600
        let deepShares = [0.34, 0.24, 0.12, 0.05, 0.03, 0.02]
        let remShares = [0.09, 0.17, 0.24, 0.30, 0.34, 0.36]

        func add(_ value: HKCategoryValueSleepAnalysis, _ seconds: Double) {
            guard seconds > 30 else { return }
            let end = cursor.addingTimeInterval(seconds)
            if cursor < now {
                samples.append(HKCategorySample(type: type, value: value.rawValue, start: cursor, end: min(end, now)))
            }
            cursor = end
            if value != .awake { asleep += seconds }
        }

        var cycle = 0
        while asleep < target {
            let length = min((88 + Double.random(in: -12...14)) * 60, target - asleep)
            let i = min(cycle, deepShares.count - 1)
            let deep = length * deepShares[i] * deepScale
            let rem = length * remShares[i]
            let core = length - deep - rem
            add(.asleepCore, core * 0.55)
            add(.asleepDeep, deep)
            add(.asleepCore, core * 0.45)
            add(.asleepREM, rem)
            if length < 60 { break }
            if cycle > 0 && Double.random(in: 0...1) < 0.45 && asleep < target {
                add(.awake, Double.random(in: 2...7) * 60)
            }
            cycle += 1
        }
        let end = cursor
        if start < now {
            samples.insert(HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                                            start: start, end: min(end.addingTimeInterval(6 * 60), now)), at: 0)
        }
        return (samples, end)
    }

    // MARK: - Workouts in Health

    private struct WorkoutPlan {
        let activity: HKWorkoutActivityType
        let start: Date
        let end: Date
        let kcal: Double
        let bpmRange: ClosedRange<Double>
        let session: Session?
        /// Higher is fresher; shapes how the session goes.
        let readiness: Double
    }

    private static func build(_ plan: WorkoutPlan, in store: HKHealthStore) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = plan.activity
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        try await builder.beginCollection(at: plan.start)

        var attached: [HKSample] = []
        if let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            attached.append(HKQuantitySample(type: energyType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: plan.kcal),
                                             start: plan.start, end: plan.end))
        }
        // Heart rate every 20 seconds, as a Watch records during a workout:
        // a warm-up ramp, then sets and rests for lifting, a steady climb for a run.
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            let duration = plan.end.timeIntervalSince(plan.start)
            let low = plan.bpmRange.lowerBound, high = plan.bpmRange.upperBound
            var t = 0.0
            while t < duration {
                let f = t / duration
                let value: Double
                if plan.activity == .running {
                    value = low + (high - low) * min(1, f * 1.6) * 0.85 + Double.random(in: -3...3)
                } else {
                    let phase = t.truncatingRemainder(dividingBy: 180) / 180 // ~45 s set, then rest
                    let warm = min(1, f * 5)
                    value = low + (high - low) * warm * (phase < 0.25 ? 0.95 : 0.55 - phase * 0.3) + Double.random(in: -3...3)
                }
                let at = plan.start.addingTimeInterval(t)
                attached.append(HKQuantitySample(type: hrType, quantity: HKQuantity(unit: unit, doubleValue: value), start: at, end: at))
                t += 20
            }
        }
        try await builder.addSamples(attached)
        try await builder.endCollection(at: plan.end)
        _ = try await builder.finishWorkout()
    }

    private static func deleteOwnSamples(of type: HKSampleType, in store: HKHealthStore) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            store.deleteObjects(of: type, predicate: HKQuery.predicateForObjects(from: .default())) { _, count, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: count) }
            }
        }
    }

    private static func quantitySample(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, value: Double, at date: Date) -> HKQuantitySample {
        quantitySample(identifier, unit: unit, value: value, start: date, end: date)
    }

    private static func quantitySample(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, value: Double,
                                       start: Date, end: Date) -> HKQuantitySample {
        let type = HKObjectType.quantityType(forIdentifier: identifier)!
        return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: start, end: max(end, start))
    }

    // MARK: - The app's own records

    private static func seedAppRecords(days: [DayPlan], workouts: [WorkoutPlan],
                                       foodDays: [(date: Date, meals: [(MealSlot, Date, [(FoodItem, Double)])])],
                                       today: Date, calendar: Calendar, context: ModelContext) throws {
        // Start clean, so a second run doesn't double everything.
        try context.delete(model: FoodEntry.self)
        try context.delete(model: WorkoutLog.self)
        try context.delete(model: WorkoutRoutine.self)
        try context.delete(model: DayTag.self)
        try context.delete(model: DailyMetrics.self)

        // Tags for the notable days.
        for plan in days {
            let date = calendar.date(byAdding: .day, value: -plan.offset, to: today)!
            if plan.sick { context.insert(DayTag(date: date, kind: .sick)) }
            if plan.travel { context.insert(DayTag(date: date, kind: .travel)) }
            if plan.alcohol { context.insert(DayTag(date: date, kind: .alcohol)) }
            if plan.lateMeal { context.insert(DayTag(date: date, kind: .lateMeal)) }
        }

        // The food log for the last three weeks, matching what went to Health.
        for day in foodDays {
            for (slot, time, items) in day.meals {
                for (index, line) in items.enumerated() {
                    context.insert(FoodEntry(item: line.0, grams: line.1.rounded(), slot: slot,
                                             date: time.addingTimeInterval(Double(index) * 20), healthID: nil))
                }
            }
        }

        // Routines, then every strength session logged set by set.
        var routines: [Session: WorkoutRoutine] = [:]
        for session in Session.allCases {
            let planned = Lifts.program[session]!.map {
                PlannedExercise(exerciseID: $0.id, name: $0.name, sets: $0.sets, reps: $0.reps.upperBound, restSeconds: $0.rest,
                                repLow: $0.reps.lowerBound, repHigh: $0.reps.upperBound)
            }
            let routine = WorkoutRoutine(name: session.rawValue, exercises: planned)
            routine.createdAt = calendar.date(byAdding: .day, value: -dayCount - 2, to: today)!
            context.insert(routine)
            routines[session] = routine
        }

        let deloadDays = Set(days.filter(\.deload).map { calendar.date(byAdding: .day, value: -$0.offset, to: today)! })
        let strength = workouts.filter { $0.session != nil }
        for (number, plan) in strength.enumerated() {
            guard let session = plan.session else { continue }
            let weeks = Double(number) / 4
            let deload = deloadDays.contains(calendar.startOfDay(for: plan.start))
            var clock = plan.start.addingTimeInterval(6 * 60)
            var exercises: [LoggedExercise] = []
            for lift in Lifts.program[session]! {
                // ~1% stronger a week, a little better or worse depending on the day.
                let working = (lift.startKg * (1 + 0.011 * weeks) * (deload ? 0.85 : 1) / lift.increment).rounded() * lift.increment
                let repBonus = Int((plan.readiness * 1.4).rounded())
                var sets: [LoggedSet] = []
                if lift.warmup {
                    var warm = LoggedSet()
                    warm.kind = .warmup
                    warm.weightKg = (working * 0.6 / lift.increment).rounded() * lift.increment
                    warm.reps = 8
                    warm.completed = true
                    warm.completedAt = clock
                    clock = clock.addingTimeInterval(90)
                    sets.append(warm)
                }
                for i in 0..<(deload ? lift.sets - 1 : lift.sets) {
                    var set = LoggedSet()
                    set.weightKg = lift.bodyweight ? nil : working
                    set.reps = max(lift.reps.lowerBound - 1,
                                   min(lift.reps.upperBound + 1, lift.reps.upperBound - i + repBonus + Int.random(in: -1...0)))
                    set.rir = max(0, 2 - i + repBonus)
                    set.completed = true
                    set.completedAt = clock
                    clock = clock.addingTimeInterval(Double(lift.rest) + 45)
                    sets.append(set)
                }
                exercises.append(LoggedExercise(exerciseID: lift.id, name: lift.name, primaryMuscle: lift.muscle,
                                                tracking: lift.bodyweight ? .reps : .weightReps, restSeconds: lift.rest, sets: sets))
            }
            let log = WorkoutLog(name: session.rawValue, routineID: routines[session]?.id, start: plan.start, end: plan.end,
                                 exercises: exercises)
            log.calories = plan.kcal
            log.averageHeartRate = (plan.bpmRange.lowerBound + plan.bpmRange.upperBound) / 2 - 8
            log.maxHeartRate = plan.bpmRange.upperBound + 4
            log.savedToHealth = true
            context.insert(log)
            routines[session]?.lastPerformed = plan.start
        }
        try context.save()
    }

    private struct Lift {
        let id: String, name: String, muscle: String
        let sets: Int, reps: ClosedRange<Int>, rest: Int
        let startKg: Double
        var increment = 2.5
        var warmup = false
        var bodyweight = false
    }

    private enum Lifts {
        static let program: [Session: [Lift]] = [
            .push: [
                Lift(id: "Barbell_Bench_Press_-_Medium_Grip", name: "Barbell Bench Press - Medium Grip", muscle: "chest",
                     sets: 4, reps: 5...8, rest: 150, startKg: 80, warmup: true),
                Lift(id: "Standing_Military_Press", name: "Standing Military Press", muscle: "shoulders",
                     sets: 3, reps: 6...10, rest: 120, startKg: 47.5),
                Lift(id: "Incline_Dumbbell_Press", name: "Incline Dumbbell Press", muscle: "chest",
                     sets: 3, reps: 8...12, rest: 90, startKg: 26, increment: 2),
                Lift(id: "Side_Lateral_Raise", name: "Side Lateral Raise", muscle: "shoulders",
                     sets: 3, reps: 12...15, rest: 60, startKg: 10, increment: 1),
                Lift(id: "Triceps_Pushdown", name: "Triceps Pushdown", muscle: "triceps",
                     sets: 3, reps: 10...12, rest: 60, startKg: 30)
            ],
            .pull: [
                Lift(id: "Barbell_Deadlift", name: "Barbell Deadlift", muscle: "lower back",
                     sets: 3, reps: 4...6, rest: 180, startKg: 140, increment: 5, warmup: true),
                Lift(id: "Pullups", name: "Pullups", muscle: "lats",
                     sets: 3, reps: 6...10, rest: 120, startKg: 0, bodyweight: true),
                Lift(id: "Seated_Cable_Rows", name: "Seated Cable Rows", muscle: "middle back",
                     sets: 3, reps: 8...12, rest: 90, startKg: 65),
                Lift(id: "Face_Pull", name: "Face Pull", muscle: "shoulders",
                     sets: 3, reps: 12...15, rest: 60, startKg: 25),
                Lift(id: "Hammer_Curls", name: "Hammer Curls", muscle: "biceps",
                     sets: 3, reps: 10...12, rest: 60, startKg: 16, increment: 2)
            ],
            .legs: [
                Lift(id: "Barbell_Squat", name: "Barbell Squat", muscle: "quadriceps",
                     sets: 4, reps: 5...8, rest: 180, startKg: 110, warmup: true),
                Lift(id: "Romanian_Deadlift", name: "Romanian Deadlift", muscle: "hamstrings",
                     sets: 3, reps: 8...10, rest: 120, startKg: 90),
                Lift(id: "Leg_Press", name: "Leg Press", muscle: "quadriceps",
                     sets: 3, reps: 10...12, rest: 120, startKg: 180, increment: 5),
                Lift(id: "Lying_Leg_Curls", name: "Lying Leg Curls", muscle: "hamstrings",
                     sets: 3, reps: 10...12, rest: 60, startKg: 40),
                Lift(id: "Standing_Calf_Raises", name: "Standing Calf Raises", muscle: "calves",
                     sets: 4, reps: 10...15, rest: 60, startKg: 70, increment: 5)
            ],
            .upper: [
                Lift(id: "Bent_Over_Barbell_Row", name: "Bent Over Barbell Row", muscle: "middle back",
                     sets: 4, reps: 6...10, rest: 120, startKg: 72.5, warmup: true),
                Lift(id: "Incline_Dumbbell_Press", name: "Incline Dumbbell Press", muscle: "chest",
                     sets: 3, reps: 8...12, rest: 90, startKg: 26, increment: 2),
                Lift(id: "Wide-Grip_Lat_Pulldown", name: "Wide-Grip Lat Pulldown", muscle: "lats",
                     sets: 3, reps: 8...12, rest: 90, startKg: 62.5),
                Lift(id: "Dumbbell_Bicep_Curl", name: "Dumbbell Bicep Curl", muscle: "biceps",
                     sets: 3, reps: 10...12, rest: 60, startKg: 14, increment: 2),
                Lift(id: "Dips_-_Triceps_Version", name: "Dips - Triceps Version", muscle: "triceps",
                     sets: 3, reps: 8...12, rest: 90, startKg: 0, bodyweight: true)
            ]
        ]
    }

    // MARK: - Foods and meals (per 100 g, USDA FoodData Central values)

    private enum Meals {
        static func food(_ name: String, _ kcal: Double, _ p: Double, _ c: Double, _ f: Double,
                         density: Double? = nil) -> FoodItem {
            FoodItem(id: "sample-\(name)", name: name, brand: nil, kcal: kcal, protein: p, carbs: c, fat: f,
                     source: .usda, barcode: nil, servingGrams: nil, density: density)
        }
        static let oats = food("Oats, rolled", 379, 13.2, 67.7, 6.5)
        static let milk = food("Milk, whole", 61, 3.2, 4.8, 3.3, density: 1.03)
        static let banana = food("Banana", 89, 1.1, 22.8, 0.3)
        static let whey = food("Whey protein powder", 400, 80, 8, 6)
        static let yogurt = food("Greek yogurt, 2%", 73, 9.9, 3.9, 2.0)
        static let blueberries = food("Blueberries", 57, 0.7, 14.5, 0.3)
        static let eggs = food("Eggs, scrambled", 149, 10, 1.6, 11)
        static let bread = food("Whole wheat bread", 252, 12.4, 42.7, 3.5)
        static let chicken = food("Chicken breast, roasted", 165, 31, 0, 3.6)
        static let rice = food("White rice, cooked", 130, 2.7, 28.2, 0.3)
        static let broccoli = food("Broccoli, boiled", 35, 2.4, 7.2, 0.4)
        static let oil = food("Olive oil", 884, 0, 0, 100, density: 0.91)
        static let salmon = food("Salmon, baked", 206, 22.1, 0, 12.4)
        static let potatoes = food("Potatoes, boiled", 87, 1.9, 20.1, 0.1)
        static let beef = food("Ground beef 90% lean, cooked", 217, 26.1, 0, 11.8)
        static let pasta = food("Pasta, cooked", 158, 5.8, 30.9, 0.9)
        static let marinara = food("Tomato sauce", 50, 1.4, 8, 1.5)
        static let almonds = food("Almonds", 579, 21.2, 21.6, 49.9)
        static let apple = food("Apple", 52, 0.3, 13.8, 0.2)
        static let cottage = food("Cottage cheese", 98, 11.1, 3.4, 4.3)

        static let breakfastA: [(FoodItem, Double)] = [(oats, 80), (milk, 250), (banana, 120), (whey, 30)]
        static let breakfastB: [(FoodItem, Double)] = [(eggs, 150), (bread, 80), (yogurt, 200), (blueberries, 100)]
        static let lunchA: [(FoodItem, Double)] = [(chicken, 200), (rice, 250), (broccoli, 150), (oil, 10)]
        static let lunchB: [(FoodItem, Double)] = [(beef, 150), (pasta, 250), (marinara, 150)]
        static let dinnerA: [(FoodItem, Double)] = [(salmon, 180), (potatoes, 300), (broccoli, 150), (oil, 10)]
        static let dinnerB: [(FoodItem, Double)] = [(chicken, 180), (rice, 220), (broccoli, 120), (oil, 8)]
        static let snackA: [(FoodItem, Double)] = [(yogurt, 250), (almonds, 25), (apple, 150)]
        static let snackB: [(FoodItem, Double)] = [(cottage, 200), (banana, 100)]
    }
}
#endif
