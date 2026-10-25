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
    var oxygenSaturation: Double? // fraction 0-1

    // Sleep
    var sleepDurationHours: Double?
    var sleepAsleepHours: Double?   // time actually asleep vs just in bed
    var sleepDeepHours: Double?
    var sleepREMHours: Double?

    // Activity
    var steps: Double?
    var activeEnergyBurned: Double?  // kcal
    var hadWorkout: Bool = false
    var workoutIsResistance: Bool = false

    // Body
    var bodyMassKg: Double?

    // Nutrition (from Yazio via HealthKit)
    var dietaryEnergyKcal: Double?
    var proteinGrams: Double?
    var carbsGrams: Double?
    var fatGrams: Double?
    var fiberGrams: Double?
    var sugarGrams: Double?

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
