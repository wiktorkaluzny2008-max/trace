//
//  Goal.swift
//  RecoverySignal2
//
//  What you're trying to do with your body, and what that means for intake.
//
//  Calorie target = maintenance + (target rate × 7700 kcal/kg ÷ 7). Protein
//  rises in a deficit (more lean mass is at risk) and sits a little above
//  maintenance level in a surplus. The target is never allowed below resting
//  energy — eating less than your body burns at rest is a crash diet, not a cut.
//

import Foundation

nonisolated struct GoalSettings: Equatable, Sendable {

    enum Phase: String, CaseIterable, Identifiable, Sendable {
        case cut, maintain, bulk

        var id: String { rawValue }

        var label: String {
            switch self {
            case .cut:      String(localized: "Lose fat")
            case .maintain: String(localized: "Maintain")
            case .bulk:     String(localized: "Build muscle")
            }
        }

        /// Selectable rates in kg/week (sign applied separately).
        var rateOptions: [Double] {
            switch self {
            case .cut:      [0.25, 0.5, 0.75]
            case .maintain: [0]
            case .bulk:     [0.1, 0.25, 0.4]
            }
        }

        /// Upper limit for a custom pace, kg/week.
        var maxRate: Double {
            switch self {
            case .cut:      1.5
            case .maintain: 0
            case .bulk:     1.0
            }
        }

        var defaultRate: Double {
            switch self {
            case .cut:      0.5
            case .maintain: 0
            case .bulk:     0.25
            }
        }

        var proteinGramsPerKg: Double {
            switch self {
            case .cut:      2.0
            case .maintain: 1.6
            case .bulk:     1.8
            }
        }
    }

    var phase: Phase
    /// Magnitude in kg/week; direction comes from the phase.
    var rateKgPerWeek: Double
    /// Free text like "vegetarian, no nuts" — passed to recipe generation.
    var dietaryNotes: String

    var signedDailyAdjustment: Double {
        // 7700 kcal/kg, same constant as EnergyModel (kept literal so this
        // type stays free of main-actor state).
        let perDay = rateKgPerWeek * 7700 / 7
        switch phase {
        case .cut:      return -perDay
        case .maintain: return 0
        case .bulk:     return perDay
        }
    }

    // MARK: Persistence

    private static let phaseKey = "goal.phase"
    private static let rateKey = "goal.rate"
    private static let notesKey = "goal.dietaryNotes"

    static func load(from defaults: UserDefaults = .standard) -> GoalSettings {
        let phase = defaults.string(forKey: phaseKey).flatMap(Phase.init(rawValue:)) ?? .maintain
        let rate = defaults.object(forKey: rateKey) as? Double ?? phase.defaultRate
        return GoalSettings(phase: phase, rateKgPerWeek: rate, dietaryNotes: defaults.string(forKey: notesKey) ?? "")
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(phase.rawValue, forKey: Self.phaseKey)
        defaults.set(rateKgPerWeek, forKey: Self.rateKey)
        defaults.set(dietaryNotes, forKey: Self.notesKey)
    }
}
