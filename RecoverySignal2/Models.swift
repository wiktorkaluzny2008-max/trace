//
//  Models.swift
//  RecoverySignal
//
//  Local persistence for computed daily rollups. Raw samples always stay in
//  HealthKit — we only cache what we derive from them, so re-installing the
//  app never loses source data, only the trend history we've computed.
//

import Foundation
import SwiftData

/// One calendar day's worth of aggregated biomarkers + nutrition.
/// Any field can be nil — a day with no Watch worn, or no food logged,
/// simply has gaps, and the aggregation/insight code is written to tolerate that.
@Model
final class DailyMetrics {
    @Attribute(.unique) var date: Date // normalized to midnight local time

    // Recovery / cardiovascular
    var hrvSDNN: Double?          // ms, average of the day's HRV samples
    var restingHeartRate: Double? // bpm
    var vo2Max: Double?           // ml/kg/min, sparse (Watch estimates infrequently)
    /// Heart rate drop in the first minute after a Workout-app session ends, bpm.
    var heartRateRecovery: Double?
    var oxygenSaturation: Double? // fraction 0-1

    // Sleep
    var sleepDurationHours: Double?
    var sleepAsleepHours: Double?   // time actually asleep vs just in bed
    var sleepDeepHours: Double?
    var sleepREMHours: Double?
    var sleepAwakeHours: Double?
    /// Daytime naps on this day, which reduce tonight's sleep need.
    var napHours: Double?
    /// First and last moment asleep for the night ending this morning.
    var sleepStart: Date?
    var sleepEnd: Date?
    /// Minutes it took to fall asleep, when the night records when you got into bed.
    var sleepLatencyMinutes: Double?
    /// Awake time between falling asleep and waking up for good.
    var sleepWakeAfterOnsetHours: Double?
    /// Average breaths per minute, measured by the Watch during sleep.
    var respiratoryRate: Double?
    /// Wrist skin temperature overnight, °C. Apple Watch Series 8+ / Ultra only.
    var wristTemperature: Double?

    // Activity
    var steps: Double?
    var activeEnergyBurned: Double?  // kcal
    /// Apple Watch "Resting Energy" — what the body burns just staying alive.
    /// Only accrues while the Watch is worn, so part-wear days read low.
    var basalEnergyKcal: Double?
    /// Apple's exercise ring minutes (brisk-walk intensity or harder).
    var exerciseMinutes: Double?
    /// Minutes spent at light (30–40%), moderate (40–60%) and vigorous (≥60%)
    /// heart-rate reserve, from the day's heart-rate stream.
    var lightMinutes: Double?
    var moderateMinutes: Double?
    var vigorousMinutes: Double?
    var hadWorkout: Bool = false
    var workoutIsResistance: Bool = false

    // Training detail. Whatever writes workouts into Health lands here — the
    // Watch's Workout app, Hevy, Strong, Strava. Note that Health stores
    // session-level data only: there are no sets/reps/loads to read.
    var workoutCount: Int = 0
    var workoutMinutes: Double?
    var workoutEnergyKcal: Double?
    var workoutAvgHeartRate: Double?
    var strengthMinutes: Double?
    var cardioMinutes: Double?
    var primaryWorkoutName: String?
    /// Banister TRIMP summed across the day's sessions — the load unit that
    /// feeds acute:chronic workload ratio.
    var trainingLoad: Double?
    /// Day strain, 0–21, from heart rate across the whole day.
    var strain: Double?

    // Body
    var bodyMassKg: Double?
    /// Only present if a smart scale (or manual entry) writes these to Health.
    /// Energy Availability and P-ratio depend on them.
    var bodyFatPercent: Double?
    var leanBodyMassKg: Double?

    // Mobility — measured by the iPhone in your pocket while walking.
    var walkingSpeed: Double?          // m/s
    var walkingStepLength: Double?     // cm
    var walkingAsymmetry: Double?      // % of steps
    var walkingDoubleSupport: Double?  // % of the gait cycle with both feet down
    var walkingSteadiness: Double?     // %, Apple's fall-risk score

    // Nutrition (from Yazio via HealthKit)
    var dietaryEnergyKcal: Double?
    var proteinGrams: Double?
    var carbsGrams: Double?
    var fatGrams: Double?
    var fiberGrams: Double?
    var sugarGrams: Double?
    /// From quick-add buttons or any app that writes to Health.
    var waterMl: Double?
    var caffeineMg: Double?
    /// The share of today's caffeine taken at or after 2pm local time — a
    /// fixed sleep-hygiene cutoff, not personalised to your own bedtime.
    var lateCaffeineMg: Double?

    init(date: Date) {
        self.date = date
    }
}

enum InsightSeverity: String, Codable {
    case info, notice, warning
}

/// A single rule-engine finding, persisted so we can show history and avoid
/// re-surfacing the same flag every single day.
@Model
final class Insight {
    var id: UUID
    var date: Date
    var title: String
    var detail: String
    var severityRaw: String
    var category: String // "recovery", "sleep", "nutrition", "body"

    var severity: InsightSeverity {
        get { InsightSeverity(rawValue: severityRaw) ?? .info }
        set { severityRaw = newValue.rawValue }
    }

    init(date: Date, title: String, detail: String, severity: InsightSeverity, category: String) {
        self.id = UUID()
        self.date = date
        self.title = title
        self.detail = detail
        self.severityRaw = severity.rawValue
        self.category = category
    }
}

/// The AI-generated weekly narrative summary.
@Model
final class WeeklyNarrative {
    var id: UUID
    var weekStartDate: Date
    var text: String
    var generatedAt: Date

    init(weekStartDate: Date, text: String) {
        self.id = UUID()
        self.weekStartDate = weekStartDate
        self.text = text
        self.generatedAt = Date()
    }
}
