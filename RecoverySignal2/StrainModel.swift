//
//  StrainModel.swift
//  RecoverySignal2
//
//  Day strain (0–21): cardiovascular load from heart rate across the whole
//  day, on a saturating scale. Tunable below.
//
//  STRAIN
//  Heart rate across the whole day is turned into cardiovascular load: each
//  minute counts by the heart-rate-reserve zone it falls in, so time at high
//  intensity weighs far more than time spent near resting.
//
//    HRR%  = (HR − resting HR) ÷ (max HR − resting HR)
//    zone weight: <50% → 0, 50–60 → 1, 60–70 → 2, 70–80 → 3, 80–90 → 4, ≥90 → 5
//    load  = Σ minutes × zone weight
//    strain = 21 × (1 − e^(−load ÷ 180))
//
//  The saturating curve makes each point harder to earn as strain climbs:
//  going 5 → 6 takes about 12 load units, 18 → 19 takes about 60.
//
import Foundation

enum StrainModel {

    static let maximum = 21.0
    /// Load at which strain reaches ~63% of the scale (≈13.3).
    static let loadScale = 180.0
    /// Gaps longer than this between readings aren't assumed to be sustained effort.
    static let maxGapMinutes = 5.0

    static func zoneWeight(heartRateReserve hrr: Double) -> Double {
        switch hrr {
        case ..<0.5: 0
        case ..<0.6: 1
        case ..<0.7: 2
        case ..<0.8: 3
        case ..<0.9: 4
        default:     5
        }
    }

    static func load(heartRates: [(date: Date, bpm: Double)], restingHR: Double, maxHR: Double) -> Double {
        guard maxHR > restingHR, heartRates.count >= 2 else { return 0 }
        let sorted = heartRates.sorted { $0.date < $1.date }
        var total = 0.0
        for (current, next) in zip(sorted, sorted.dropFirst()) {
            let minutes = min(next.date.timeIntervalSince(current.date) / 60, maxGapMinutes)
            let hrr = (current.bpm - restingHR) / (maxHR - restingHR)
            total += minutes * zoneWeight(heartRateReserve: hrr)
        }
        return total
    }

    /// Minutes at light (30–40%), moderate (40–60%) and vigorous (≥60%) heart
    /// rate reserve — the ACSM intensity bands used in activity guidelines.
    static func intensityMinutes(heartRates: [(date: Date, bpm: Double)], restingHR: Double, maxHR: Double)
        -> (light: Double, moderate: Double, vigorous: Double) {
        guard maxHR > restingHR, heartRates.count >= 2 else { return (0, 0, 0) }
        let sorted = heartRates.sorted { $0.date < $1.date }
        var light = 0.0, moderate = 0.0, vigorous = 0.0
        for (current, next) in zip(sorted, sorted.dropFirst()) {
            let minutes = min(next.date.timeIntervalSince(current.date) / 60, maxGapMinutes)
            let hrr = (current.bpm - restingHR) / (maxHR - restingHR)
            switch hrr {
            case 0.6...: vigorous += minutes
            case 0.4..<0.6: moderate += minutes
            case 0.3..<0.4: light += minutes
            default: break
            }
        }
        return (light, moderate, vigorous)
    }

    static func strain(fromLoad load: Double) -> Double {
        maximum * (1 - exp(-load / loadScale))
    }

    enum Level {
        case light, moderate, high, allOut

        init(_ strain: Double) {
            switch strain {
            case ..<10: self = .light
            case ..<14: self = .moderate
            case ..<18: self = .high
            default:    self = .allOut
            }
        }

        var label: String {
            switch self {
            case .light:    String(localized: "Light")
            case .moderate: String(localized: "Moderate")
            case .high:     String(localized: "High")
            case .allOut:   String(localized: "All out")
            }
        }
    }
}
